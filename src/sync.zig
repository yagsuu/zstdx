//! Synchronization primitives. See docs/specs/sync/signal.md,
//! docs/specs/sync/spin.md, docs/specs/sync/atomic-cell.md,
//! and docs/specs/sync/raw-spin-lock.md.

pub const atomic_cell = @import("sync/atomic_cell.zig");
pub const signal = @import("sync/signal.zig");
pub const spin = @import("sync/backend/spin.zig");
pub const raw_spin_lock = @import("sync/raw_spin_lock.zig");

pub const AtomicCell = atomic_cell.AtomicCell;
pub const Signal = signal.Signal;
pub const RawSpinLock = raw_spin_lock.RawSpinLock;
