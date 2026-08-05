//! Barrier primitives. See `docs/specs/barrier.md` and
//! `docs/specs/barrier/dma.md`.

pub const mmio = @import("barrier/mmio.zig");
pub const dma = @import("barrier/dma.zig");

pub const compiler = @import("barrier/compiler.zig").compiler;
