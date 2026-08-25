//! Poll-until composition tests. See `docs/specs/io/poll.md`.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const testing = std.testing;

const poll = stdx.io.poll;
const Backoff = stdx.time.Backoff;
const Deadline = stdx.time.Deadline;
const Duration = stdx.time.Duration;
const Instant = stdx.time.Instant;
const PollReturnType = poll.PollReturnType;

/// Deterministic clock that records sleeps and advances by their durations.
const FakeClock = struct {
    current: Instant = Instant.zero(),
    sleeps_buf: [64]Duration = undefined,
    sleeps_len: usize = 0,

    pub fn init(start_ns: u64) FakeClock {
        return .{ .current = Instant.fromNanos(start_ns) };
    }

    pub fn now(self: *FakeClock) Instant {
        return self.current;
    }

    pub fn sleep(self: *FakeClock, delta: Duration) void {
        if (self.sleeps_len < self.sleeps_buf.len) {
            self.sleeps_buf[self.sleeps_len] = delta;
            self.sleeps_len += 1;
        }
        const advanced: i128 = @as(i128, self.current.nanos()) + @as(i128, delta.nanos());
        std.debug.assert(advanced >= 0);
        std.debug.assert(advanced <= std.math.maxInt(u64));
        self.current = Instant.fromNanos(@intCast(advanced));
    }

    pub fn sleeps(self: *const FakeClock) []const Duration {
        return self.sleeps_buf[0..self.sleeps_len];
    }

    pub fn advance(self: *FakeClock, delta_ns: u64) void {
        self.current = Instant.fromNanos(self.current.nanos() + delta_ns);
    }
};

/// Yield-hook call count; `Backoff.Policy.yield` cannot capture state.
var yield_calls: usize = 0;

fn testYieldHook() void {
    yield_calls += 1;
}

fn samplePolicy(spin: u32, yield_iters: u32, yield_fn: ?*const fn () void) Backoff.Policy {
    return .{
        .spin_iterations = spin,
        .yield_iterations = yield_iters,
        .yield = yield_fn,
        .initial_wait = Duration.fromNanos(1),
        .max_wait = Duration.fromNanos(1_000_000),
        .growth_shift = 0,
    };
}

const PayloadOn = struct {
    calls: usize = 0,
    target: usize,
    value: u32,

    pub fn call(self: *PayloadOn) error{}!?u32 {
        self.calls += 1;
        if (self.calls >= self.target) return self.value;
        return null;
    }
};

const NeverFires = struct {
    calls: usize = 0,

    pub fn call(self: *NeverFires) error{}!?u32 {
        self.calls += 1;
        return null;
    }
};

const FailsOn = struct {
    calls: usize = 0,
    fire_on: usize,

    pub fn call(self: *FailsOn) error{DeviceFault}!?u32 {
        self.calls += 1;
        if (self.calls >= self.fire_on) return error.DeviceFault;
        return null;
    }
};

const CancelsOn = struct {
    calls: usize = 0,
    fire_on: usize,

    pub fn call(self: *CancelsOn) error{Cancelled}!?u32 {
        self.calls += 1;
        if (self.calls >= self.fire_on) return error.Cancelled;
        return null;
    }
};

const ByValuePayload = struct {
    value: u32,

    pub fn call(self: @This()) error{}!?u32 {
        return self.value;
    }
};

const ByConstPtrPayload = struct {
    value: u32,

    pub fn call(self: *const @This()) error{}!?u32 {
        return self.value;
    }
};

fn bareOk() error{}!?u32 {
    return 7;
}

fn bareNever() error{}!?u32 {
    return null;
}

test "unit: immediate success returns payload without touching backoff or clock" {
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(4, 0, null));
    var pred: PayloadOn = .{ .target = 1, .value = 42 };

    const result = try poll.until(&clock, Deadline.never, &backoff, &pred);
    try testing.expectEqual(@as(u32, 42), result);
    try testing.expectEqual(@as(u32, 0), backoff.attempts());
    try testing.expectEqual(@as(usize, 0), clock.sleeps_len);
    try testing.expectEqual(@as(usize, 1), pred.calls);
}

test "unit: late success after N nulls returns payload; attempts equals N" {
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(8, 0, null));
    var pred: PayloadOn = .{ .target = 5, .value = 99 };

    const result = try poll.until(&clock, Deadline.never, &backoff, &pred);
    try testing.expectEqual(@as(u32, 99), result);
    try testing.expectEqual(@as(u32, 4), backoff.attempts());
    try testing.expectEqual(@as(usize, 5), pred.calls);
}

test "unit: timeout when predicate never returns payload before deadline" {
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(0, 0, null));
    var pred: NeverFires = .{};
    // A 5 ns deadline yields four 1 ns sleeps before timeout.
    const dl = Deadline.at(Instant.fromNanos(5));

    const result = poll.until(&clock, dl, &backoff, &pred);
    try testing.expectError(error.Timeout, result);
    try testing.expect(pred.calls > 0);
}

test "unit: progress rule: expired deadline still runs predicate once" {
    var clock = FakeClock.init(1_000);
    var backoff = Backoff.init(samplePolicy(0, 0, null));
    var pred: PayloadOn = .{ .target = 1, .value = 5 };

    const dl = Deadline.at(clock.now());
    const result = try poll.until(&clock, dl, &backoff, &pred);
    try testing.expectEqual(@as(u32, 5), result);
    try testing.expectEqual(@as(usize, 1), pred.calls);
    try testing.expectEqual(@as(u32, 0), backoff.attempts());
}

test "unit: progress rule: expired deadline, predicate returns null → Timeout" {
    var clock = FakeClock.init(1_000);
    var backoff = Backoff.init(samplePolicy(0, 0, null));
    var pred: NeverFires = .{};

    const dl = Deadline.at(clock.now());
    const result = poll.until(&clock, dl, &backoff, &pred);
    try testing.expectError(error.Timeout, result);
    try testing.expectEqual(@as(usize, 1), pred.calls);
    try testing.expectEqual(@as(u32, 0), backoff.attempts());
}

test "unit: predicate error propagates unwrapped" {
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(4, 0, null));
    var pred: FailsOn = .{ .fire_on = 3 };

    const result = poll.until(&clock, Deadline.never, &backoff, &pred);
    try testing.expectError(error.DeviceFault, result);
    try testing.expectEqual(@as(usize, 3), pred.calls);
    // The terminating error does not advance backoff.
    try testing.expectEqual(@as(u32, 2), backoff.attempts());
}

test "unit: caller cancellation via predicate error propagates unchanged" {
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(0, 0, null));
    var pred: CancelsOn = .{ .fire_on = 2 };

    const result = poll.until(&clock, Deadline.never, &backoff, &pred);
    try testing.expectError(error.Cancelled, result);
    try testing.expectEqual(@as(usize, 2), pred.calls);
}

test "ordering: recorded step sequence follows predicate, spin, spin, yield, sleep, sleep" {
    yield_calls = 0;

    var clock = FakeClock.init(0);
    const p: Backoff.Policy = .{
        .spin_iterations = 2,
        .yield_iterations = 1,
        .yield = &testYieldHook,
        .initial_wait = Duration.fromNanos(3),
        .max_wait = Duration.fromNanos(3),
        .growth_shift = 0,
    };
    var backoff = Backoff.init(p);
    var pred: NeverFires = .{};

    // Avoid timeout before multiple sleep steps.
    const dl = Deadline.at(Instant.fromNanos(1_000));
    _ = poll.until(&clock, dl, &backoff, &pred) catch {};

    // `growth_shift = 0` keeps every recorded sleep at 3 ns.
    try testing.expect(clock.sleeps_len >= 2);
    for (clock.sleeps()) |d| {
        try testing.expectEqual(Duration.fromNanos(3), d);
    }
    // The yield hook runs once.
    try testing.expectEqual(@as(usize, 1), yield_calls);
    // Timeout adds one predicate call but no productive attempt.
    try testing.expect(pred.calls >= 1 + backoff.attempts());
}

test "unit: yield dispatch count matches yield_iterations before first sleep" {
    yield_calls = 0;

    var clock = FakeClock.init(0);
    const p: Backoff.Policy = .{
        .spin_iterations = 0,
        .yield_iterations = 4,
        .yield = &testYieldHook,
        .initial_wait = Duration.fromNanos(1_000_000_000),
        .max_wait = Duration.fromNanos(1_000_000_000),
        .growth_shift = 0,
    };
    var backoff = Backoff.init(p);

    // Records the yield count after the first sleep is observed.
    const Probe = struct {
        clock_ptr: *FakeClock,
        seen_first_sleep_yields: ?usize = null,
        calls: usize = 0,

        pub fn call(self: *@This()) error{}!?u32 {
            self.calls += 1;
            if (self.clock_ptr.sleeps_len > 0 and self.seen_first_sleep_yields == null) {
                self.seen_first_sleep_yields = yield_calls;
            }
            return null;
        }
    };

    var probe: Probe = .{ .clock_ptr = &clock };
    const dl = Deadline.at(Instant.fromNanos(1_500_000_000));
    _ = poll.until(&clock, dl, &backoff, &probe) catch {};

    try testing.expectEqual(@as(?usize, 4), probe.seen_first_sleep_yields);
}

test "unit: sleep dispatch fidelity records exact Backoff.next durations" {
    var clock = FakeClock.init(0);
    // `growth_shift = 1` doubles sleeps until they reach 32 ns.
    const p: Backoff.Policy = .{
        .spin_iterations = 0,
        .yield_iterations = 0,
        .yield = null,
        .initial_wait = Duration.fromNanos(4),
        .max_wait = Duration.fromNanos(32),
        .growth_shift = 1,
    };
    var backoff = Backoff.init(p);
    var pred: NeverFires = .{};

    const dl = Deadline.at(Instant.fromNanos(1_000_000));
    _ = poll.until(&clock, dl, &backoff, &pred) catch {};

    // The first five sleeps are 4, 8, 16, 32, and 32 ns.
    try testing.expect(clock.sleeps_len >= 5);
    try testing.expectEqual(Duration.fromNanos(4), clock.sleeps()[0]);
    try testing.expectEqual(Duration.fromNanos(8), clock.sleeps()[1]);
    try testing.expectEqual(Duration.fromNanos(16), clock.sleeps()[2]);
    try testing.expectEqual(Duration.fromNanos(32), clock.sleeps()[3]);
    try testing.expectEqual(Duration.fromNanos(32), clock.sleeps()[4]);
}

test "unit: method-object predicate (*Self receiver) composes" {
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(1, 0, null));
    var pred: PayloadOn = .{ .target = 1, .value = 11 };

    const got = try poll.until(&clock, Deadline.never, &backoff, &pred);
    try testing.expectEqual(@as(u32, 11), got);
}

test "unit: struct predicate with `self: @This()` receiver composes" {
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(1, 0, null));
    const pred: ByValuePayload = .{ .value = 21 };

    const got = try poll.until(&clock, Deadline.never, &backoff, pred);
    try testing.expectEqual(@as(u32, 21), got);
}

test "unit: struct predicate with `*const @This()` receiver composes" {
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(1, 0, null));
    const pred: ByConstPtrPayload = .{ .value = 31 };

    const got = try poll.until(&clock, Deadline.never, &backoff, &pred);
    try testing.expectEqual(@as(u32, 31), got);
}

test "unit: bare-function predicate value composes" {
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(1, 0, null));

    const got = try poll.until(&clock, Deadline.never, &backoff, bareOk);
    try testing.expectEqual(@as(u32, 7), got);
}

test "unit: bare-function pointer predicate composes" {
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(1, 0, null));
    const pred_ptr: *const fn () error{}!?u32 = &bareOk;

    const got = try poll.until(&clock, Deadline.never, &backoff, pred_ptr);
    try testing.expectEqual(@as(u32, 7), got);
}

test "unit: bare-function predicate returns Timeout when it never fires" {
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(0, 0, null));

    const dl = Deadline.at(Instant.fromNanos(2));
    const result = poll.until(&clock, dl, &backoff, bareNever);
    try testing.expectError(error.Timeout, result);
}

test "unit: PollReturnType identity for non-empty predicate error set" {
    const R = PollReturnType(*FailsOn);
    const info = @typeInfo(R);
    try testing.expect(info == .error_union);
    try testing.expectEqual(u32, info.error_union.payload);
    const Expected = (Deadline.TimeoutError || error{DeviceFault})!u32;
    try testing.expectEqual(Expected, R);
}

test "unit: PollReturnType collapses to Timeout-only for error{} predicate" {
    const R = PollReturnType(*PayloadOn);
    const Expected = Deadline.TimeoutError!u32;
    try testing.expectEqual(Expected, R);
}

test "unit: PollReturnType names bare-function predicate return" {
    const R = PollReturnType(@TypeOf(bareOk));
    const Expected = Deadline.TimeoutError!u32;
    try testing.expectEqual(Expected, R);
}

test "unit: PollReturnType names function-pointer predicate return" {
    const R = PollReturnType(*const fn () error{}!?u32);
    const Expected = Deadline.TimeoutError!u32;
    try testing.expectEqual(Expected, R);
}

test "unit: PollReturnType usable as an intermediate signature" {
    const Wrap = struct {
        fn run(clock: *FakeClock, backoff: *Backoff, pred: *PayloadOn) PollReturnType(*PayloadOn) {
            return poll.until(clock, Deadline.never, backoff, pred);
        }
    };
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(1, 0, null));
    var pred: PayloadOn = .{ .target = 1, .value = 55 };

    const got = try Wrap.run(&clock, &backoff, &pred);
    try testing.expectEqual(@as(u32, 55), got);
}

test "contract: PollReturnType compiles for every approved predicate shape" {
    comptime {
        _ = PollReturnType(*PayloadOn); // *Self receiver
        _ = PollReturnType(ByValuePayload); // self: @This()
        _ = PollReturnType(*const ByConstPtrPayload); // *const Self
        _ = PollReturnType(@TypeOf(bareOk)); // bare fn
        _ = PollReturnType(*const fn () error{}!?u32); // fn pointer
        _ = PollReturnType(*FailsOn); // non-empty predicate error set
        _ = PollReturnType(*CancelsOn); // caller cancellation error set
    }
}

test "contract: yield-null debug assertion compiles under Debug and never trips on a legal step" {
    // A legal yield executes the debug assertion before invoking the hook.
    if (builtin.mode != .Debug) return;

    yield_calls = 0;
    var clock = FakeClock.init(0);
    const p: Backoff.Policy = .{
        .spin_iterations = 0,
        .yield_iterations = 3,
        .yield = &testYieldHook,
        .initial_wait = Duration.fromNanos(1),
        .max_wait = Duration.fromNanos(1),
        .growth_shift = 0,
    };
    var backoff = Backoff.init(p);
    var pred: NeverFires = .{};

    const dl = Deadline.at(Instant.fromNanos(1_000));
    _ = poll.until(&clock, dl, &backoff, &pred) catch {};

    try testing.expectEqual(@as(usize, 3), yield_calls);
}

test "contract: module compiles on the host architecture" {
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(1, 0, null));
    var pred: PayloadOn = .{ .target = 1, .value = 1 };
    _ = try poll.until(&clock, Deadline.never, &backoff, &pred);
}
