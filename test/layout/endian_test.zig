//! Endian integer contract tests. See `docs/specs/layout/endian.md`.

const std = @import("std");

const stdx = @import("stdx");

const layout = stdx.layout;

const Le = layout.Le;
const Be = layout.Be;

const testing = std.testing;

test "unit: EndianInt has byte alignment and exact size for every supported width" {
    inline for (.{ Le(u16), Be(u16), Le(u24), Be(u40), Le(u128) }) |T| {
        try testing.expectEqual(T.count_bytes, @sizeOf(T));
        try testing.expectEqual(@as(usize, 1), @alignOf(T));
    }
}

test "unit: EndianInt fields preserve extern struct layout" {
    const Header = extern struct {
        tag: u8,
        length: Le(u16),
        generation: Be(u32),
    };

    try testing.expectEqual(@as(usize, 0), @offsetOf(Header, "tag"));
    try testing.expectEqual(@as(usize, 1), @offsetOf(Header, "length"));
    try testing.expectEqual(@as(usize, 3), @offsetOf(Header, "generation"));
    try testing.expectEqual(@as(usize, 7), @sizeOf(Header));
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

test "unit: EndianInt composes with standard byte-value conversion" {
    const Le32 = Le(u32);
    const buf = std.mem.toBytes(Le32.fromNative(0xaabbccdd));
    try testing.expectEqual(@as(u32, 0xaabbccdd), std.mem.bytesToValue(Le32, &buf).native());
}
