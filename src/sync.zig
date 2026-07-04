//! Synchronization primitives. See docs/specs/sync/signal.md,
//! docs/specs/sync/spin.md, and docs/specs/sync/atomic-cell.md.

pub const atomic_cell = @import("sync/atomic_cell.zig");
pub const signal = @import("sync/signal.zig");
pub const spin = @import("sync/backend/spin.zig");

pub const AtomicCell = atomic_cell.AtomicCell;
pub const Signal = signal.Signal;
