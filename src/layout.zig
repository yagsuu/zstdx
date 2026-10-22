//! Data-layout primitives. See `docs/specs/layout/` and `docs/specs/mem/`.

pub const alignment = @import("layout/alignment.zig");
pub const cache = @import("layout/cache.zig");
pub const endian = @import("layout/endian.zig");

pub const EndianInt = endian.EndianInt;
pub const Le = endian.Le;
pub const Be = endian.Be;

pub const alignDown = alignment.alignDown;
pub const alignDownDelta = alignment.alignDownDelta;
pub const alignUp = alignment.alignUp;
pub const alignUpDelta = alignment.alignUpDelta;
pub const isAligned = alignment.isAligned;

pub const CacheAlign = cache.CacheAlign;
pub const CachePad = cache.CachePad;

test {
    _ = alignment.unit;
    _ = cache.unit;
}
