//! Tests for `stdx.sync.RawSpinLock`. See `docs/specs/sync/raw_spin_lock.md`.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const Atomic = std.atomic.Value;
const RawSpinLock = stdx.sync.RawSpinLock;
const testing = std.testing;

test "unit: init returns an unlocked lock" {
    var lock: RawSpinLock = .init();
    try testing.expect(!lock.isHeld());
}

test "unit: acquire then release round trip" {
    var lock: RawSpinLock = .init();

    lock.acquire();
    try testing.expect(lock.isHeld());

    lock.release();
    try testing.expect(!lock.isHeld());

    // Re-acquire after release succeeds, so state fully returned to unlocked.
    try testing.expect(lock.tryAcquire());
    lock.release();
    try testing.expect(!lock.isHeld());
}

test "unit: tryAcquire returns true on unlocked and false on locked" {
    var lock: RawSpinLock = .init();

    try testing.expect(lock.tryAcquire());
    try testing.expect(lock.isHeld());

    // Second attempt observes contention and leaves state untouched.
    try testing.expect(!lock.tryAcquire());
    try testing.expect(lock.isHeld());

    lock.release();
    try testing.expect(!lock.isHeld());

    // After release the lock is once again grabbable via tryAcquire.
    try testing.expect(lock.tryAcquire());
    lock.release();
}

test "unit: bulk-zero @memset produces a valid unlocked lock" {
    // Spec: `RawSpinLock` values are safe to `@memset` to zero at
    // bulk-init time; the zero representation is a valid unlocked lock.
    var lock: RawSpinLock = undefined;
    @memset(std.mem.asBytes(&lock), 0);
    try testing.expect(!lock.isHeld());

    // Round-trip acquire/release confirms the zero-init state is fully
    // usable, not merely readable.
    lock.acquire();
    try testing.expect(lock.isHeld());
    lock.release();
    try testing.expect(!lock.isHeld());
}

test "contract: acquire on freshly initialized lock marks it held" {
    var lock: RawSpinLock = .init();
    lock.acquire();
    defer lock.release();
    try testing.expect(lock.isHeld());
}

test "contract: assertHeld is a no-op when the lock is held" {
    var lock: RawSpinLock = .init();
    lock.acquire();
    defer lock.release();
    lock.assertHeld();
}

// Debug-only trap probes cannot be exercised at Zig test runtime:
// `std.debug.assert` aborts the process on failure and this repo has no
// `expectPanic`-equivalent. The following comment enumerates the
// invariants trapped by the source; each is reachable through direct
// caller misuse and covered by the debug asserts in
// `src/sync/raw_spin_lock.zig`.
//
//   RawSpinLock.assertHeld traps under checksEnabled() when:
//     - the state word is `unlocked` (never acquired or already released).
//
//   RawSpinLock.release traps under checksEnabled() when:
//     - assertHeld would trap on the same instance (release without a
//       prior successful acquire/tryAcquire).

test "stress: two threads acquire/release preserve mutual exclusion" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const Ctx = struct {
        lock: *RawSpinLock,
        counter: *Atomic(u32),
        iterations: u32,

        fn run(ctx: @This()) void {
            var i: u32 = 0;
            while (i < ctx.iterations) : (i += 1) {
                ctx.lock.acquire();
                // Separate loads/stores expose lost updates if mutual exclusion fails.
                const prev = ctx.counter.load(.monotonic);
                ctx.counter.store(prev + 1, .monotonic);
                ctx.lock.release();
            }
        }
    };

    const iterations: u32 = 10_000;

    var lock: RawSpinLock = .init();
    var counter: Atomic(u32) = .init(0);

    const ctx = Ctx{ .lock = &lock, .counter = &counter, .iterations = iterations };

    var t0 = try std.Thread.spawn(.{}, Ctx.run, .{ctx});
    var t1 = try std.Thread.spawn(.{}, Ctx.run, .{ctx});
    t0.join();
    t1.join();

    try testing.expectEqual(@as(u32, 2 * iterations), counter.load(.acquire));
    try testing.expect(!lock.isHeld());
}

test "stress: N-thread counter final value equals N*K" {
    // Spec model test: N threads each acquire, increment, release, in a
    // loop of K iterations; final counter equals N*K.
    if (builtin.single_threaded) return error.SkipZigTest;

    const Ctx = struct {
        lock: *RawSpinLock,
        counter: *Atomic(u64),
        iterations: u64,

        fn run(ctx: @This()) void {
            var i: u64 = 0;
            while (i < ctx.iterations) : (i += 1) {
                ctx.lock.acquire();
                const prev = ctx.counter.load(.monotonic);
                ctx.counter.store(prev + 1, .monotonic);
                ctx.lock.release();
            }
        }
    };

    const thread_count: usize = 4;
    const iterations: u64 = 2_500;

    var lock: RawSpinLock = .init();
    var counter: Atomic(u64) = .init(0);

    var threads: [thread_count]std.Thread = undefined;
    const ctx = Ctx{ .lock = &lock, .counter = &counter, .iterations = iterations };

    var idx: usize = 0;
    while (idx < thread_count) : (idx += 1) {
        threads[idx] = try std.Thread.spawn(.{}, Ctx.run, .{ctx});
    }
    idx = 0;
    while (idx < thread_count) : (idx += 1) {
        threads[idx].join();
    }

    try testing.expectEqual(@as(u64, thread_count * iterations), counter.load(.acquire));
}

test "ordering: paired payload published through release/acquire is observed" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const Ctx = struct {
        lock: *RawSpinLock,
        payload: *Atomic(u64),
        observed: *Atomic(u64),

        fn writer(ctx: @This()) void {
            ctx.lock.acquire();
            ctx.payload.store(0xC0FFEE_1234_5678, .release);
            ctx.lock.release();
        }

        fn reader(ctx: @This()) void {
            while (true) {
                ctx.lock.acquire();
                const value = ctx.payload.load(.acquire);
                ctx.lock.release();
                if (value != 0) {
                    ctx.observed.store(value, .release);
                    return;
                }
                std.atomic.spinLoopHint();
            }
        }
    };

    var trials: usize = 0;
    while (trials < 32) : (trials += 1) {
        var lock: RawSpinLock = .init();
        var payload: Atomic(u64) = .init(0);
        var observed: Atomic(u64) = .init(0);

        const ctx = Ctx{ .lock = &lock, .payload = &payload, .observed = &observed };
        var writer_thread = try std.Thread.spawn(.{}, Ctx.writer, .{ctx});
        var reader_thread = try std.Thread.spawn(.{}, Ctx.reader, .{ctx});
        writer_thread.join();
        reader_thread.join();

        try testing.expectEqual(@as(u64, 0xC0FFEE_1234_5678), observed.load(.acquire));
    }
}

test "stress: contended path — holder blocks waiters, each acquires in turn" {
    // Spec: one thread holds the lock while N-1 threads spin in
    // `acquire`; after the holder releases, exactly one waiter wins and
    // the remainder continue spinning until each has acquired and
    // released in turn.
    if (builtin.single_threaded) return error.SkipZigTest;

    const waiter_count: usize = 4;

    const Ctx = struct {
        lock: *RawSpinLock,
        acquired: *Atomic(u32),

        fn waiter(ctx: @This()) void {
            ctx.lock.acquire();
            _ = ctx.acquired.fetchAdd(1, .monotonic);
            ctx.lock.release();
        }
    };

    var lock: RawSpinLock = .init();
    var acquired: Atomic(u32) = .init(0);

    // Holder takes the lock before spawning any waiter, so every waiter
    // enters the spin path on entry.
    lock.acquire();

    var threads: [waiter_count]std.Thread = undefined;
    const ctx = Ctx{ .lock = &lock, .acquired = &acquired };

    var idx: usize = 0;
    while (idx < waiter_count) : (idx += 1) {
        threads[idx] = try std.Thread.spawn(.{}, Ctx.waiter, .{ctx});
    }

    // Yield a few times to give the waiters a chance to enter their
    // spin loops. No observable pre-release state is available to poll, so this
    // is best-effort; the same invariant holds if the yields do not deschedule.
    var pump: usize = 0;
    while (pump < 32) : (pump += 1) {
        std.Thread.yield() catch {};
    }
    try testing.expectEqual(@as(u32, 0), acquired.load(.acquire));

    lock.release();

    idx = 0;
    while (idx < waiter_count) : (idx += 1) {
        threads[idx].join();
    }

    try testing.expectEqual(@as(u32, waiter_count), acquired.load(.acquire));
    try testing.expect(!lock.isHeld());
}
