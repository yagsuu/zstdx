//! Concurrent data structures. See docs/specs/concurrent/mpsc-ring.md, docs/specs/concurrent/spsc-ring.md.

pub const mpsc = @import("concurrent/mpsc.zig");
pub const spsc = @import("concurrent/spsc.zig");
