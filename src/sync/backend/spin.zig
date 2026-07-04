//! Spin-only wait/wake backend. Spec: docs/specs/sync/spin.md.

const std = @import("std");

/// Zero-sized wait/wake backend satisfying the shared backend contract for
/// every wait-capable primitive in `stdx.sync` and `stdx.concurrent`.
/// `wait` performs a single `std.atomic.spinLoopHint()` and returns; the
/// consuming primitive supplies the outer recheck loop. `wakeAll` is a
/// no-op. `Backend{}` is the sole constructor.
pub const Backend = struct {
    /// Empty error set: `Backend.wait` is infallible; `try` monomorphizes
    /// away at every callsite.
    pub const WaitError = error{};

    comptime {
        std.debug.assert(@sizeOf(Backend) == 0);
        std.debug.assert(@alignOf(Backend) == 1);
    }

    /// Spin-only wait: emits one `std.atomic.spinLoopHint()` and returns
    /// with no state observation. `state` and `observed` are discarded;
    /// the consuming primitive supplies the outer recheck loop.
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

    /// No-op: nothing is blocked on `wait` that requires waking; the
    /// caller's next iteration observes the primitive state on its own
    /// recheck.
    pub fn wakeAll(self: *Backend, state: *const anyopaque) void {
        _ = self;
        _ = state;
    }
};
