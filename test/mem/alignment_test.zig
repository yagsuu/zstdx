//! Memory alignment helper contract tests. Spec: docs/specs/mem/alignment.md.

const std = @import("std");

const stdx = @import("stdx");

const mem = stdx.mem;

const testing = std.testing;

test "unit: alignUp and alignDown reject invalid alignment" {
    try testing.expectError(error.InvalidAlignment, mem.alignUp(usize, 1, 0));
    try testing.expectError(error.InvalidAlignment, mem.alignDown(usize, 1, 3));
}

test "unit: alignUp detects overflow on a narrow type" {
    try testing.expectError(error.Overflow, mem.alignUp(u8, 250, 16));
}

test "unit: alignUp/alignDown round to multiples of alignment" {
    try testing.expectEqual(@as(usize, 16), try mem.alignUp(usize, 9, 8));
    try testing.expectEqual(@as(usize, 8), try mem.alignDown(usize, 15, 8));
    try testing.expectEqual(@as(usize, 16), try mem.alignDown(usize, 16, 8));
}

test "unit: isAligned reports both states" {
    try testing.expect(mem.isAligned(usize, 16, 8));
    try testing.expect(!mem.isAligned(usize, 18, 8));
}

test "unit: alignment helpers work on non-native widths" {
    try testing.expectEqual(@as(u17, 24), try mem.alignUp(u17, 17, 8));
}

test "unit: alignUpDelta and alignDownDelta compute padding" {
    try testing.expectEqual(@as(usize, 7), try mem.alignUpDelta(usize, 9, 8));
    try testing.expectEqual(@as(usize, 0), try mem.alignUpDelta(usize, 16, 8));
    try testing.expectEqual(@as(usize, 7), try mem.alignDownDelta(usize, 15, 8));
    try testing.expectEqual(@as(usize, 0), try mem.alignDownDelta(usize, 16, 8));
    try testing.expectError(error.Overflow, mem.alignUpDelta(u8, 250, 16));
    try testing.expectError(error.InvalidAlignment, mem.alignDownDelta(usize, 1, 3));
}
