//! RangeSet contract tests. See `docs/specs/ranges/range-set.md`.

const std = @import("std");

const stdx = @import("stdx");
const RangeSet = stdx.ranges.RangeSet;
const testing = std.testing;

fn expectRanges(comptime Range: type, expected: []const Range, actual: []const Range) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |want, got| try testing.expectEqual(want, got);
}

fn r(comptime Range: type, start: anytype, end: anytype) !Range {
    return Range.fromBounds(start, end);
}

test "unit: RangeSet construction and capacity" {
    var static = RangeSet.Static(u64, 2).init();
    try testing.expect(static.isEmpty());
    try testing.expect(!static.isFull());
    try testing.expectEqual(@as(usize, 2), static.capacity());
    try testing.expectEqual(@as(usize, 2), static.remaining());

    var backing: [3]RangeSet.Bounded(u64).Range = undefined;
    var bounded = RangeSet.Bounded(u64).wrap(&backing);
    try testing.expectEqual(@as(usize, 3), bounded.capacity());
    try bounded.insert(try r(@TypeOf(bounded).Range, 1, 2));
    bounded.clearRetainingCapacity();
    try testing.expect(bounded.isEmpty());
    try testing.expectEqual(@as(usize, 3), bounded.capacity());

    var zero_backing: [0]RangeSet.Bounded(u8).Range = .{};
    var zero_bounded = RangeSet.Bounded(u8).wrap(&zero_backing);
    try testing.expect(zero_bounded.isEmpty());
    try testing.expect(zero_bounded.isFull());
}

test "unit: RangeSet insert canonicalizes sorted adjacent and overlapping ranges" {
    const Set = RangeSet.Static(u64, 4);
    const Range = Set.Range;
    var set = Set.init();

    try set.insert(try r(Range, 30, 40));
    try set.insert(try r(Range, 10, 20));
    try expectRanges(Range, &.{ try r(Range, 10, 20), try r(Range, 30, 40) }, set.asConstSlice());

    try set.insert(Range.empty(25));
    try expectRanges(Range, &.{ try r(Range, 10, 20), try r(Range, 30, 40) }, set.asConstSlice());

    try set.insert(try r(Range, 20, 30));
    try expectRanges(Range, &.{try r(Range, 10, 40)}, set.asConstSlice());

    try set.insert(try r(Range, 15, 45));
    try expectRanges(Range, &.{try r(Range, 10, 45)}, set.asConstSlice());
    set.assertValid();
}

test "unit: RangeSet insert full and invalid leave unchanged" {
    const Set = RangeSet.Static(u8, 1);
    const Range = Set.Range;
    var set = Set.init();
    try set.insert(try r(Range, 10, 20));

    try testing.expectError(error.Full, set.insert(try r(Range, 30, 40)));
    try expectRanges(Range, &.{try r(Range, 10, 20)}, set.asConstSlice());

    try testing.expectError(error.InvalidRange, set.insert(.{ .start = 8, .end = 7 }));
    try expectRanges(Range, &.{try r(Range, 10, 20)}, set.asConstSlice());
}

test "unit: RangeSet remove deletes shrinks splits and spans" {
    const Set = RangeSet.Static(u64, 5);
    const Range = Set.Range;
    var set = Set.init();

    try set.insert(try r(Range, 10, 30));
    try set.remove(Range.empty(12));
    try set.remove(try r(Range, 40, 50));
    try expectRanges(Range, &.{try r(Range, 10, 30)}, set.asConstSlice());

    try set.remove(try r(Range, 10, 15));
    try expectRanges(Range, &.{try r(Range, 15, 30)}, set.asConstSlice());
    try set.remove(try r(Range, 25, 30));
    try expectRanges(Range, &.{try r(Range, 15, 25)}, set.asConstSlice());
    try set.remove(try r(Range, 18, 20));
    try expectRanges(Range, &.{ try r(Range, 15, 18), try r(Range, 20, 25) }, set.asConstSlice());

    try set.insert(try r(Range, 40, 50));
    try set.insert(try r(Range, 60, 70));
    try set.remove(try r(Range, 17, 65));
    try expectRanges(Range, &.{ try r(Range, 15, 17), try r(Range, 65, 70) }, set.asConstSlice());
    try set.remove(try r(Range, 15, 17));
    try expectRanges(Range, &.{try r(Range, 65, 70)}, set.asConstSlice());
    set.assertValid();
}

test "unit: RangeSet remove full split and invalid leave unchanged" {
    const Set = RangeSet.Static(u8, 1);
    const Range = Set.Range;
    var set = Set.init();
    try set.insert(try r(Range, 10, 30));

    try testing.expectError(error.Full, set.remove(try r(Range, 15, 20)));
    try expectRanges(Range, &.{try r(Range, 10, 30)}, set.asConstSlice());

    try testing.expectError(error.InvalidRange, set.remove(.{ .start = 8, .end = 7 }));
    try expectRanges(Range, &.{try r(Range, 10, 30)}, set.asConstSlice());
}

test "unit: RangeSet queries follow half-open and boundary rules" {
    const Set = RangeSet.Static(u64, 4);
    const Range = Set.Range;
    var set = Set.init();
    try set.insert(try r(Range, 10, 20));
    try set.insert(try r(Range, 30, 40));

    try testing.expect(set.contains(10));
    try testing.expect(!set.contains(20));
    try testing.expect(!set.contains(25));
    try testing.expectEqual(try r(Range, 10, 20), set.findContaining(19).?);
    try testing.expectEqual(@as(?Range, null), set.findContaining(20));
    try testing.expect(set.containsRange(try r(Range, 12, 18)));
    try testing.expect(!set.containsRange(try r(Range, 18, 31)));
    try testing.expect(!set.containsRange(try r(Range, 20, 30)));
    try testing.expect(set.containsRange(Range.empty(10)));
    try testing.expect(set.containsRange(Range.empty(20)));
    try testing.expect(!set.containsRange(Range.empty(25)));
    try testing.expect(!set.overlaps(try r(Range, 20, 30)));
    try testing.expect(!set.overlaps(Range.empty(15)));
    try testing.expectEqual(try r(Range, 30, 40), set.findIntersecting(try r(Range, 25, 35)).?);
}

test "model: RangeSet matches bitset over small domain" {
    const Set = RangeSet.Static(u8, 16);
    const Range = Set.Range;
    var set = Set.init();
    var model = [_]bool{false} ** 32;
    var prng = std.Random.Xoshiro256.init(0x12345678);
    const random = prng.random();

    var step: usize = 0;
    while (step < 160) : (step += 1) {
        const a = random.uintLessThan(u8, 32);
        const b = random.uintLessThan(u8, 32);
        const start = @min(a, b);
        const end = @max(a, b);
        const range = try r(Range, start, end);

        if (random.boolean()) {
            try set.insert(range);
            for (model[start..end]) |*bit| bit.* = true;
        } else {
            try set.remove(range);
            for (model[start..end]) |*bit| bit.* = false;
        }

        for (model, 0..) |bit, index| try testing.expectEqual(bit, set.contains(@intCast(index)));
        var cursor: usize = 0;
        for (set.asConstSlice()) |stored| {
            while (cursor < model.len and !model[cursor]) : (cursor += 1) {}
            const range_start = cursor;
            while (cursor < model.len and model[cursor]) : (cursor += 1) {}
            try testing.expectEqual(@as(u8, @intCast(range_start)), stored.start);
            try testing.expectEqual(@as(u8, @intCast(cursor)), stored.end);
        }
        while (cursor < model.len and !model[cursor]) : (cursor += 1) {}
        try testing.expectEqual(model.len, cursor);
    }
}

test "comptime: RangeSet mutates at compile time" {
    comptime {
        const Set = stdx.ranges.RangeSet.Static(u8, 4);
        const Range = Set.Range;

        var set = Set.init();
        try set.insert(Range.of(1, 3));
        try set.insert(Range.of(3, 5));

        std.debug.assert(set.len() == 1);
        std.debug.assert(set.contains(4));
        std.debug.assert(!set.contains(5));
    }
}
