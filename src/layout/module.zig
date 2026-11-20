//! Data-layout primitives. See `docs/specs/layout/` and `docs/specs/mem/`.

pub const alignment = @import("alignment.zig");
pub const assert = @import("assert.zig");
pub const cache = @import("cache.zig");
pub const endian = @import("endian.zig");

pub const EndianInt = endian.EndianInt;
pub const Le = endian.Le;
pub const Be = endian.Be;

pub const CacheAlign = cache.CacheAlign;
pub const CachePad = cache.CachePad;

pub const Struct = @import("struct.zig").Struct;

pub const assertLayout = assert.assertLayout;
pub const alignDown = alignment.alignDown;
pub const alignDownDelta = alignment.alignDownDelta;
pub const alignUp = alignment.alignUp;
pub const alignUpDelta = alignment.alignUpDelta;
pub const isAligned = alignment.isAligned;

test {
    _ = alignment.unit;
    _ = cache.unit;
    _ = endian.unit;
    _ = @import("struct.zig").unit;
}
