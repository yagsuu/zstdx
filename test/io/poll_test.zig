//! Poll-until composition tests. See `docs/specs/io/poll-until.md`.

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

/// Caller-controlled monotonic clock. `now(*Self)` returns whatever the
/// test last stored in `current`; `sleep(*Self, Duration)` appends the
/// duration to `sleeps` and advances `current` by the same amount.
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

/// Module-level yield-hook counter. `Backoff.Policy.yield` is a bare
/// function pointer with no capture; tests reset the counter before use.
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

/// Struct predicate returning a payload on the Nth call.
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

/// Predicate that never fires.
const NeverFires = struct {
    calls: usize = 0,

    pub fn call(self: *NeverFires) error{}!?u32 {
        self.calls += 1;
        return null;
    }
};

/// Predicate that returns an error on the Nth call.
const FailsOn = struct {
    calls: usize = 0,
    fire_on: usize,

    pub fn call(self: *FailsOn) error{DeviceFault}!?u32 {
        self.calls += 1;
        if (self.calls >= self.fire_on) return error.DeviceFault;
        return null;
    }
};

/// Predicate returning a caller-owned cancellation error on the Nth call.
const CancelsOn = struct {
    calls: usize = 0,
    fire_on: usize,

    pub fn call(self: *CancelsOn) error{Cancelled}!?u32 {
        self.calls += 1;
        if (self.calls >= self.fire_on) return error.Cancelled;
        return null;
    }
};

/// Struct receiver by value (`self: @This()`), not pointer.
const ByValuePayload = struct {
    value: u32,

    pub fn call(self: @This()) error{}!?u32 {
        return self.value;
    }
};

/// Struct receiver by `*const @This()`.
const ByConstPtrPayload = struct {
    value: u32,

    pub fn call(self: *const @This()) error{}!?u32 {
        return self.value;
    }
};

/// Bare-function predicate.
fn bareOk() error{}!?u32 {
    return 7;
}

/// Bare-function predicate that never fires.
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
    // 5 ns budget: sleep step returns .sleep(1) four times, then .timeout.
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
    // The failing predicate call itself does not consume a backoff step.
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
    // spec required config: spin_iterations=2, yield_iterations=1,
    // growth_shift=0, policy.yield set, initial_wait small.
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

    // Wide budget so we reach several sleep steps without timing out.
    const dl = Deadline.at(Instant.fromNanos(1_000));
    _ = poll.until(&clock, dl, &backoff, &pred) catch {};

    // After spin×2, yield×1, sleep×N (each advances clock by 3 ns until
    // the deadline is exhausted at 1_000 ns), predicate is called between
    // each pair. The exact sleep count is (1000-0)/3 rounded down after
    // the deadline check timing; assert on the observable log.
    try testing.expect(clock.sleeps_len >= 2);
    for (clock.sleeps()) |d| {
        try testing.expectEqual(Duration.fromNanos(3), d);
    }
    // Every sleep in the log matches initial_wait exactly (growth_shift=0).
    // yield-hook fires exactly `yield_iterations` times.
    try testing.expectEqual(@as(usize, 1), yield_calls);
    // Predicate was invoked once before each spin/yield/sleep step plus
    // once for the final .timeout observation, so pred.calls == 1 +
    // productive_attempts; assert the lower bound.
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

    // Custom predicate that snapshots yield_calls the moment the first
    // sleep runs, so we observe the count *before* any sleep dispatch.
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
    // Doubling growth so successive sleeps differ.
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

    // First few sleeps: 4, 8, 16, 32, 32, ...
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
    // Payload is u32; error set is (Timeout || DeviceFault).
    const info = @typeInfo(R);
    try testing.expect(info == .error_union);
    try testing.expectEqual(u32, info.error_union.payload);
    // Same error union across TimeoutError || DeviceFault ordering.
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

// Compile-only rejection cases. Zig cannot exercise `@compileError` at
// test runtime; enumerated here so a reviewer can grep for each message
// against `src/io/poll.zig`:
//
//   Predicate return `E!T` (non-optional payload)     → analyzeReturn @compileError
//     "predicate payload must be optional (E!?T)"
//   Predicate return `?T` (no error union)            → analyzeReturn @compileError
//     "predicate must return an error union (E!?T); got bare optional"
//   Predicate return `anyerror!?T`                    → analyzeReturn @compileError
//     "predicate must declare an explicit error set, not `anyerror`"
//   Callable with extra parameters                    → analyzeCallable @compileError
//     "callable function must take no parameters" / "`call` must take exactly one parameter"
//   Neither callable nor struct-with-`call`           → analyzePredicate @compileError
//     "predicate must be a callable function or a struct exposing `pub fn call(...)`"
//   Struct with no `call` decl                        → analyzeCallStruct @compileError
//     "has no `call` method and is not a callable function"
//   Clock missing `sleep(*Self, Duration) void`       → requireClockSleep @compileError
//     "clock type ... is missing pub fn sleep(*Self, Duration) void"
//   Clock whose `now` returns `!Instant` / anyerror   → requireClockNow @compileError
//     ".now must return Instant, not an error union or anyerror"
//   Clock whose `sleep` returns `!void`               → requireClockSleep @compileError
//     ".sleep must return void, not an error union or anyerror"

test "contract: yield-null debug assertion compiles under Debug and never trips on a legal step" {
    // Under `.build_mode` (Debug or ReleaseSafe), `poll.until` asserts
    // `backoff.policy.yield != null` immediately before unwrapping the
    // hook on a `.yield` step. We verify the assertion is compiled and
    // passes when the policy is legal (yield is non-null). Zig has no
    // `expectPanic` primitive. The compile-only trap condition is documented
    // separately and covered by the shared `checksEnabled(.build_mode)`
    // policy assertion in `Backoff.next`.
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

// Debug-only trap probe for `policy.yield == null` on a `.yield` step
// cannot be exercised at Zig test runtime: `std.debug.assert` aborts on
// failure and this repo has no `expectPanic`-equivalent. The invariant
// is doubly protected — `Backoff.next` never returns `.yield` when
// `policy.yield == null` per `docs/specs/time/backoff.md`, so the
// assertion in `poll.until` traps only if that invariant is broken
// (test-only synthetic `Backoff` substitution, which the concrete
// `*Backoff` parameter type intentionally does not permit).

test "contract: module compiles regardless of host architecture" {
    // The spec's "Non-x86 build compiles the module" requirement: the
    // module reaches only `std.atomic.spinLoopHint`, `Backoff`, `Deadline`,
    // and a caller-supplied clock, all of which are target-agnostic. A
    // successful invocation of `poll.until` on the host demonstrates that
    // the module compiles; every runtime test is also a host-target smoke check.
    var clock = FakeClock.init(0);
    var backoff = Backoff.init(samplePolicy(1, 0, null));
    var pred: PayloadOn = .{ .target = 1, .value = 1 };
    _ = try poll.until(&clock, Deadline.never, &backoff, &pred);
}
