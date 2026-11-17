//! Memory allocation primitives.
//! See `docs/specs/mem/`.

pub const alloc = @import("alloc.zig");

test {
    _ = alloc.arena.unit;
    _ = alloc.slab.allocator.unit;
    _ = alloc.slab.cache.unit;
    _ = alloc.page.unit;
    _ = alloc.bitmap.unit;
    _ = alloc.buddy.unit;
    _ = @import("alloc/arena_test.zig");
    _ = @import("alloc/page_test.zig");
    _ = @import("alloc/slab/allocator_test.zig");
    _ = @import("alloc/slab/cache_test.zig");
}
