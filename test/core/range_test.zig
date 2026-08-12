//! Range primitive contract tests. See `docs/specs/core/range.md`.

const std = @import("std");

const stdx = @import("stdx");

const Range = stdx.core.Range;
const InclusiveRange = stdx.core.InclusiveRange;

const testing = std.testing;

test "unit: range init rejects inverted bounds" {
    const R = Range(u64);
    try testing.expectError(error.InvalidRange, R.fromBounds(2, 1));
    try testing.expectEqual(@as(u64, 0), (try R.fromBounds(5, 5)).len());
}

test "comptime: range of constructs literals" {
    const R = Range(u8);
    const r = comptime R.of(5, 9);
    try testing.expectEqual(R{ .start = 5, .end = 9 }, r);
    try testing.expectEqual(R.empty(7), comptime R.of(7, 7));
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

test "unit: inclusive range construction enforces representable cardinality" {
    const R = InclusiveRange(u8);

    try testing.expectEqual(R{ .start = 5, .end = 9 }, try R.fromBounds(5, 9));
    try testing.expectEqual(R{ .start = 7, .end = 7 }, R.single(7));
    try testing.expect(R.single(7).isSingleton());
    try testing.expectError(error.InvalidRange, R.fromBounds(9, 5));
    try testing.expectError(error.InvalidRange, R.fromBounds(0, std.math.maxInt(u8)));
    try testing.expect(!(R{ .start = 0, .end = std.math.maxInt(u8) }).isValid());

    const literal = comptime R.of(5, 9);
    try testing.expectEqual(R{ .start = 5, .end = 9 }, literal);
}

test "unit: inclusive range fromStartLen rejects zero and endpoint overflow" {
    const R = InclusiveRange(u8);

    try testing.expectEqual(R{ .start = 10, .end = 14 }, try R.fromStartLen(10, 5));
    try testing.expectError(error.InvalidRange, R.fromStartLen(10, 0));
    try testing.expectError(error.Overflow, R.fromStartLen(250, 7));
}

test "unit: inclusive range length is infallible at maximum valid cardinality" {
    const R = InclusiveRange(u8);

    try testing.expectEqual(@as(u8, 1), R.single(0).len());
    try testing.expectEqual(@as(u8, 255), R.of(0, 254).len());
    try testing.expectEqual(@as(u8, 255), R.of(1, 255).len());

    const U16Domain = InclusiveRange(u32);
    const all_u16 = comptime U16Domain.of(0, std.math.maxInt(u16));
    try testing.expectEqual(@as(u32, 65_536), all_u16.len());
}

test "unit: inclusive range contains both endpoints and contained ranges" {
    const R = InclusiveRange(u8);
    const r = R.of(10, 20);

    try testing.expect(r.contains(10));
    try testing.expect(r.contains(20));
    try testing.expect(!r.contains(9));
    try testing.expect(r.containsRange(R.of(12, 18)));
    try testing.expect(!r.containsRange(R.of(12, 21)));
}

test "unit: inclusive range overlap adjacency intersection and span" {
    const R = InclusiveRange(u8);
    const r = R.of(10, 20);

    try testing.expect(r.overlaps(R.of(20, 25)));
    try testing.expect(!r.overlaps(R.of(21, 25)));
    try testing.expect(r.isAdjacent(R.of(21, 25)));
    try testing.expect(R.of(21, 25).isAdjacent(r));
    try testing.expect(R.single(0).isAdjacent(R.single(1)));
    try testing.expect(R.single(255).isAdjacent(R.single(254)));
    try testing.expectEqual(R.single(20), r.intersection(R.of(20, 25)).?);
    try testing.expectEqual(@as(?R, null), r.intersection(R.of(21, 25)));
    try testing.expectEqual(R.of(10, 25), try r.span(R.of(21, 25)));
    try testing.expectError(error.Overflow, R.single(0).span(R.single(255)));
}

test "unit: inclusive range prefix and suffix share the split point" {
    const R = InclusiveRange(u8);
    const r = R.of(10, 20);

    try testing.expectEqual(R.of(10, 14), try r.prefix(14));
    try testing.expectEqual(R.of(14, 20), try r.suffix(14));
    try testing.expectEqual(R.single(10), try r.prefix(10));
    try testing.expectEqual(R.single(20), try r.suffix(20));
    try testing.expectEqual(R.single(14), (try r.prefix(14)).intersection(try r.suffix(14)).?);
    try testing.expectError(error.OutOfBounds, r.prefix(9));
    try testing.expectError(error.OutOfBounds, r.suffix(21));
}

test "unit: inclusive range offset includes the final endpoint" {
    const R = InclusiveRange(u8);
    const r = R.of(10, 20);

    try testing.expectEqual(@as(?u8, 0), r.offsetOf(10));
    try testing.expectEqual(@as(?u8, 10), r.offsetOf(20));
    try testing.expectEqual(@as(?u8, 20), r.atOffset(10));
    try testing.expectEqual(@as(?u8, null), r.atOffset(11));
    try testing.expectEqual(@as(?u8, null), r.offsetOf(21));
}

test "unit: inclusive range shifts report overflow in both directions" {
    const R = InclusiveRange(u8);
    const r = R.of(10, 20);

    try testing.expectEqual(R.of(15, 25), try r.shiftForward(5));
    try testing.expectEqual(R.of(5, 15), try r.shiftBackward(5));
    try testing.expectError(error.Overflow, r.shiftBackward(11));
    try testing.expectError(error.Overflow, R.of(250, 255).shiftForward(1));
}

test "unit: inclusive and half-open range conversions preserve bounds" {
    const R = Range(u8);
    const I = InclusiveRange(u8);

    try testing.expectEqual(I.of(10, 19), I.fromRange(R.of(10, 20)).?);
    try testing.expectEqual(@as(?I, null), I.fromRange(R.empty(10)));
    try testing.expectEqual(R.of(10, 20), try I.of(10, 19).toRange());
    try testing.expectEqual(R.of(10, 11), try I.single(10).toRange());
    try testing.expectEqual(R.of(10, 20), try I.fromRange(R.of(10, 20)).?.toRange());
    try testing.expectError(error.Overflow, I.of(1, std.math.maxInt(u8)).toRange());
}

// Compile-error cases are enforced by `requireNonZeroUnsignedInt` and `of`:
//   - `InclusiveRange(i8)` rejects a signed backing type;
//   - `InclusiveRange(u0)` rejects a zero-width backing type;
//   - `InclusiveRange(u8).of(0, 255)` rejects the full-domain range.
