//! Byte-stable endian integer wrappers. `extern struct { bytes: [N]u8 }` with
//! alignment 1, exact-byte storage, and host-independent conversion. See
//! docs/specs/layout/endian.md.

const std = @import("std");

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

/// Wrapper around an unsigned byte-aligned integer `T` (8..128 bits, exact
/// multiples of 8; `usize`/`isize` rejected) that stores it as a fixed-size
/// byte array in the chosen endianness. The returned type is an
/// `extern struct` with `@sizeOf == count_bytes` and `@alignOf == 1`.
pub fn EndianInt(comptime T: type, comptime endian_value: std.builtin.Endian) type {
    comptime requireEndianInt(T);
    const bits = @bitSizeOf(T);
    const bytes_len = bits / 8;
    return extern struct {
        bytes: [bytes_len]u8,

        const Self = @This();

        /// Native integer type the wrapper carries.
        pub const Native = T;

        /// Byte order encoded in `bytes`.
        pub const byte_order = endian_value;

        /// Bit width of `Native`.
        pub const count_bits = bits;

        /// Storage width in bytes.
        pub const count_bytes = bytes_len;

        /// Encode `value` into the wrapper's byte order.
        pub fn fromNative(value: T) Self {
            var self: Self = .{ .bytes = [_]u8{0} ** bytes_len };
            var i: usize = 0;
            while (i < bytes_len) : (i += 1) {
                const source_index = switch (endian_value) {
                    .little => i,
                    .big => bytes_len - 1 - i,
                };
                const shift: std.math.Log2Int(T) = @intCast(source_index * 8);
                const byte_value: T = (value >> shift) & 0xff;
                self.bytes[i] = @intCast(byte_value);
            }
            return self;
        }

        /// Decode the wrapper's bytes into the native integer.
        pub fn native(self: Self) T {
            var value: T = 0;
            var i: usize = 0;
            while (i < bytes_len) : (i += 1) {
                const dest_index = switch (endian_value) {
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

/// Little-endian convenience factory: `Le(T) == EndianInt(T, .little)`.
pub fn Le(comptime T: type) type {
    return EndianInt(T, .little);
}

/// Big-endian convenience factory: `Be(T) == EndianInt(T, .big)`.
pub fn Be(comptime T: type) type {
    return EndianInt(T, .big);
}
