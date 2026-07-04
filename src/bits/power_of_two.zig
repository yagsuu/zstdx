//! Power-of-two integer helpers used by alignment, ring capacities, and
//! bitsets. See docs/specs/bits/power-of-two.md.

const std = @import("std");

/// `Overflow`: `nextPowerOfTwo` would round past the largest representable
/// power of two for `T`.
pub const Error = error{Overflow};

fn requireUnsignedInt(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("power-of-two helpers require an unsigned integer type");
    }
}

/// True if `value` is a non-zero power of two; `0` returns false.
pub fn isPowerOfTwo(comptime T: type, value: T) bool {
    comptime requireUnsignedInt(T);
    return value != 0 and (value & (value - 1)) == 0;
}

/// Smallest power of two `>= value`. `0` and `1` map to `1`; exact powers
/// return themselves; values above the highest representable power return
/// `error.Overflow` without lossy wrap.
pub fn nextPowerOfTwo(comptime T: type, value: T) Error!T {
    comptime requireUnsignedInt(T);

    if (value <= 1) return 1;
    if (isPowerOfTwo(T, value)) return value;

    const bits = @bitSizeOf(T);
    const highest: T = @as(T, 1) << (bits - 1);
    if (value > highest) return error.Overflow;

    const shift_amount: std.math.Log2Int(T) = @intCast(bits - @clz(value - 1));
    return @as(T, 1) << shift_amount;
}
