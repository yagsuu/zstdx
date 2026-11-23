//! Slab allocation primitives.

pub const allocator = @import("slab/allocator.zig");
pub const cache = @import("slab/cache.zig");

pub const SlabAllocator = allocator.SlabAllocator;
pub const SlabCache = cache.SlabCache;
