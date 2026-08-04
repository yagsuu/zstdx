//! Rendezvous contract tests. See `docs/specs/sync/rendezvous.md`.

const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;

const State = stdx.sync.rendezvous.State;
const Token = stdx.sync.rendezvous.Token;
const Rendezvous = stdx.sync.Rendezvous;

// Test backend that records `wait`/`wakeAll` invocations and drives the
// wait loop deterministically. When `wait` is called the backend either
// returns success (letting the caller re-observe the state), returns the
// injected error, or asserts that the state has changed since the token
// was captured.
const TestBackend = struct {
    wait_calls: usize = 0,
    wake_calls: usize = 0,
    last_wake_state: ?*const State = null,
    force_generation_advance: bool = false,
    payload_state: ?*State = null,
    fail_next_wait: bool = false,

    pub const WaitError = error{Canceled};

    pub fn wait(self: *TestBackend, state: *const State, observed: Token) WaitError!void {
        self.wait_calls += 1;
        if (self.fail_next_wait) {
            self.fail_next_wait = false;
            return error.Canceled;
        }
        if (state.changedSince(observed)) return;
        if (self.force_generation_advance) {
            self.force_generation_advance = false;
            if (self.payload_state) |mut| {
                const current = mut.word.load(.acquire);
                const cur_remaining = unpackSpecRemaining(current);
                const cur_generation = unpackSpecGeneration(current);
                mut.word.store(packSpec(cur_remaining, cur_generation +% 1), .release);
            }
            return;
        }
        return error.Canceled;
    }

    pub fn wakeAll(self: *TestBackend, state: *const State) void {
        self.wake_calls += 1;
        self.last_wake_state = state;
    }
};

const SpinBackend = stdx.sync.spin.Backend;

test "unit: rendezvous State has 8-byte word layout" {
    try testing.expectEqual(@as(usize, 8), @sizeOf(State));
    try testing.expect(@alignOf(State) >= 8);
}

test "unit: rendezvous State.init packs remaining and zero generation" {
    const s = State.init(7);
    try testing.expectEqual(@as(u32, 7), s.remaining());
    try testing.expectEqual(@as(u32, 0), s.generation());
}

test "unit: rendezvous Token unpacks remaining and generation fields" {
    var s = State.init(4);
    const t0 = s.observe();
    try testing.expectEqual(@as(u32, 4), t0.remaining());
    try testing.expectEqual(@as(u32, 0), t0.generation());

    s.word.store(packSpec(2, 3), .release);
    const t1 = s.observe();
    try testing.expectEqual(@as(u32, 2), t1.remaining());
    try testing.expectEqual(@as(u32, 3), t1.generation());
}

test "unit: rendezvous State.changedSince tracks only generation advance" {
    var s = State.init(4);
    const t = s.observe();
    try testing.expect(!s.changedSince(t));

    s.word.store(packSpec(3, 0), .release);
    try testing.expect(!s.changedSince(t));

    s.word.store(packSpec(4, 1), .release);
    try testing.expect(s.changedSince(t));
}

test "contract: Rendezvous.Static(1) is the minimum legal capacity" {
    _ = Rendezvous(SpinBackend).Static(1);
}

test "unit: Rendezvous.Static(1) returns immediately and advances generation" {
    const Rv = Rendezvous(SpinBackend).Static(1);
    var rv = Rv.init(.{});

    try testing.expectEqual(@as(u32, 1), rv.pending());
    try testing.expectEqual(@as(u32, 0), rv.generation());

    try rv.arrive();
    try testing.expectEqual(@as(u32, 1), rv.pending());
    try testing.expectEqual(@as(u32, 1), rv.generation());

    try rv.arrive();
    try testing.expectEqual(@as(u32, 1), rv.pending());
    try testing.expectEqual(@as(u32, 2), rv.generation());
}

test "unit: Rendezvous.Static reports initial capacity, pending, and generation" {
    const Rv = Rendezvous(TestBackend).Static(4);
    var rv = Rv.init(.{});

    try testing.expectEqual(@as(usize, 4), Rv.party_capacity);
    try testing.expectEqual(@as(u32, 4), rv.capacity());
    try testing.expectEqual(@as(u32, 4), rv.pending());
    try testing.expectEqual(@as(u32, 0), rv.generation());
}

test "unit: Rendezvous.Static non-last arriver decrements pending and calls backend.wait" {
    const Rv = Rendezvous(TestBackend).Static(3);
    var rv = Rv.init(.{ .fail_next_wait = true });

    try testing.expectError(error.Canceled, rv.arrive());
    try testing.expectEqual(@as(u32, 2), rv.pending());
    try testing.expectEqual(@as(u32, 0), rv.generation());
    try testing.expectEqual(@as(usize, 1), rv.backend.wait_calls);
    try testing.expectEqual(@as(usize, 0), rv.backend.wake_calls);
}

test "unit: Rendezvous.Static last arriver advances generation and wakes waiters" {
    const Rv = Rendezvous(TestBackend).Static(3);
    var rv = Rv.init(.{ .fail_next_wait = true });

    try testing.expectError(error.Canceled, rv.arrive());
    rv.backend.fail_next_wait = true;
    try testing.expectError(error.Canceled, rv.arrive());
    try testing.expectEqual(@as(u32, 1), rv.pending());
    try testing.expectEqual(@as(usize, 0), rv.backend.wake_calls);

    try rv.arrive();
    try testing.expectEqual(@as(u32, 3), rv.pending());
    try testing.expectEqual(@as(u32, 1), rv.generation());
    try testing.expectEqual(@as(usize, 1), rv.backend.wake_calls);
    try testing.expectEqual(rv.stateRef(), rv.backend.last_wake_state.?);
}

test "unit: Rendezvous.Static cycles across generations with the same capacity" {
    const Rv = Rendezvous(TestBackend).Static(2);
    var rv = Rv.init(.{ .fail_next_wait = true });

    try testing.expectError(error.Canceled, rv.arrive());
    try rv.arrive();
    try testing.expectEqual(@as(u32, 2), rv.pending());
    try testing.expectEqual(@as(u32, 1), rv.generation());

    rv.backend.fail_next_wait = true;
    try testing.expectError(error.Canceled, rv.arrive());
    try rv.arrive();
    try testing.expectEqual(@as(u32, 2), rv.pending());
    try testing.expectEqual(@as(u32, 2), rv.generation());
    try testing.expectEqual(@as(usize, 2), rv.backend.wake_calls);
}

test "unit: Rendezvous.Static non-last arriver returns when generation advances mid-wait" {
    const Rv = Rendezvous(TestBackend).Static(2);
    var rv = Rv.init(.{});

    rv.backend.payload_state = &rv.state;
    rv.backend.force_generation_advance = true;

    try rv.arrive();
    try testing.expectEqual(@as(u32, 1), rv.generation());
    try testing.expectEqual(@as(usize, 1), rv.backend.wait_calls);
    try testing.expectEqual(@as(usize, 0), rv.backend.wake_calls);
}

test "unit: Rendezvous.Bounded matches Static semantics for the same capacity" {
    const Rv = Rendezvous(TestBackend);
    var rv = Rv.Bounded.init(3, .{ .fail_next_wait = true });

    try testing.expectEqual(@as(u32, 3), rv.capacity());
    try testing.expectEqual(@as(u32, 3), rv.pending());
    try testing.expectEqual(@as(u32, 0), rv.generation());

    try testing.expectError(error.Canceled, rv.arrive());
    rv.backend.fail_next_wait = true;
    try testing.expectError(error.Canceled, rv.arrive());
    try testing.expectEqual(@as(u32, 1), rv.pending());

    try rv.arrive();
    try testing.expectEqual(@as(u32, 3), rv.pending());
    try testing.expectEqual(@as(u32, 1), rv.generation());
    try testing.expectEqual(@as(usize, 1), rv.backend.wake_calls);
    try testing.expectEqual(rv.stateRef(), rv.backend.last_wake_state.?);
}

test "unit: Rendezvous.Bounded reuses generation counter across rounds" {
    const Rv = Rendezvous(TestBackend);
    var rv = Rv.Bounded.init(2, .{});

    rv.backend.payload_state = &rv.state;
    rv.backend.force_generation_advance = true;
    try rv.arrive();
    try testing.expectEqual(@as(u32, 1), rv.generation());

    rv.backend.force_generation_advance = true;
    try rv.arrive();
    try testing.expectEqual(@as(u32, 2), rv.generation());
}

test "unit: backend recheck observes generation advance between token and wait" {
    const Rv = Rendezvous(TestBackend).Static(2);
    var rv = Rv.init(.{});

    const observed = rv.stateRef().observe();
    try testing.expectEqual(@as(u32, 2), observed.remaining());

    rv.state.word.store(packSpec(2, 1), .release);
    try rv.backend.wait(rv.stateRef(), observed);

    try testing.expectEqual(@as(u32, 1), rv.generation());
    try testing.expectEqual(@as(usize, 1), rv.backend.wait_calls);
}

test "contract: Rendezvous(spin.Backend) instantiates for Static and Bounded" {
    _ = Rendezvous(SpinBackend).Static(4);
    _ = Rendezvous(SpinBackend).Bounded;
}

fn packSpec(remaining: u32, generation: u32) u64 {
    return @as(u64, remaining) | (@as(u64, generation) << 32);
}

fn unpackSpecRemaining(word: u64) u32 {
    return @intCast(word & ((@as(u64, 1) << 32) - 1));
}

fn unpackSpecGeneration(word: u64) u32 {
    return @intCast(word >> 32);
}
