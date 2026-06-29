//! Unsigned-integer alignment helpers. See docs/specs/mem/alignment.md.

const std = @import("std");

const bits = @import("../bits.zig");

/// `InvalidAlignment`: `alignment` is zero or not a power of two.
/// `Overflow`: rounding up exceeds `T`.
pub const Error = error{ InvalidAlignment, Overflow };

fn requireUnsignedInt(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("alignment helpers require an unsigned integer type");
    }
}

fn validate(comptime T: type, alignment: T) Error!void {
    comptime requireUnsignedInt(T);
    if (alignment == 0 or !bits.isPowerOfTwo(T, alignment)) return error.InvalidAlignment;
}

/// Smallest multiple of `alignment` that is `>= value`.
pub fn alignUp(comptime T: type, value: T, alignment: T) Error!T {
    try validate(T, alignment);
    const mask = alignment - 1;
    const added = std.math.add(T, value, mask) catch return error.Overflow;
    return added & ~mask;
}

/// Largest multiple of `alignment` that is `<= value`. Returns the original
/// value when already aligned; never overflows.
pub fn alignDown(comptime T: type, value: T, alignment: T) Error!T {
    try validate(T, alignment);
    return value & ~(alignment - 1);
}

/// True when `value` is a multiple of `alignment`.
pub fn isAligned(comptime T: type, value: T, alignment: T) Error!bool {
    try validate(T, alignment);
    return (value & (alignment - 1)) == 0;
}
