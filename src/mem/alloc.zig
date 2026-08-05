//! Allocation primitives. See `docs/specs/mem/`.

pub const arena = @import("alloc/arena.zig");
pub const bitmap = @import("alloc/bitmap.zig");
pub const buddy = @import("alloc/buddy.zig");
pub const frame = @import("alloc/frame.zig");
pub const slab = @import("alloc/slab.zig");

pub const Arena = arena.Arena;
pub const BitmapAllocator = bitmap.BitmapAllocator;
pub const BuddyAllocator = buddy.BuddyAllocator;
pub const FrameAllocator = frame.FrameAllocator;
pub const SlabAllocator = slab.SlabAllocator;
pub const SlabCache = slab.SlabCache;
