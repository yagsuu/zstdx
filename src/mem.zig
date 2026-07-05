//! Memory primitives. See docs/specs/mem/alignment.md,
//! docs/specs/mem/arena-bounded.md, docs/specs/mem/arena-static.md,
//! docs/specs/mem/pool.md, docs/specs/mem/pool-cache.md,
//! docs/specs/mem/bitmap-allocator.md, docs/specs/mem/buddy-allocator.md,
//! docs/specs/mem/frame-allocator.md, and docs/specs/mem/cache.md.

pub const alignment = @import("mem/alignment.zig");
pub const arena = @import("mem/arena.zig");
pub const bitmap = @import("mem/bitmap.zig");
pub const buddy = @import("mem/buddy.zig");
pub const cache = @import("mem/cache.zig");
pub const frame = @import("mem/frame.zig");
pub const pool = @import("mem/pool.zig");
pub const pool_cache = @import("mem/pool_cache.zig");

pub const Arena = arena.Arena;
pub const BitmapAllocator = bitmap.BitmapAllocator;
pub const BuddyAllocator = buddy.BuddyAllocator;
pub const CacheAlign = cache.CacheAlign;
pub const CachePad = cache.CachePad;
pub const FrameAllocator = frame.FrameAllocator;
pub const Pool = pool.Pool;
pub const PoolCache = pool_cache.PoolCache;

pub const alignDown = alignment.alignDown;
pub const alignDownDelta = alignment.alignDownDelta;
pub const alignUp = alignment.alignUp;
pub const alignUpDelta = alignment.alignUpDelta;
pub const isAligned = alignment.isAligned;
