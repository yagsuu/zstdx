//! Latch contract tests. Spec: docs/specs/sync/latch.md.

const std = @import("std");

const stdx = @import("stdx");

const State = stdx.sync.latch.State;
const Token = stdx.sync.latch.Token;
const Latch = stdx.sync.Latch;
const SpinBackend = stdx.sync.spin.Backend;

const testing = std.testing;

/// Mock backend recording wait/wake calls and optionally releasing the
/// state word between the waiter's observe and its parking step, so tests
/// can drive the lost-wakeup recheck deterministically without threads.
const TestBackend = struct {
    wait_calls: usize = 0,
    wake_calls: usize = 0,
    last_wake_state: ?*const State = null,
    fail_next_wait: bool = false,
    force_release: bool = false,
    payload_state: ?*State = null,

    pub const WaitError = error{Canceled};

    pub fn wait(self: *TestBackend, state: *const State, observed: Token) WaitError!void {
        self.wait_calls += 1;
        if (self.fail_next_wait) {
            self.fail_next_wait = false;
            return error.Canceled;
        }
        if (state.changedSince(observed)) return;
        if (self.force_release) {
            self.force_release = false;
            if (self.payload_state) |mut| mut.word.store(0, .release);
            return;
        }
        return error.Canceled;
    }

    pub fn wakeAll(self: *TestBackend, state: *const State) void {
        self.wake_calls += 1;
        self.last_wake_state = state;
    }
};

test "unit: latch State has 4-byte word layout" {
    try testing.expectEqual(@as(usize, 4), @sizeOf(State));
    try testing.expect(@alignOf(State) >= 4);
}

test "unit: latch State.init packs remaining count" {
    const s = State.init(7);
    try testing.expectEqual(@as(u32, 7), s.remaining());
    try testing.expect(!s.isReleased());
}

test "unit: latch Token unpacks remaining and isReleased" {
    var s = State.init(4);
    const t0 = s.observe();
    try testing.expectEqual(@as(u32, 4), t0.remaining());
    try testing.expect(!t0.isReleased());

    s.word.store(0, .release);
    const t1 = s.observe();
    try testing.expectEqual(@as(u32, 0), t1.remaining());
    try testing.expect(t1.isReleased());
}

test "unit: latch State.changedSince detects any word delta" {
    var s = State.init(4);
    const t = s.observe();
    try testing.expect(!s.changedSince(t));

    s.word.store(3, .release);
    try testing.expect(s.changedSince(t));

    s.word.store(4, .release);
    try testing.expect(!s.changedSince(t));
}

test "contract: Latch.Static(1) is the minimum legal capacity" {
    _ = Latch(SpinBackend).Static(1);
}

test "unit: Latch.Static(1) single arrive releases and wait fast-paths" {
    const L = Latch(TestBackend).Static(1);
    var l = L.init(.{});

    try testing.expectEqual(@as(u32, 1), l.pending());
    try testing.expectEqual(@as(u32, 1), l.capacity());
    try testing.expect(!l.isReleased());

    l.arrive();

    try testing.expectEqual(@as(u32, 0), l.pending());
    try testing.expect(l.isReleased());
    try testing.expectEqual(@as(usize, 1), l.backend.wake_calls);
    try testing.expectEqual(l.stateRef(), l.backend.last_wake_state.?);

    try l.wait();
    try testing.expectEqual(@as(usize, 0), l.backend.wait_calls);
}

test "unit: Latch.Static reports initial capacity, pending, and released" {
    const L = Latch(TestBackend).Static(4);
    var l = L.init(.{});

    try testing.expectEqual(@as(usize, 4), L.arrival_capacity);
    try testing.expectEqual(@as(u32, 4), l.capacity());
    try testing.expectEqual(@as(u32, 4), l.pending());
    try testing.expect(!l.isReleased());
}

test "unit: Latch.Static non-last arrivals decrement pending without wakeAll" {
    const L = Latch(TestBackend).Static(3);
    var l = L.init(.{});

    l.arrive();
    try testing.expectEqual(@as(u32, 2), l.pending());
    try testing.expect(!l.isReleased());
    try testing.expectEqual(@as(usize, 0), l.backend.wake_calls);

    l.arrive();
    try testing.expectEqual(@as(u32, 1), l.pending());
    try testing.expect(!l.isReleased());
    try testing.expectEqual(@as(usize, 0), l.backend.wake_calls);
}

test "unit: Latch.Static last arrival releases, wakes, and stays released" {
    const L = Latch(TestBackend).Static(3);
    var l = L.init(.{});

    l.arrive();
    l.arrive();
    l.arrive();

    try testing.expectEqual(@as(u32, 0), l.pending());
    try testing.expect(l.isReleased());
    try testing.expectEqual(@as(usize, 1), l.backend.wake_calls);
    try testing.expectEqual(l.stateRef(), l.backend.last_wake_state.?);

    // Sticky release: subsequent wait must fast-path.
    try testing.expect(l.isReleased());
    try l.wait();
    try testing.expectEqual(@as(usize, 0), l.backend.wait_calls);
}

test "unit: Latch.wait post-release fast-paths on the first observation" {
    const L = Latch(TestBackend).Static(1);
    var l = L.init(.{});

    l.arrive();
    try l.wait();
    try l.wait();
    try l.wait();

    try testing.expectEqual(@as(usize, 0), l.backend.wait_calls);
}

test "unit: Latch.wait propagates backend WaitError without touching state" {
    const L = Latch(TestBackend).Static(2);
    var l = L.init(.{ .fail_next_wait = true });

    l.arrive();
    try testing.expectEqual(@as(u32, 1), l.pending());
    try testing.expectError(error.Canceled, l.wait());
    try testing.expectEqual(@as(u32, 1), l.pending());
    try testing.expect(!l.isReleased());
    try testing.expectEqual(@as(usize, 1), l.backend.wait_calls);
    try testing.expectEqual(@as(usize, 0), l.backend.wake_calls);
}

test "unit: Latch.wait returns when backend releases mid-wait" {
    const L = Latch(TestBackend).Static(2);
    var l = L.init(.{});

    l.backend.payload_state = &l.state;
    l.backend.force_release = true;

    try l.wait();

    try testing.expect(l.isReleased());
    try testing.expectEqual(@as(usize, 1), l.backend.wait_calls);
    try testing.expectEqual(@as(usize, 0), l.backend.wake_calls);
}

test "unit: Latch.Bounded mirrors Static semantics for the same capacity" {
    const L = Latch(TestBackend);
    var l = L.Bounded.init(3, .{});

    try testing.expectEqual(@as(u32, 3), l.capacity());
    try testing.expectEqual(@as(u32, 3), l.pending());
    try testing.expect(!l.isReleased());

    l.arrive();
    l.arrive();
    try testing.expectEqual(@as(u32, 1), l.pending());
    try testing.expectEqual(@as(usize, 0), l.backend.wake_calls);

    l.arrive();
    try testing.expectEqual(@as(u32, 0), l.pending());
    try testing.expect(l.isReleased());
    try testing.expectEqual(@as(usize, 1), l.backend.wake_calls);
    try testing.expectEqual(l.stateRef(), l.backend.last_wake_state.?);
}

test "unit: Latch.Bounded wait fast-paths after release" {
    const L = Latch(TestBackend);
    var l = L.Bounded.init(2, .{});

    l.arrive();
    l.arrive();
    try l.wait();
    try testing.expectEqual(@as(usize, 0), l.backend.wait_calls);
}

test "unit: backend recheck observes release between token capture and wait" {
    const L = Latch(TestBackend).Static(2);
    var l = L.init(.{});

    const observed = l.stateRef().observe();
    try testing.expectEqual(@as(u32, 2), observed.remaining());

    l.state.word.store(0, .release);
    try l.backend.wait(l.stateRef(), observed);

    try testing.expect(l.isReleased());
    try testing.expectEqual(@as(usize, 1), l.backend.wait_calls);
}

test "contract: Latch(spin.Backend) instantiates for Static and Bounded" {
    _ = Latch(SpinBackend).Static(4);
    _ = Latch(SpinBackend).Bounded;
}

test "unit: Latch(spin.Backend).Static releases after N arrivals" {
    const L = Latch(SpinBackend).Static(4);
    var l = L.init(.{});

    var i: usize = 0;
    while (i < 4) : (i += 1) l.arrive();

    try testing.expect(l.isReleased());
    l.wait() catch unreachable;
}

test "unit: Latch(spin.Backend).Bounded releases after N arrivals" {
    const L = Latch(SpinBackend);
    var l = L.Bounded.init(3, .{});

    l.arrive();
    l.arrive();
    l.arrive();

    try testing.expect(l.isReleased());
    l.wait() catch unreachable;
}
