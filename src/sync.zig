//! Synchronization primitives. See docs/specs/sync/signal.md and docs/specs/sync/spin.md.

pub const signal = @import("sync/signal.zig");
pub const spin = @import("sync/backend/spin.zig");

pub const Signal = signal.Signal;
