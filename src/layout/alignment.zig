//! Unsigned-integer alignment helpers. See `docs/specs/mem/align.md`.

const std = @import("std");

pub const OverflowError = error{Overflow};

/// Asserts that `alignment` is non-zero and a power of two.
pub fn alignUp(comptime T: type, value: T, alignment: T) OverflowError!T {
    comptime requireUnsignedInt(T);
    std.debug.assert(alignment != 0 and std.math.isPowerOfTwo(alignment));

    const mask = alignment - 1;
    const added = std.math.add(T, value, mask) catch return error.Overflow;
    return added & ~mask;
}

/// Asserts that `alignment` is non-zero and a power of two.
pub fn alignDown(comptime T: type, value: T, alignment: T) T {
    comptime requireUnsignedInt(T);
    std.debug.assert(alignment != 0 and std.math.isPowerOfTwo(alignment));
    return value & ~(alignment - 1);
}

/// Asserts that `alignment` is non-zero and a power of two.
pub fn isAligned(comptime T: type, value: T, alignment: T) bool {
    comptime requireUnsignedInt(T);
    std.debug.assert(alignment != 0 and std.math.isPowerOfTwo(alignment));
    return (value & (alignment - 1)) == 0;
}

/// Asserts that `alignment` is non-zero and a power of two.
pub fn alignUpDelta(comptime T: type, value: T, alignment: T) OverflowError!T {
    const rounded = try alignUp(T, value, alignment);
    return rounded - value;
}

/// Asserts that `alignment` is non-zero and a power of two.
pub fn alignDownDelta(comptime T: type, value: T, alignment: T) T {
    comptime requireUnsignedInt(T);
    std.debug.assert(alignment != 0 and std.math.isPowerOfTwo(alignment));
    return value & (alignment - 1);
}

fn requireUnsignedInt(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("alignment helpers require an unsigned integer type");
    }
}

pub const unit = struct {
    const testing = std.testing;

    test "unit: alignment rounding and deltas" {
        try testing.expectEqual(@as(usize, 16), try alignUp(usize, 9, 8));
        try testing.expectEqual(@as(usize, 8), alignDown(usize, 15, 8));
        try testing.expectEqual(@as(usize, 16), alignDown(usize, 16, 8));
        try testing.expect(isAligned(usize, 16, 8));
        try testing.expect(!isAligned(usize, 18, 8));

        try testing.expectEqual(@as(usize, 7), try alignUpDelta(usize, 9, 8));
        try testing.expectEqual(@as(usize, 0), try alignUpDelta(usize, 16, 8));
        try testing.expectEqual(@as(usize, 7), alignDownDelta(usize, 15, 8));
        try testing.expectEqual(@as(usize, 0), alignDownDelta(usize, 16, 8));
        try testing.expectEqual(@as(u8, 0), alignDown(u8, 0, 128));
        try testing.expectEqual(@as(u8, 0), alignDown(u8, 127, 128));
        try testing.expectEqual(@as(u8, 128), alignDown(u8, 255, 128));
        try testing.expectEqual(@as(u8, 127), alignDownDelta(u8, 255, 128));
        try testing.expectEqual(@as(u8, 255), alignDown(u8, 255, 1));
        try testing.expectEqual(@as(u8, 0), alignDownDelta(u8, 255, 1));
        try testing.expectEqual(@as(u8, 255), try alignUp(u8, 255, 1));
    }

    test "unit: upward alignment overflow" {
        try testing.expectError(error.Overflow, alignUp(u8, 250, 16));
        try testing.expectError(error.Overflow, alignUpDelta(u8, 250, 16));
    }

    test "unit: alignment supports non-native unsigned widths" {
        try testing.expectEqual(@as(u17, 24), try alignUp(u17, 17, 8));
    }
};
