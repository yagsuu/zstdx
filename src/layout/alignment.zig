//! Unsigned-integer alignment helpers. See `docs/specs/mem/align.md`.

const std = @import("std");

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
    std.debug.assert(alignment != 0 and std.math.isPowerOfTwo(alignment));
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
    if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) {
        return error.InvalidAlignment;
    }
}

pub const unit = struct {
    const testing = std.testing;

    test "unit: alignment rounding and deltas" {
        try testing.expectEqual(@as(usize, 16), try alignUp(usize, 9, 8));
        try testing.expectEqual(@as(usize, 8), try alignDown(usize, 15, 8));
        try testing.expectEqual(@as(usize, 16), try alignDown(usize, 16, 8));
        try testing.expect(isAligned(usize, 16, 8));
        try testing.expect(!isAligned(usize, 18, 8));

        try testing.expectEqual(@as(usize, 7), try alignUpDelta(usize, 9, 8));
        try testing.expectEqual(@as(usize, 0), try alignUpDelta(usize, 16, 8));
        try testing.expectEqual(@as(usize, 7), try alignDownDelta(usize, 15, 8));
        try testing.expectEqual(@as(usize, 0), try alignDownDelta(usize, 16, 8));
    }

    test "unit: alignment rejection and overflow" {
        try testing.expectError(error.InvalidAlignment, alignUp(usize, 1, 0));
        try testing.expectError(error.InvalidAlignment, alignDown(usize, 1, 3));
        try testing.expectError(error.InvalidAlignment, alignDownDelta(usize, 1, 3));
        try testing.expectError(error.Overflow, alignUp(u8, 250, 16));
        try testing.expectError(error.Overflow, alignUpDelta(u8, 250, 16));
    }

    test "unit: alignment supports non-native unsigned widths" {
        try testing.expectEqual(@as(u17, 24), try alignUp(u17, 17, 8));
    }
};
