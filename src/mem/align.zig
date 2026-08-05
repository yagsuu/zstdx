//! Unsigned-integer alignment helpers. See `docs/specs/mem/align.md`.

const std = @import("std");

const bits = @import("../bits.zig");

/// `InvalidAlignment`: `alignment` is zero or not a power of two.
/// `Overflow`: rounding up exceeds `T`.
pub const AlignError = error{InvalidAlignment};
pub const OverflowError = error{Overflow};
pub const Error = AlignError || OverflowError;

pub fn alignUp(comptime T: type, value: T, alignment: T) Error!T {
    try validate(T, alignment);

    const mask = alignment - 1;
    const added = std.math.add(T, value, mask) catch return error.Overflow;
    return added & ~mask;
}

pub fn alignDown(comptime T: type, value: T, alignment: T) AlignError!T {
    try validate(T, alignment);
    return value & ~(alignment - 1);
}

/// Asserts that `alignment` is non-zero and a power of two.
pub fn isAligned(comptime T: type, value: T, alignment: T) bool {
    comptime requireUnsignedInt(T);
    std.debug.assert(alignment != 0);
    std.debug.assert(bits.isPowerOfTwo(T, alignment));
    return (value & (alignment - 1)) == 0;
}

pub fn alignUpDelta(comptime T: type, value: T, alignment: T) Error!T {
    const rounded = try alignUp(T, value, alignment);
    return rounded - value;
}

pub fn alignDownDelta(comptime T: type, value: T, alignment: T) AlignError!T {
    try validate(T, alignment);
    return value & (alignment - 1);
}

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
