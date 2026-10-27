//! raw spinlock

const std = @import("std");

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
        return .{ .state = std.atomic.Value(u32).init(@intFromEnum(State.unlocked)) };
    }

    /// spins without yielding; successful acquisition has acquire ordering
    pub fn acquire(self: *Self) void {
        Impl.acquire(&self.state);
    }

    /// tries once without spurious failure; never spins
    pub fn tryAcquire(self: *Self) bool {
        return self.state.cmpxchgStrong(
            @intFromEnum(State.unlocked),
            @intFromEnum(State.locked),
            .acquire,
            .acquire,
        ) == null;
    }

    /// only the acquiring thread may release the lock
    pub fn release(self: *Self) void {
        if (debug.checksEnabled()) {
            std.debug.assert(self.isLocked());
        }
        self.state.store(@intFromEnum(State.unlocked), .release);
    }

    /// relaxed diagnostic snapshot; does not establish ownership or synchronization
    pub fn isLocked(self: *const Self) bool {
        return self.state.load(.monotonic) == @intFromEnum(State.locked);
    }
};

const Impl = struct {
    fn acquire(state: *std.atomic.Value(u32)) void {
        while (true) {
            if (state.cmpxchgWeak(
                @intFromEnum(RawSpinLock.State.unlocked),
                @intFromEnum(RawSpinLock.State.locked),
                .acquire,
                .acquire,
            ) == null) {
                return;
            }

            while (state.load(.monotonic) != @intFromEnum(RawSpinLock.State.unlocked)) {
                std.atomic.spinLoopHint();
            }
        }
    }
};

pub const unit = struct {
    const testing = std.testing;

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
};
