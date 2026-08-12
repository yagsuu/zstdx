//! Raw atomic-word spinlock. See `docs/specs/sync/raw_spin_lock.md`.

const std = @import("std");

const debug = @import("../core/debug.zig");
const atomic_cell = @import("atomic_cell.zig");

const AtomicCell = atomic_cell.AtomicCell;

/// Non-fair atomic-word spinlock.
///
/// Representation: one atomic word. `unlocked` is zero, so bulk `@memset`
/// initialization is valid.
///
/// `acquire()` spins until it succeeds. The lock does not queue waiters,
/// manage interrupt policy or scheduling, or apply backoff.
pub const RawSpinLock = struct {
    state: AtomicCell(u32),

    pub const State = enum(u32) {
        unlocked = 0,
        locked = 1,
    };

    const Self = @This();

    pub fn init() Self {
        return .{ .state = AtomicCell(u32).init(@intFromEnum(State.unlocked)) };
    }

    /// Acquires the lock through test-and-test-and-set.
    ///
    /// Contended callers spin on monotonic loads and retry the acquire CAS.
    /// The lock does not allocate, yield, or change interrupt state. The winning
    /// CAS establishes an acquire edge with the previous holder's `release()`.
    pub fn acquire(self: *Self) void {
        while (true) {
            if (self.state.cmpxchgWeakAcquire(
                @intFromEnum(State.unlocked),
                @intFromEnum(State.locked),
            ) == null) return;

            while (self.state.loadMonotonic() != @intFromEnum(State.unlocked)) {
                std.atomic.spinLoopHint();
            }
        }
    }

    /// Attempts to acquire once. Returns `true` only when the caller holds
    /// the lock. Strong CAS means that `false` unambiguously signals
    /// contention rather than spurious failure. Never spins.
    pub fn tryAcquire(self: *Self) bool {
        return self.state.cmpxchgStrongAcquire(
            @intFromEnum(State.unlocked),
            @intFromEnum(State.locked),
        ) == null;
    }

    /// Release-publishes the unlocked state.
    ///
    /// Under `core.debug.checksEnabled(.build_mode)`, `assertHeld` runs first;
    /// a stray release traps in Debug/ReleaseSafe. In ReleaseFast/ReleaseSmall,
    /// the store is unconditional.
    pub fn release(self: *Self) void {
        if (debug.checksEnabled(.build_mode)) self.assertHeld();
        self.state.storeRelease(@intFromEnum(State.unlocked));
    }

    /// Snapshot: monotonic load reports whether the state word equals
    /// `locked`. Not a synchronize-with edge; use for diagnostics and
    /// invariant checks only.
    pub fn isHeld(self: *const Self) bool {
        return self.state.loadMonotonic() == @intFromEnum(State.locked);
    }

    /// Trap if the state word is not `locked`. Runs unconditionally when
    /// called; consumers gate at the call site under
    /// `core.debug.checksEnabled(.build_mode)`. `release()` invokes this
    /// internally under the same gate.
    pub fn assertHeld(self: *const Self) void {
        if (debug.checksEnabled(.build_mode)) std.debug.assert(self.isHeld());
    }
};
