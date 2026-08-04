//! Strongly typed tag identifiers and allocators. See `docs/specs/tags/tag-allocator.md`.

pub const tag = @import("tags/tag.zig");
pub const allocator = @import("tags/allocator.zig");

pub const Tag = tag.Tag;
pub const TagAllocator = allocator.TagAllocator;
