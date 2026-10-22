//! Barrier primitives. See `docs/specs/barrier.md` and
//! `docs/specs/barrier/dma.md`.

pub const mmio = @import("mmio.zig");
pub const dma = @import("dma.zig");

pub const compiler = @import("compiler.zig").compiler;
