//! Memory primitives: alignment and cache-line layout.
//! See `docs/specs/mem/`.

pub const @"align" = @import("mem/align.zig");
pub const alloc = @import("mem/alloc.zig");
pub const cache = @import("mem/cache.zig");

pub const CacheAlign = cache.CacheAlign;
pub const CachePad = cache.CachePad;

pub const alignDown = @"align".alignDown;
pub const alignDownDelta = @"align".alignDownDelta;
pub const alignUp = @"align".alignUp;
pub const alignUpDelta = @"align".alignUpDelta;
pub const isAligned = @"align".isAligned;
