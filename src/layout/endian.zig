//! Endian integer wrappers use exact-byte storage and host-independent conversion.
//! See `docs/specs/layout/endian.md`.

const std = @import("std");

/// Stores fixed-width unsigned integers of 8–128 bits, divisible by 8.
/// Storage has alignment 1 and excludes integer padding; usize/isize are rejected.
pub fn EndianInt(comptime T: type, comptime endian: std.builtin.Endian) type {
    comptime requireEndianInt(T);

    return extern struct {
        bytes: [size]u8,

        pub const Int = T;
        pub const width = @bitSizeOf(T);
        pub const size = @divExact(width, 8);
        pub const order = endian;

        const Self = @This();

        pub fn from(value: T) Self {
            var self: Self = undefined;
            std.mem.writeInt(T, &self.bytes, value, endian);
            return self;
        }

        pub fn native(self: Self) T {
            return std.mem.readInt(T, &self.bytes, endian);
        }
    };
}

pub fn Le(comptime T: type) type {
    return EndianInt(T, .little);
}

pub fn Be(comptime T: type) type {
    return EndianInt(T, .big);
}

fn requireEndianInt(comptime T: type) void {
    if (T == usize or T == isize) {
        @compileError("EndianInt rejects target-sized integer types");
    }

    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("EndianInt requires an unsigned integer type");
    }

    const width = @bitSizeOf(T);
    if (width < 8 or width > 128 or width % 8 != 0) {
        @compileError("EndianInt requires a byte-aligned unsigned integer from 8 to 128 bits");
    }
}

pub const unit = struct {
    const testing = std.testing;

    test "unit: EndianInt preserves exact byte size and alignment" {
        inline for (.{ Le(u16), Be(u16), Le(u24), Be(u40), Le(u128) }) |T| {
            try testing.expectEqual(T.size, @sizeOf(T));
            try testing.expectEqual(@as(usize, 1), @alignOf(T));
        }
    }

    test "unit: EndianInt preserves field offsets in extern headers" {
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

    test "unit: EndianInt encodes both byte orders" {
        const little = Le(u32).from(0x12345678);
        const big = Be(u32).from(0x12345678);

        try testing.expectEqualSlices(u8, &.{ 0x78, 0x56, 0x34, 0x12 }, &little.bytes);
        try testing.expectEqualSlices(u8, &.{ 0x12, 0x34, 0x56, 0x78 }, &big.bytes);
    }

    test "unit: EndianInt decodes bytes and preserves extreme values" {
        const little = Le(u32){ .bytes = .{ 0x78, 0x56, 0x34, 0x12 } };
        const zero = Be(u32).from(0);
        const maximum = Le(u128).from(std.math.maxInt(u128));

        try testing.expectEqual(@as(u32, 0x12345678), little.native());
        try testing.expectEqual(@as(u32, 0), zero.native());
        try testing.expectEqual(std.math.maxInt(u128), maximum.native());
    }

    test "unit: EndianInt handles integer storage padding independently of byte order" {
        const little = Le(u24).from(0x123456);
        const big = Be(u24){ .bytes = .{ 0x12, 0x34, 0x56 } };

        try testing.expectEqualSlices(u8, &.{ 0x56, 0x34, 0x12 }, &little.bytes);
        try testing.expectEqual(@as(u24, 0x123456), big.native());
    }
};
