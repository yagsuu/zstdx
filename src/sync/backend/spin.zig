//! spin-only wait/wake backend

const std = @import("std");
const layout = @import("layout");

pub const Backend = struct {
    pub const WaitError = error{};

    comptime {
        layout.assertLayout(Backend, .{ .size = 0, .alignment = 1 });
    }

    /// does not observe state; callers must recheck readiness
    pub fn wait(
        self: *Backend,
        state: *const anyopaque,
        observed: anytype,
    ) WaitError!void {
        _ = self;
        _ = state;
        _ = observed;
        std.atomic.spinLoopHint();
    }

    /// no parked waiters need waking
    pub fn wakeAll(self: *Backend, state: *const anyopaque) void {
        _ = self;
        _ = state;
    }
};
