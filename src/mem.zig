//! Memory primitives. See docs/specs/mem/alignment.md and
//! docs/specs/mem/fixed-buffer-arena.md.

pub const alignment = @import("mem/alignment.zig");
pub const fixed_buffer_arena = @import("mem/fixed_buffer_arena.zig");

pub const FixedBufferArena = fixed_buffer_arena.FixedBufferArena;

pub const alignUp = alignment.alignUp;
pub const alignDown = alignment.alignDown;
pub const isAligned = alignment.isAligned;
pub const alignUpDelta = alignment.alignUpDelta;
pub const alignDownDelta = alignment.alignDownDelta;
