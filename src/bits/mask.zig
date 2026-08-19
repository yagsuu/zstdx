//! Bit-mask construction. See `docs/specs/bits/mask.md`.

const std = @import("std");

fn requireUnsignedInt(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != .unsigned or info.int.bits == 0) {
        @compileError("bits.mask requires a non-zero-width unsigned integer type");
    }
}

/// Requirements: `T` is a non-zero-width unsigned integer and `count <= @bitSizeOf(T)`.
pub fn low(comptime T: type, count: usize) T {
    comptime requireUnsignedInt(T);
    std.debug.assert(count <= @bitSizeOf(T));

    if (count == @bitSizeOf(T)) return ~@as(T, 0);

    const shift: std.math.Log2Int(T) = @intCast(count);
    return (@as(T, 1) << shift) - 1;
}

/// Requirements: `T` is a non-zero-width unsigned integer and `index < @bitSizeOf(T)`.
pub fn single(comptime T: type, index: usize) T {
    comptime requireUnsignedInt(T);
    std.debug.assert(index < @bitSizeOf(T));
    const shift: std.math.Log2Int(T) = @intCast(index);
    return @as(T, 1) << shift;
}

/// Requirements: `T` is a non-zero-width unsigned integer, `first <= last`, and `last < @bitSizeOf(T)`.
pub fn range(comptime T: type, first: usize, last: usize) T {
    comptime requireUnsignedInt(T);
    std.debug.assert(first <= last);
    std.debug.assert(last < @bitSizeOf(T));

    const width = last - first + 1;
    const first_shift: std.math.Log2Int(T) = @intCast(first);
    return low(T, width) << first_shift;
}
