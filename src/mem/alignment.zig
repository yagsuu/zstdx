//! Unsigned-integer alignment helpers. See docs/specs/mem/alignment.md.

const std = @import("std");

const bits = @import("../bits.zig");

/// `InvalidAlignment`: `alignment` is zero or not a power of two.
/// `Overflow`: rounding up exceeds `T`.
pub const AlignError = error{InvalidAlignment};
pub const OverflowError = error{Overflow};
pub const Error = AlignError || OverflowError;

fn requireUnsignedInt(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("alignment helpers require an unsigned integer type");
    }
}

fn validate(comptime T: type, alignment: T) AlignError!void {
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
pub fn alignDown(comptime T: type, value: T, alignment: T) AlignError!T {
    try validate(T, alignment);
    return value & ~(alignment - 1);
}

/// True when `value` is a multiple of `alignment`. `alignment` must be a
/// non-zero power of two; the precondition is asserted, not error-checked.
pub fn isAligned(comptime T: type, value: T, alignment: T) bool {
    comptime requireUnsignedInt(T);
    std.debug.assert(alignment != 0);
    std.debug.assert(bits.isPowerOfTwo(T, alignment));
    return (value & (alignment - 1)) == 0;
}

/// Padding required to reach the next multiple of `alignment` from `value`.
/// Equal to `alignUp(value, alignment) - value`. Returns `error.Overflow`
/// under the same condition as `alignUp`.
pub fn alignUpDelta(comptime T: type, value: T, alignment: T) Error!T {
    const rounded = try alignUp(T, value, alignment);
    return rounded - value;
}

/// Bytes past the previous multiple of `alignment`. Equal to
/// `value - alignDown(value, alignment)`. Cannot overflow.
pub fn alignDownDelta(comptime T: type, value: T, alignment: T) AlignError!T {
    try validate(T, alignment);
    return value & (alignment - 1);
}
