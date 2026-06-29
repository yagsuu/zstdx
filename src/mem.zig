//! Memory primitives. See docs/specs/mem/alignment.md,
//! docs/specs/mem/arena-bounded.md, and docs/specs/mem/arena-static.md.

pub const alignment = @import("mem/alignment.zig");
pub const arena = @import("mem/arena.zig");

pub const Arena = arena.Arena;

pub const alignUp = alignment.alignUp;
pub const alignDown = alignment.alignDown;
pub const isAligned = alignment.isAligned;
pub const alignUpDelta = alignment.alignUpDelta;
pub const alignDownDelta = alignment.alignDownDelta;
