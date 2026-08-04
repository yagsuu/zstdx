//! Once contract tests. See `docs/specs/sync/once.md`.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const testing = std.testing;
const sync = stdx.sync;
const AtomicCell = sync.AtomicCell;
const State = sync.once.State;
const Token = sync.once.Token;
const SpinOnce = sync.Once(sync.spin.Backend);

// Backend that fails waits. A gated winner makes the loser path deterministic.
const FailingBackend = struct {
    fail_remaining: usize,
    wait_calls: usize = 0,
    wake_calls: usize = 0,

    pub const WaitError = error{Canceled};

    pub fn wait(self: *FailingBackend, state: *const State, observed: Token) WaitError!void {
        _ = state;
        _ = observed;
        self.wait_calls += 1;
        if (self.fail_remaining > 0) {
            self.fail_remaining -= 1;
            return error.Canceled;
        }
    }

    pub fn wakeAll(self: *FailingBackend, state: *const State) void {
        _ = state;
        self.wake_calls += 1;
    }
};

// Counting spin backend: satisfies the shared wait/wake contract with the
// same semantics as `sync.spin.Backend` but tracks `wait`/`wakeAll` call
// counts so tests can verify wake fanout on rollback.
const CountingBackend = struct {
    wait_calls: usize = 0,
    wake_calls: usize = 0,

    pub const WaitError = error{};

    pub fn wait(self: *CountingBackend, state: *const State, observed: Token) WaitError!void {
        _ = state;
        _ = observed;
        self.wait_calls += 1;
        std.atomic.spinLoopHint();
    }

    pub fn wakeAll(self: *CountingBackend, state: *const State) void {
        _ = state;
        self.wake_calls += 1;
    }
};

test "unit: State.init reports untouched and not done" {
    const state = State.init();
    try testing.expect(!state.isDone());

    const token = state.observe();
    try testing.expect(!token.isDone());
    try testing.expect(!state.changedSince(token));
}

test "unit: single-thread call invokes work exactly once across sequential callers" {
    const Ctx = struct { counter: *u32 };

    var counter: u32 = 0;
    var once = SpinOnce.init(.{});

    const work = struct {
        fn run(ctx: Ctx) void {
            ctx.counter.* += 1;
        }
    }.run;

    try once.call(Ctx, work, .{ .counter = &counter });
    try testing.expectEqual(@as(u32, 1), counter);
    try testing.expect(once.isDone());

    var i: usize = 0;
    while (i < 8) : (i += 1) {
        try once.call(Ctx, work, .{ .counter = &counter });
    }
    try testing.expectEqual(@as(u32, 1), counter);
}

test "unit: call publishes work writes observable after return" {
    const Payload = struct {
        value: AtomicCell(u64),
    };
    const Ctx = struct { payload: *Payload };

    var payload = Payload{ .value = AtomicCell(u64).init(0) };
    var once = SpinOnce.init(.{});

    const work = struct {
        fn run(ctx: Ctx) void {
            ctx.payload.value.storeRelease(0xdead_beef);
        }
    }.run;

    try once.call(Ctx, work, .{ .payload = &payload });
    try testing.expectEqual(@as(u64, 0xdead_beef), payload.value.loadAcquire());
}

test "unit: Once.isDone reflects state transitions" {
    var once = SpinOnce.init(.{});
    try testing.expect(!once.isDone());

    const work = struct {
        fn run(_: void) void {}
    }.run;

    try once.call(void, work, {});
    try testing.expect(once.isDone());
}

test "unit: WaitError propagates unchanged to losing callers" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const Once = sync.Once(FailingBackend);
    const Gate = struct {
        started: AtomicCell(bool),
        release: AtomicCell(bool),
    };
    const Winner = struct {
        fn run(gate: *Gate) void {
            gate.started.storeRelease(true);
            while (!gate.release.loadAcquire()) {
                std.atomic.spinLoopHint();
            }
        }
    };
    const Runner = struct {
        fn run(once: *Once, gate: *Gate) void {
            once.call(*Gate, Winner.run, gate) catch unreachable;
        }
    };
    const loser = struct {
        fn run(_: void) void {
            unreachable;
        }
    }.run;

    var gate = Gate{
        .started = AtomicCell(bool).init(false),
        .release = AtomicCell(bool).init(false),
    };
    var once = Once.init(.{ .fail_remaining = std.math.maxInt(usize) });
    var winner = try std.Thread.spawn(.{}, Runner.run, .{ &once, &gate });
    defer {
        gate.release.storeRelease(true);
        winner.join();
    }

    while (!gate.started.loadAcquire()) {
        std.atomic.spinLoopHint();
    }

    try testing.expectError(error.Canceled, once.call(void, loser, {}));
    try testing.expect(once.backend.wait_calls >= 1);
}

test "unit: callChecked returns work error and leaves state re-runnable" {
    const Fail = struct {
        var attempts: u32 = 0;

        fn run(_: void) error{Custom}!void {
            attempts += 1;
            return error.Custom;
        }
    };
    const Succeed = struct {
        var attempts: u32 = 0;

        fn run(_: void) error{Custom}!void {
            attempts += 1;
        }
    };

    var once = SpinOnce.init(.{});
    Fail.attempts = 0;
    Succeed.attempts = 0;

    try testing.expectError(error.Custom, once.callChecked(void, error{Custom}, Fail.run, {}));
    try testing.expect(!once.isDone());
    try testing.expectEqual(@as(u32, 1), Fail.attempts);

    try once.callChecked(void, error{Custom}, Succeed.run, {});
    try testing.expect(once.isDone());
    try testing.expectEqual(@as(u32, 1), Succeed.attempts);

    try once.callChecked(void, error{Custom}, Succeed.run, {});
    try testing.expectEqual(@as(u32, 1), Succeed.attempts);
}

test "unit: callChecked rollback calls wakeAll" {
    const Once = sync.Once(CountingBackend);

    var once = Once.init(.{});

    const Fail = struct {
        fn run(_: void) error{Custom}!void {
            return error.Custom;
        }
    };
    try testing.expectError(error.Custom, once.callChecked(void, error{Custom}, Fail.run, {}));

    try testing.expect(!once.isDone());
    try testing.expectEqual(@as(usize, 1), once.backend.wake_calls);
}

test "unit: mixing call and callChecked on the same state" {
    const Ctx = struct { counter: *u32 };

    var counter: u32 = 0;
    var once = SpinOnce.init(.{});

    const checked_work = struct {
        fn run(ctx: Ctx) error{Custom}!void {
            ctx.counter.* += 1;
        }
    }.run;
    try once.callChecked(Ctx, error{Custom}, checked_work, .{ .counter = &counter });
    try testing.expectEqual(@as(u32, 1), counter);

    const plain_work = struct {
        fn run(ctx: Ctx) void {
            ctx.counter.* += 1;
        }
    }.run;
    try once.call(Ctx, plain_work, .{ .counter = &counter });
    try testing.expectEqual(@as(u32, 1), counter);
}

test "contract: Once(spin.Backend) instantiates and its WaitError is empty" {
    comptime {
        _ = SpinOnce;
    }
    comptime std.debug.assert(SpinOnce.WaitError == error{});
    comptime std.debug.assert(!@hasDecl(SpinOnce, "stateRef"));
    // Instantiate additional backend shapes required by the backend contract.
    comptime {
        _ = sync.Once(CountingBackend);
        _ = sync.Once(FailingBackend);
    }
}

test "stress: N threads race on the same Once observe exactly one work invocation" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const Payload = struct {
        counter: AtomicCell(u32),
        flag: AtomicCell(u32),
    };
    const Ctx = struct {
        once: *SpinOnce,
        payload: *Payload,

        fn run(ctx: @This()) void {
            const work = struct {
                fn go(p: *Payload) void {
                    // Publish `counter` before `flag` to test release/acquire visibility.
                    _ = p.counter.fetchAddMonotonic(1);
                    p.flag.storeRelease(1);
                }
            }.go;

            ctx.once.call(*Payload, work, ctx.payload) catch unreachable;

            // Every returned caller observes the published pair.
            std.debug.assert(ctx.payload.flag.loadAcquire() == 1);
            std.debug.assert(ctx.payload.counter.loadAcquire() == 1);
        }
    };

    const thread_count: usize = 8;

    var payload = Payload{
        .counter = AtomicCell(u32).init(0),
        .flag = AtomicCell(u32).init(0),
    };
    var once = SpinOnce.init(.{});

    var threads: [thread_count]std.Thread = undefined;
    const ctx = Ctx{ .once = &once, .payload = &payload };

    var idx: usize = 0;
    while (idx < thread_count) : (idx += 1) {
        threads[idx] = try std.Thread.spawn(.{}, Ctx.run, .{ctx});
    }
    idx = 0;
    while (idx < thread_count) : (idx += 1) {
        threads[idx].join();
    }

    try testing.expectEqual(@as(u32, 1), payload.counter.loadAcquire());
    try testing.expect(once.isDone());
}

test "stress: callChecked rollback releases waiters that re-race the claim" {
    // One failed claim lets one waiter publish on retry.
    if (builtin.single_threaded) return error.SkipZigTest;

    const Payload = struct {
        succeed: AtomicCell(u32),
        successes: AtomicCell(u32),
    };
    const Ctx = struct {
        once: *SpinOnce,
        payload: *Payload,

        fn run(ctx: @This()) void {
            const work = struct {
                fn go(p: *Payload) error{TransientFailure}!void {
                    if (p.succeed.loadAcquire() == 0) {
                        p.succeed.storeRelease(1);
                        return error.TransientFailure;
                    }
                    _ = p.successes.fetchAddMonotonic(1);
                }
            }.go;

            _ = ctx.once.callChecked(*Payload, error{TransientFailure}, work, ctx.payload) catch {};
        }
    };

    const thread_count: usize = 8;

    var payload = Payload{
        .succeed = AtomicCell(u32).init(0),
        .successes = AtomicCell(u32).init(0),
    };
    var once = SpinOnce.init(.{});

    var threads: [thread_count]std.Thread = undefined;
    const ctx = Ctx{ .once = &once, .payload = &payload };

    var idx: usize = 0;
    while (idx < thread_count) : (idx += 1) {
        threads[idx] = try std.Thread.spawn(.{}, Ctx.run, .{ctx});
    }
    idx = 0;
    while (idx < thread_count) : (idx += 1) {
        threads[idx].join();
    }

    try testing.expect(once.isDone());
    try testing.expectEqual(@as(u32, 1), payload.successes.loadAcquire());
}

// Recursion traps and backend compile failures require test-harness support
// unavailable here.
