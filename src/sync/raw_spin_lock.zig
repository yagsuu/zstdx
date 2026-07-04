//! Raw atomic-word spinlock. Spec: docs/specs/sync/raw-spin-lock.md.

const std = @import("std");

const debug = @import("../core/debug.zig");
const atomic_cell = @import("atomic_cell.zig");

const AtomicCell = atomic_cell.AtomicCell;

/// Minimum viable mutual-exclusion primitive: one atomic word, an
/// `acquire()` that spins until it wins, a `release()` that publishes
/// the exit. No fairness, no queueing, no interrupt policy, no
/// scheduler awareness, no backoff. The zero bit-pattern is a valid
/// unlocked lock, so bulk `@memset` to zero is a legal initialization.
pub const RawSpinLock = struct {
    state: AtomicCell(u32),

    /// State-word encoding. `unlocked` is `0` so the zero bit-pattern is
    /// a valid unlocked lock; adding a third value is a spec break.
    pub const State = enum(u32) {
        unlocked = 0,
        locked = 1,
    };

    const Self = @This();

    /// Return a lock whose state is `unlocked`.
    pub fn init() Self {
        return .{ .state = AtomicCell(u32).init(@intFromEnum(State.unlocked)) };
    }

    /// Spin until the caller holds the lock. Test-and-test-and-set:
    /// contended waiters spin on monotonic loads then retry the acquire
    /// CAS. Never allocates, never yields, never touches interrupt
    /// state; the winning CAS establishes an acquire edge with the
    /// previous holder's `release()`.
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

    /// Attempt one acquire; return `true` iff the caller now holds the
    /// lock. Strong CAS so a `false` return unambiguously means
    /// contention, not spurious failure. Never spins.
    pub fn tryAcquire(self: *Self) bool {
        return self.state.cmpxchgStrongAcquire(
            @intFromEnum(State.unlocked),
            @intFromEnum(State.locked),
        ) == null;
    }

    /// Publish the unlocked state with a release store. Under
    /// `core.debug.checksEnabled(.build_mode)` `assertHeld` runs first;
    /// a stray release traps in Debug/ReleaseSafe. In
    /// ReleaseFast/ReleaseSmall the store is unconditional.
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
