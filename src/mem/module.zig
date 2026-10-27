//! Memory allocation primitives.
//! See `docs/specs/mem/`.

pub const alloc = @import("alloc.zig");

test {
    _ = alloc.arena.unit;
    _ = alloc.slab.allocator.unit;
    _ = alloc.slab.cache.unit;
    _ = alloc.bitmap.unit;
}
