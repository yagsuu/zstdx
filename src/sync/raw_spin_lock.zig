//! Raw spin lock. See `docs/specs/sync/raw_spin_lock.md`.

const std = @import("std");
const builtin = @import("builtin");

const debug = @import("core").debug;

/// non-fair spinlock; callers manage interrupt and scheduling policy
pub const RawSpinLock = struct {
    state: std.atomic.Value(u32),

    const State = enum(u32) {
        unlocked = 0,
        locked = 1,
    };

    const Self = @This();

    pub fn init() Self {
        return .{ .state = std.atomic.Value(u32).init(@backingInt(State.unlocked)) };
    }

    /// spins without yielding; successful acquisition has acquire ordering
    pub fn acquire(self: *Self) void {
        Impl.acquire(&self.state);
    }

    /// tries once without spurious failure; never spins
    pub fn tryAcquire(self: *Self) bool {
        return self.state.cmpxchgStrong(
            @backingInt(State.unlocked),
            @backingInt(State.locked),
            .acquire,
            .acquire,
        ) == null;
    }

    /// only the acquiring thread may release the lock
    pub fn release(self: *Self) void {
        if (debug.checksEnabled()) {
            std.debug.assert(self.isLocked());
        }
        self.state.store(@backingInt(State.unlocked), .release);
    }

    /// relaxed diagnostic snapshot; does not establish ownership or synchronization
    pub fn isLocked(self: *const Self) bool {
        return self.state.load(.monotonic) == @backingInt(State.locked);
    }
};

const Impl = struct {
    fn acquire(state: *std.atomic.Value(u32)) void {
        while (true) {
            if (state.cmpxchgWeak(
                @backingInt(RawSpinLock.State.unlocked),
                @backingInt(RawSpinLock.State.locked),
                .acquire,
                .acquire,
            ) == null) {
                return;
            }

            while (state.load(.monotonic) != @backingInt(RawSpinLock.State.unlocked)) {
                std.atomic.spinLoopHint();
            }
        }
    }
};

pub const unit = struct {
    const testing = std.testing;

    const CounterRace = struct {
        lock: RawSpinLock = .init(),
        counter: u64 = 0,

        fn run(self: *@This()) void {
            for (0..2_500) |_| {
                self.lock.acquire();
                self.counter += 1;
                self.lock.release();
            }
        }
    };

    const PayloadPublication = struct {
        lock: RawSpinLock = .init(),
        payload: [2]u64 = .{ 0, 0 },
        ready: bool = false,
        observed: [2]u64 = .{ 0, 0 },

        fn writer(self: *@This()) void {
            self.lock.acquire();
            self.payload = .{ 0xC0FFEE_1234_5678, 0x1234_5678_C0FFEE };
            self.ready = true;
            self.lock.release();
        }

        fn reader(self: *@This()) void {
            for (0..10_000_000) |_| {
                self.lock.acquire();
                if (self.ready) {
                    self.observed = self.payload;
                    self.lock.release();
                    return;
                }

                self.lock.release();
                std.atomic.spinLoopHint();
            }
        }
    };

    test "lock lifecycle preserves acquisition and release state" {
        var lock = RawSpinLock.init();

        try testing.expect(!lock.isLocked());

        Impl.acquire(&lock.state);

        try testing.expect(lock.isLocked());
        try testing.expect(!lock.tryAcquire());

        lock.release();

        try testing.expect(!lock.isLocked());
        try testing.expect(lock.tryAcquire());

        lock.release();
        lock.acquire();

        try testing.expect(lock.isLocked());

        lock.release();

        try testing.expect(!lock.isLocked());
    }

    test "zero initialization produces a usable unlocked lock" {
        var lock: RawSpinLock = undefined;
        @memset(std.mem.asBytes(&lock), 0);

        try testing.expect(!lock.isLocked());
        try testing.expect(lock.tryAcquire());

        lock.release();
        lock.acquire();
        lock.release();

        try testing.expect(!lock.isLocked());
    }

    test "contending threads preserve lock-protected counter updates" {
        if (builtin.single_threaded) {
            return error.SkipZigTest;
        }

        var context: CounterRace = .{};
        var threads: [4]std.Thread = undefined;
        var started: usize = 0;

        context.lock.acquire();

        while (started < threads.len) : (started += 1) {
            threads[started] = std.Thread.spawn(.{}, CounterRace.run, .{&context}) catch |err| {
                context.lock.release();
                for (threads[0..started]) |thread| {
                    thread.join();
                }
                return err;
            };
        }

        context.lock.release();

        for (threads) |thread| {
            thread.join();
        }

        try testing.expectEqual(@as(u64, 10_000), context.counter);
        try testing.expect(!context.lock.isLocked());
    }

    test "release and acquire publish an ordinary paired payload" {
        if (builtin.single_threaded) {
            return error.SkipZigTest;
        }

        for (0..32) |_| {
            var context: PayloadPublication = .{};

            const writer = try std.Thread.spawn(.{}, PayloadPublication.writer, .{&context});
            const reader = std.Thread.spawn(.{}, PayloadPublication.reader, .{&context}) catch |err| {
                writer.join();
                return err;
            };

            writer.join();
            reader.join();

            try testing.expectEqual([2]u64{ 0xC0FFEE_1234_5678, 0x1234_5678_C0FFEE }, context.observed);
            try testing.expect(!context.lock.isLocked());
        }
    }
};
