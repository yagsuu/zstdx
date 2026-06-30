//! Memory primitives. See docs/specs/mem/alignment.md,
//! docs/specs/mem/arena-bounded.md, docs/specs/mem/arena-static.md,
//! docs/specs/mem/pool.md, and docs/specs/mem/bitmap-allocator.md.

pub const alignment = @import("mem/alignment.zig");
pub const arena = @import("mem/arena.zig");
pub const pool = @import("mem/pool.zig");
pub const bitmap = @import("mem/bitmap.zig");

pub const Arena = arena.Arena;
pub const Pool = pool.Pool;
pub const BitmapAllocator = bitmap.BitmapAllocator;

pub const alignUp = alignment.alignUp;
pub const alignDown = alignment.alignDown;
pub const isAligned = alignment.isAligned;
pub const alignUpDelta = alignment.alignUpDelta;
pub const alignDownDelta = alignment.alignDownDelta;
