//! Synchronization primitives. Specs: docs/specs/sync/signal.md, docs/specs/sync/spin.md,
//! docs/specs/sync/atomic-cell.md, docs/specs/sync/raw-spin-lock.md, docs/specs/sync/once.md,
//! docs/specs/sync/rendezvous.md, and docs/specs/sync/latch.md.

pub const atomic_cell = @import("sync/atomic_cell.zig");
pub const latch = @import("sync/latch.zig");
pub const once = @import("sync/once.zig");
pub const raw_spin_lock = @import("sync/raw_spin_lock.zig");
pub const rendezvous = @import("sync/rendezvous.zig");
pub const signal = @import("sync/signal.zig");
pub const spin = @import("sync/backend/spin.zig");

pub const AtomicCell = atomic_cell.AtomicCell;
pub const Latch = latch.Latch;
pub const Once = once.Once;
pub const RawSpinLock = raw_spin_lock.RawSpinLock;
pub const Rendezvous = rendezvous.Rendezvous;
pub const Signal = signal.Signal;
