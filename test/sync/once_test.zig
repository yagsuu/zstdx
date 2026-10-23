//! Once contract tests. See `docs/specs/sync/once.md`.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const testing = std.testing;
const sync = stdx.sync;
const Atomic = std.atomic.Value;
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

test "unit: WaitError propagates unchanged to losing callers" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    const Once = sync.Once(FailingBackend);
    const Gate = struct {
        started: Atomic(bool),
        release: Atomic(bool),
    };
    const Winner = struct {
        fn run(gate: *Gate) void {
            gate.started.store(true, .release);
            while (!gate.release.load(.acquire)) {
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
        .started = Atomic(bool).init(false),
        .release = Atomic(bool).init(false),
    };
    var once = Once.init(.{ .fail_remaining = std.math.maxInt(usize) });
    var winner = try std.Thread.spawn(.{}, Runner.run, .{ &once, &gate });
    defer {
        gate.release.store(true, .release);
        winner.join();
    }

    while (!gate.started.load(.acquire)) {
        std.atomic.spinLoopHint();
    }

    try testing.expectError(error.Canceled, once.call(void, loser, {}));
    try testing.expect(once.backend.wait_calls >= 1);
}

test "stress: N threads race on the same Once observe exactly one work invocation" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    const Payload = struct {
        counter: Atomic(u32),
        flag: Atomic(u32),
    };
    const Ctx = struct {
        once: *SpinOnce,
        payload: *Payload,

        fn run(ctx: @This()) void {
            const work = struct {
                fn go(p: *Payload) void {
                    // Publish `counter` before `flag` to test release/acquire visibility.
                    _ = p.counter.fetchAdd(1, .monotonic);
                    p.flag.store(1, .release);
                }
            }.go;

            ctx.once.call(*Payload, work, ctx.payload) catch unreachable;

            // Every returned caller observes the published pair.
            std.debug.assert(ctx.payload.flag.load(.acquire) == 1);
            std.debug.assert(ctx.payload.counter.load(.acquire) == 1);
        }
    };

    const thread_count: usize = 8;

    var payload = Payload{
        .counter = Atomic(u32).init(0),
        .flag = Atomic(u32).init(0),
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

    try testing.expectEqual(@as(u32, 1), payload.counter.load(.acquire));
    try testing.expect(once.isDone());
}

test "stress: callChecked rollback releases waiters that re-race the claim" {
    // One failed claim lets one waiter publish on retry.
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    const Payload = struct {
        succeed: Atomic(u32),
        successes: Atomic(u32),
    };
    const Ctx = struct {
        once: *SpinOnce,
        payload: *Payload,

        fn run(ctx: @This()) void {
            const work = struct {
                fn go(p: *Payload) error{TransientFailure}!void {
                    if (p.succeed.load(.acquire) == 0) {
                        p.succeed.store(1, .release);
                        return error.TransientFailure;
                    }
                    _ = p.successes.fetchAdd(1, .monotonic);
                }
            }.go;

            _ = ctx.once.callChecked(*Payload, error{TransientFailure}, work, ctx.payload) catch {};
        }
    };

    const thread_count: usize = 8;

    var payload = Payload{
        .succeed = Atomic(u32).init(0),
        .successes = Atomic(u32).init(0),
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
    try testing.expectEqual(@as(u32, 1), payload.successes.load(.acquire));
}
