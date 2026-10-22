//! Data-layout primitives. See `docs/specs/layout/` and `docs/specs/mem/`.

pub const alignment = @import("alignment.zig");
pub const cache = @import("cache.zig");
pub const endian = @import("endian.zig");

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
    _ = endian.unit;
}
