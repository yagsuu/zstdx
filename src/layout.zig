//! Byte-layout primitives. See `docs/specs/layout/endian.md`.

pub const endian = @import("layout/endian.zig");

pub const EndianInt = endian.EndianInt;
pub const Le = endian.Le;
pub const Be = endian.Be;
