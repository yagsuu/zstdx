//! Byte layout primitives. See docs/specs/layout/unaligned.md and
//! docs/specs/layout/endian.md.

pub const unaligned = @import("layout/unaligned.zig");
pub const endian = @import("layout/endian.zig");

pub const EndianInt = endian.EndianInt;
pub const Le = endian.Le;
pub const Be = endian.Be;

pub const unalignedLoad = unaligned.unalignedLoad;
pub const unalignedStore = unaligned.unalignedStore;
