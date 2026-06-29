//! Power-of-two helper contract tests. Spec: docs/specs/bits/power-of-two.md.

const std = @import("std");

const stdx = @import("stdx");

const bits = stdx.bits;

const testing = std.testing;

test "unit: isPowerOfTwo classifies u8 boundary cases" {
    try testing.expect(!bits.isPowerOfTwo(u8, 0));
    try testing.expect(bits.isPowerOfTwo(u8, 1));
    try testing.expect(bits.isPowerOfTwo(u8, 128));
    try testing.expect(!bits.isPowerOfTwo(u8, 129));
}

test "unit: nextPowerOfTwo rounds and detects overflow" {
    try testing.expectEqual(@as(u8, 1), try bits.nextPowerOfTwo(u8, 0));
    try testing.expectEqual(@as(u8, 1), try bits.nextPowerOfTwo(u8, 1));
    try testing.expectEqual(@as(u8, 8), try bits.nextPowerOfTwo(u8, 5));
    try testing.expectEqual(@as(u8, 128), try bits.nextPowerOfTwo(u8, 128));
    try testing.expectError(error.Overflow, bits.nextPowerOfTwo(u8, 129));
}

test "unit: nextPowerOfTwo works on non-native widths" {
    try testing.expectEqual(@as(u17, 65536), try bits.nextPowerOfTwo(u17, 65535));
}
