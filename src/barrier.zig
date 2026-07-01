//! Barrier primitives. See docs/specs/barrier/overview.md and
//! docs/specs/barrier/dma.md.

pub const compiler = @import("barrier/compiler.zig").compiler;

pub const mmio = @import("barrier/mmio.zig");
pub const dma = @import("barrier/dma.zig");
