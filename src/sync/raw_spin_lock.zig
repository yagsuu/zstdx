//! raw spinlock

const std = @import("std");

const debug = @import("core").debug;

/// non-fair spinlock; callers manage interrupt and scheduling policy
pub const RawSpinLock = struct {
    state: std.atomic.Value(u32),

    pub const State = enum(u32) {
        unlocked = 0,
        locked = 1,
    };

    const Self = @This();

    pub fn init() Self {
        return .{ .state = std.atomic.Value(u32).init(@intFromEnum(State.unlocked)) };
    }

    /// spins without yielding; successful acquisition has acquire ordering
    pub fn acquire(self: *Self) void {
        while (true) {
            if (self.state.cmpxchgWeak(
                @intFromEnum(State.unlocked),
                @intFromEnum(State.locked),
                .acquire,
                .acquire,
            ) == null) return;

            while (self.state.load(.monotonic) != @intFromEnum(State.unlocked)) {
                std.atomic.spinLoopHint();
            }
        }
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
        if (debug.checksEnabled()) self.assertHeld();
        self.state.store(@intFromEnum(State.unlocked), .release);
    }

    /// relaxed diagnostic snapshot; does not establish ownership or synchronization
    pub fn isHeld(self: *const Self) bool {
        return self.state.load(.monotonic) == @intFromEnum(State.locked);
    }

    /// checks locked state in checked builds; does not verify ownership
    pub fn assertHeld(self: *const Self) void {
        if (debug.checksEnabled()) std.debug.assert(self.isHeld());
    }
};
