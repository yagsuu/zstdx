//! Range primitive contract tests. Spec: docs/specs/core/range.md.

const std = @import("std");

const zstdx = @import("zstdx");

const Range = zstdx.core.Range;

const testing = std.testing;

test "unit: range init rejects inverted bounds" {
    const R = Range(u64);
    try testing.expectError(error.InvalidRange, R.fromBounds(2, 1));
    try testing.expectEqual(@as(u64, 0), (try R.fromBounds(5, 5)).len());
}

test "unit: range fromStartLen detects overflow" {
    const R = Range(u64);
    try testing.expectError(error.Overflow, R.fromStartLen(std.math.maxInt(u64), 1));
}

test "unit: range contains is half-open" {
    const R = Range(u64);
    const r = try R.fromBounds(10, 20);
    try testing.expect(r.contains(10));
    try testing.expect(!r.contains(20));
    try testing.expect(r.containsRange(try R.fromBounds(12, 18)));
    try testing.expect(!r.containsRange(try R.fromBounds(12, 21)));
}

test "unit: range overlap rejects empty ranges" {
    const R = Range(u64);
    const r = try R.fromBounds(10, 20);
    try testing.expect(r.overlaps(try R.fromBounds(19, 21)));
    try testing.expect(!r.overlaps(R.empty(15)));
    try testing.expect(!R.empty(15).overlaps(r));
    try testing.expectEqual(@as(?R, null), r.intersection(R.empty(15)));
}

test "unit: range adjacency and intersection/span" {
    const R = Range(u64);
    const r = try R.fromBounds(10, 20);
    try testing.expect(r.isAdjacent(try R.fromBounds(20, 25)));
    try testing.expectEqual(R{ .start = 15, .end = 20 }, r.intersection(try R.fromBounds(15, 25)).?);
    try testing.expectEqual(R{ .start = 0, .end = 20 }, r.span(try R.fromBounds(0, 12)));
}

test "unit: range prefix and suffix split at point" {
    const R = Range(u64);
    const r = try R.fromBounds(10, 20);
    try testing.expectEqual(R{ .start = 10, .end = 14 }, try r.prefix(14));
    try testing.expectEqual(R{ .start = 14, .end = 20 }, try r.suffix(14));
    try testing.expectEqual(R{ .start = 10, .end = 10 }, try r.prefix(10));
    try testing.expectEqual(R{ .start = 20, .end = 20 }, try r.suffix(20));
    try testing.expectError(error.OutOfBounds, r.prefix(21));
    try testing.expectError(error.OutOfBounds, r.suffix(21));
}

test "unit: range offsetOf and atOffset round trip" {
    const R = Range(u64);
    const r = try R.fromBounds(10, 20);
    try testing.expectEqual(@as(?u64, 3), r.offsetOf(13));
    try testing.expectEqual(@as(?u64, null), r.offsetOf(20));
    try testing.expectEqual(@as(?u64, 13), r.atOffset(3));
    try testing.expectEqual(@as(?u64, null), r.atOffset(10));
}

test "unit: range shifts report overflow at both directions" {
    const R = Range(u64);
    const r = try R.fromBounds(10, 20);
    try testing.expectEqual(R{ .start = 15, .end = 25 }, try r.shiftForward(5));
    try testing.expectEqual(R{ .start = 5, .end = 15 }, try r.shiftBackward(5));
    try testing.expectError(error.Overflow, r.shiftBackward(11));
    const r_high = R{ .start = std.math.maxInt(u64) - 1, .end = std.math.maxInt(u64) };
    try testing.expectError(error.Overflow, r_high.shiftForward(2));
}
