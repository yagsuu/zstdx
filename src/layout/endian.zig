//! Endian integer wrappers use exact-byte storage and host-independent conversion.
//! See `docs/specs/layout/endian.md`.

const std = @import("std");

/// Returns a wrapper that stores an unsigned byte-aligned integer `T` from 8
/// through 128 bits in `endian` byte order. `usize` and `isize` are not
/// supported. The wrapper size is `@bitSizeOf(T) / 8`; its alignment is 1.
pub fn EndianInt(comptime T: type, comptime endian: std.builtin.Endian) type {
    comptime requireEndianInt(T);

    const bits = @bitSizeOf(T);
    const bytes_len = @divExact(bits, 8);
    return extern struct {
        bytes: [bytes_len]u8,

        pub const byte_order = endian;
        pub const count_bits = bits;
        pub const count_bytes = bytes_len;

        pub const Native = T;

        const Self = @This();

        pub fn fromNative(value: T) Self {
            var self: Self = .{ .bytes = [_]u8{0} ** bytes_len };
            var i: usize = 0;
            while (i < bytes_len) : (i += 1) {
                const source_index = switch (endian) {
                    .little => i,
                    .big => bytes_len - 1 - i,
                };

                const shift: std.math.Log2Int(T) = @intCast(source_index * 8);
                const byte_value: T = (value >> shift) & 0xff;
                self.bytes[i] = @intCast(byte_value);
            }

            return self;
        }

        pub fn native(self: Self) T {
            var value: T = 0;
            var i: usize = 0;
            while (i < bytes_len) : (i += 1) {
                const dest_index = switch (endian) {
                    .little => i,
                    .big => bytes_len - 1 - i,
                };

                const shift: std.math.Log2Int(T) = @intCast(dest_index * 8);
                value |= @as(T, self.bytes[i]) << shift;
            }

            return value;
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

    const bits = @bitSizeOf(T);
    const too_small = bits < 8;
    const too_large = bits > 128;
    const not_byte_aligned = bits % 8 != 0;

    if (too_small or too_large or not_byte_aligned) {
        @compileError("EndianInt requires a byte-aligned unsigned integer from 8 to 128 bits");
    }
}
