//! Slab allocation primitives. See `docs/specs/mem/alloc/slab/allocator.md` and
//! `docs/specs/mem/alloc/slab/cache.md`.

pub const allocator = @import("slab/allocator.zig");
pub const cache = @import("slab/cache.zig");

pub const SlabAllocator = allocator.SlabAllocator;
pub const SlabCache = cache.SlabCache;
