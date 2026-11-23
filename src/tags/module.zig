//! Strongly typed tag identifiers and allocators.

pub const tag = @import("tag.zig");
pub const allocator = @import("allocator.zig");

pub const Tag = tag.Tag;
pub const TagAllocator = allocator.TagAllocator;

test {
    _ = tag.unit;
    _ = allocator.unit;
}
