//! Endian integer contract tests. Spec: docs/specs/layout/endian.md.

const std = @import("std");

const zstdx = @import("zstdx");

const layout = zstdx.layout;
const bytes = zstdx.bytes;

const Le = layout.Le;
const Be = layout.Be;

const testing = std.testing;

test "unit: EndianInt has byte alignment and exact size for every supported width" {
    inline for (.{ Le(u16), Be(u16), Le(u24), Be(u40), Le(u128) }) |T| {
        try testing.expectEqual(T.byte_count, @sizeOf(T));
        try testing.expectEqual(@as(usize, 1), @alignOf(T));
    }
}

test "unit: EndianInt encodes little- and big-endian bytes for u32" {
    try testing.expectEqualSlices(
        u8,
        &.{ 0x78, 0x56, 0x34, 0x12 },
        &Le(u32).fromNative(0x12345678).bytes,
    );
    try testing.expectEqualSlices(
        u8,
        &.{ 0x12, 0x34, 0x56, 0x78 },
        &Be(u32).fromNative(0x12345678).bytes,
    );
}

test "unit: EndianInt round-trips zero, max, and a non-palindrome value" {
    try testing.expectEqual(
        @as(u32, 0x12345678),
        (Le(u32){ .bytes = .{ 0x78, 0x56, 0x34, 0x12 } }).native(),
    );
    try testing.expectEqual(@as(u32, 0), Be(u32).fromNative(0).native());
    try testing.expectEqual(
        std.math.maxInt(u128),
        Le(u128).fromNative(std.math.maxInt(u128)).native(),
    );
}

test "unit: EndianInt composes with unaligned load/store" {
    const Le32 = Le(u32);
    var buf: [@sizeOf(Le32)]u8 = undefined;
    bytes.storeUnaligned(Le32, &buf, Le32.fromNative(0xaabbccdd));
    try testing.expectEqual(@as(u32, 0xaabbccdd), bytes.loadUnaligned(Le32, &buf).native());
}
