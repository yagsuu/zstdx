//! Once contract tests. Spec: docs/specs/sync/once.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const testing = std.testing;
const sync = stdx.sync;
const AtomicCell = sync.AtomicCell;
const State = sync.once.State;
const Token = sync.once.Token;
const SpinOnce = sync.Once(sync.spin.Backend);

// Synthetic backend that fails `wait` a fixed number of times, then
// succeeds forever. Used to exercise `WaitError` propagation on losers
// without relying on real thread scheduling.
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

test "unit: State.init reports untouched, not done, generation zero" {
    const state = State.init();
    try testing.expect(!state.isDone());

    const token = state.observe();
    try testing.expect(!token.isDone());
    try testing.expectEqual(@as(u32, 0), @intFromEnum(token));
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

    // Fast-path skip: subsequent calls short-circuit without invoking work.
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

test "unit: stateRef returns a pointer whose reads track transitions" {
    var once = SpinOnce.init(.{});
    const state_ptr = once.stateRef();
    try testing.expectEqual(@as(*const State, &once.state), state_ptr);
    try testing.expect(!state_ptr.isDone());

    const initial = state_ptr.observe();
    try testing.expect(!initial.isDone());

    const work = struct {
        fn run(_: void) void {}
    }.run;
    try once.call(void, work, {});

    try testing.expect(state_ptr.isDone());
    try testing.expect(state_ptr.changedSince(initial));
    const after = state_ptr.observe();
    try testing.expect(after.isDone());
    try testing.expect(!state_ptr.changedSince(after));
}

test "unit: Token.isDone matches state bits of the observed word" {
    const untouched: Token = @enumFromInt(0b0000);
    const running: Token = @enumFromInt(0b0101);
    const done: Token = @enumFromInt(0b1110);
    try testing.expect(!untouched.isDone());
    try testing.expect(!running.isDone());
    try testing.expect(done.isDone());
}

test "unit: WaitError propagates unchanged to losing callers" {
    // A `Once` whose backend fails every `wait` surfaces that error to
    // any caller that lost the claim CAS. Simulated here by manually
    // driving the state into `running` before invoking `call`, forcing
    // the caller down the loser path.
    const Once = sync.Once(FailingBackend);

    var once = Once.init(.{ .fail_remaining = std.math.maxInt(usize) });

    // Bump state -> running(gen=1) so the next `call` cannot claim.
    once.state.word.store((1 << 2) | 0b01, .release);

    const work = struct {
        fn run(_: void) void {
            // Winner path; should not fire on the loser.
            unreachable;
        }
    }.run;

    const result = once.call(void, work, {});
    try testing.expectError(error.Canceled, result);
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

    // Retry sees fresh untouched state; work re-runs and can succeed.
    try once.callChecked(void, error{Custom}, Succeed.run, {});
    try testing.expect(once.isDone());
    try testing.expectEqual(@as(u32, 1), Succeed.attempts);

    // Post-publication, further callChecked calls short-circuit.
    try once.callChecked(void, error{Custom}, Succeed.run, {});
    try testing.expectEqual(@as(u32, 1), Succeed.attempts);
}

test "unit: callChecked rollback bumps generation and calls wakeAll" {
    // Directly exercise the winning-rollback path against a counting
    // backend to confirm the required `wakeAll(&state)` on failure and
    // that the generation counter advances so losers holding the old
    // running token observe `changedSince`.
    const Once = sync.Once(CountingBackend);

    var once = Once.init(.{});
    const before_generation = @intFromEnum(once.stateRef().observe());

    const Fail = struct {
        fn run(_: void) error{Custom}!void {
            return error.Custom;
        }
    };
    try testing.expectError(error.Custom, once.callChecked(void, error{Custom}, Fail.run, {}));

    try testing.expect(!once.isDone());
    try testing.expectEqual(@as(usize, 1), once.backend.wake_calls);

    const after_rollback = @intFromEnum(once.stateRef().observe());
    try testing.expect(after_rollback != before_generation);
}

test "unit: mixing call and callChecked on the same state" {
    // After a successful callChecked publishes done, subsequent `call`
    // must short-circuit on the fast path without invoking work.
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

test "unit: State.observe and changedSince track every transition" {
    var once = SpinOnce.init(.{});
    const state = once.stateRef();

    const untouched_token = state.observe();
    try testing.expect(!untouched_token.isDone());

    const work = struct {
        fn run(_: void) void {}
    }.run;
    try once.call(void, work, {});

    const done_token = state.observe();
    try testing.expect(done_token.isDone());
    try testing.expect(state.changedSince(untouched_token));
    try testing.expect(!state.changedSince(done_token));
}

test "contract: Once(spin.Backend) instantiates and its WaitError is empty" {
    comptime {
        _ = SpinOnce;
    }
    comptime std.debug.assert(SpinOnce.WaitError == error{});
    // Also exercise a test backend that counts `wait` invocations; the
    // spec requires the factory to accept any backend meeting the shared
    // contract regardless of scheduler semantics.
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
                    // Prove publication ordering: the winner writes
                    // `counter` before releasing `flag`; every returning
                    // caller must observe both.
                    _ = p.counter.fetchAddMonotonic(1);
                    p.flag.storeRelease(1);
                }
            }.go;

            ctx.once.call(*Payload, work, ctx.payload) catch unreachable;

            // Every returning caller must acquire-see the winner's
            // publication: flag == 1 implies counter == 1.
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
    // Producer thread's first attempt fails; a fleet of losers observe
    // `running`, see the rollback via `changedSince`, and one of them
    // wins the retry. After the join, `state` is `done` and exactly one
    // successful publication occurred.
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
                    // First attempt across all threads fails; the winner
                    // of the retry succeeds.
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

// Debug-only trap probes cannot be exercised at Zig test runtime:
// `std.debug.assert` aborts the process on failure and this repo has no
// `expectPanic`-equivalent. The following comment enumerates the
// invariants trapped by the source; each is reachable through direct
// caller misuse and covered by the debug asserts in `src/sync/once.zig`.
//
//   Once.call / Once.callChecked trap under checksEnabled(.build_mode) on
//   hosts with functional `threadlocal` when:
//     - `work` re-enters `call` or `callChecked` on the same `Once`
//       instance from inside the running invocation.
//
// The check is best-effort per spec: mutual recursion through two
// distinct `Once` instances is not caught, and single-threaded builds
// compile the check out.

// Compile-only rejection cases enforced by `requireBackend` in
// `src/sync/once.zig`:
//   - Backend missing `WaitError` decl.
//   - Backend.WaitError not an error set.
//   - Backend.WaitError == anyerror (no explicit error set).
//   - Backend missing `wait` decl.
//   - Backend missing `wakeAll` decl.
// Attempting `sync.Once(BadBackend)` for any of the above fails to
// compile with the corresponding `@compileError` message.
