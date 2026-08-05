//! RangeMap contract tests. See `docs/specs/ranges/map.md`.

const std = @import("std");

const stdx = @import("stdx");
const RangeMap = stdx.ranges.RangeMap;
const testing = std.testing;

const Kind = enum { a, b, c };

fn eqlKind(_: void, lhs: *const Kind, rhs: *const Kind) bool {
    return lhs.* == rhs.*;
}

fn neverEql(_: void, _: *const Kind, _: *const Kind) bool {
    return false;
}

fn r(comptime Range: type, start: anytype, end: anytype) !Range {
    return Range.fromBounds(start, end);
}

fn expectEntries(comptime Map: type, expected: []const Map.Entry, actual: []const Map.Entry) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |want, got| try testing.expectEqual(want, got);
}

test "unit: RangeMap construction and capacity" {
    var static = RangeMap.Static(u64, Kind, 2).init();
    try testing.expect(static.isEmpty());
    try testing.expect(!static.isFull());
    try testing.expectEqual(@as(usize, 2), static.capacity());
    try testing.expectEqual(@as(usize, 2), static.remaining());

    var backing: [3]RangeMap.Bounded(u64, Kind).Entry = undefined;
    var bounded = RangeMap.Bounded(u64, Kind).wrap(&backing);
    try testing.expectEqual(@as(usize, 3), bounded.capacity());
    try bounded.insert(try r(@TypeOf(bounded).Range, 1, 2), .a);
    bounded.clearRetainingCapacity();
    try testing.expect(bounded.isEmpty());
    try testing.expectEqual(@as(usize, 3), bounded.capacity());

    var zero_backing: [0]RangeMap.Bounded(u8, Kind).Entry = .{};
    var zero_bounded = RangeMap.Bounded(u8, Kind).wrap(&zero_backing);
    try testing.expect(zero_bounded.isEmpty());
    try testing.expect(zero_bounded.isFull());
}

test "unit: RangeMap insert sorts allows adjacency and rejects overlap" {
    const Map = RangeMap.Static(u64, Kind, 4);
    const Range = Map.Range;
    var map = Map.init();

    try map.insert(try r(Range, 30, 40), .c);
    try map.insert(try r(Range, 10, 20), .a);
    try map.insert(try r(Range, 20, 30), .a);
    try expectEntries(Map, &.{
        .{ .range = try r(Range, 10, 20), .value = .a },
        .{ .range = try r(Range, 20, 30), .value = .a },
        .{ .range = try r(Range, 30, 40), .value = .c },
    }, map.asConstSlice());

    try map.insert(Range.empty(25), .b);
    try testing.expectEqual(@as(usize, 3), map.len());

    try testing.expectError(error.Overlap, map.insert(try r(Range, 19, 21), .b));
    try testing.expectError(error.InvalidRange, map.insert(.{ .start = 9, .end = 8 }, .b));
    try expectEntries(Map, &.{
        .{ .range = try r(Range, 10, 20), .value = .a },
        .{ .range = try r(Range, 20, 30), .value = .a },
        .{ .range = try r(Range, 30, 40), .value = .c },
    }, map.asConstSlice());
}

test "unit: RangeMap insert full leaves unchanged" {
    const Map = RangeMap.Static(u8, Kind, 1);
    const Range = Map.Range;
    var map = Map.init();
    try map.insert(try r(Range, 10, 20), .a);
    try testing.expectError(error.Full, map.insert(try r(Range, 30, 40), .b));
    try expectEntries(Map, &.{.{ .range = try r(Range, 10, 20), .value = .a }}, map.asConstSlice());
}

test "unit: RangeMap assign overlays gaps and entries without auto-coalescing" {
    const Map = RangeMap.Static(u64, Kind, 8);
    const Range = Map.Range;
    var map = Map.init();

    try map.assign(Range.empty(3), .a);
    try testing.expect(map.isEmpty());
    try map.assign(try r(Range, 0, 10), .a);
    try map.assign(try r(Range, 20, 30), .b);
    try map.assign(try r(Range, 5, 25), .c);
    try expectEntries(Map, &.{
        .{ .range = try r(Range, 0, 5), .value = .a },
        .{ .range = try r(Range, 5, 25), .value = .c },
        .{ .range = try r(Range, 25, 30), .value = .b },
    }, map.asConstSlice());

    map.clearRetainingCapacity();
    try map.assign(try r(Range, 0, 100), .a);
    try map.assign(try r(Range, 40, 60), .b);
    try expectEntries(Map, &.{
        .{ .range = try r(Range, 0, 40), .value = .a },
        .{ .range = try r(Range, 40, 60), .value = .b },
        .{ .range = try r(Range, 60, 100), .value = .a },
    }, map.asConstSlice());

    try map.assign(try r(Range, 100, 110), .a);
    try testing.expectEqual(@as(usize, 4), map.len());
    map.assertValid();
}

test "unit: RangeMap assign full and invalid leave unchanged" {
    const Map = RangeMap.Static(u8, Kind, 2);
    const Range = Map.Range;
    var map = Map.init();
    try map.insert(try r(Range, 0, 10), .a);

    try testing.expectError(error.Full, map.assign(try r(Range, 3, 7), .b));
    try expectEntries(Map, &.{.{ .range = try r(Range, 0, 10), .value = .a }}, map.asConstSlice());

    try testing.expectError(error.InvalidRange, map.assign(.{ .start = 8, .end = 7 }, .b));
    try expectEntries(Map, &.{.{ .range = try r(Range, 0, 10), .value = .a }}, map.asConstSlice());
}

test "unit: RangeMap remove deletes shrinks splits spans and preserves values" {
    const Map = RangeMap.Static(u64, Kind, 6);
    const Range = Map.Range;
    var map = Map.init();

    try map.insert(try r(Range, 10, 30), .a);
    try map.remove(Range.empty(11));
    try map.remove(try r(Range, 40, 50));
    try expectEntries(Map, &.{.{ .range = try r(Range, 10, 30), .value = .a }}, map.asConstSlice());
    try map.remove(try r(Range, 10, 15));
    try map.remove(try r(Range, 25, 30));
    try map.remove(try r(Range, 18, 20));
    try expectEntries(Map, &.{
        .{ .range = try r(Range, 15, 18), .value = .a },
        .{ .range = try r(Range, 20, 25), .value = .a },
    }, map.asConstSlice());

    try map.insert(try r(Range, 40, 50), .b);
    try map.insert(try r(Range, 60, 70), .c);
    try map.remove(try r(Range, 17, 65));
    try expectEntries(Map, &.{
        .{ .range = try r(Range, 15, 17), .value = .a },
        .{ .range = try r(Range, 65, 70), .value = .c },
    }, map.asConstSlice());
    try map.remove(try r(Range, 15, 17));
    try expectEntries(Map, &.{.{ .range = try r(Range, 65, 70), .value = .c }}, map.asConstSlice());
}

test "unit: RangeMap remove full split and invalid leave unchanged" {
    const Map = RangeMap.Static(u8, Kind, 1);
    const Range = Map.Range;
    var map = Map.init();
    try map.insert(try r(Range, 10, 30), .a);

    try testing.expectError(error.Full, map.remove(try r(Range, 15, 20)));
    try expectEntries(Map, &.{.{ .range = try r(Range, 10, 30), .value = .a }}, map.asConstSlice());

    try testing.expectError(error.InvalidRange, map.remove(.{ .start = 8, .end = 7 }));
    try expectEntries(Map, &.{.{ .range = try r(Range, 10, 30), .value = .a }}, map.asConstSlice());
}

test "unit: RangeMap queries cover adjacent entries and gaps" {
    const Map = RangeMap.Static(u64, Kind, 4);
    const Range = Map.Range;
    var map = Map.init();
    try map.insert(try r(Range, 10, 20), .a);
    try map.insert(try r(Range, 20, 30), .b);
    try map.insert(try r(Range, 40, 50), .c);

    try testing.expect(map.contains(10));
    try testing.expect(!map.contains(30));
    try testing.expectEqual(Kind.a, map.get(19).?.*);
    try testing.expectEqual(@as(?*const Kind, null), map.get(30));
    try testing.expectEqual(try r(Range, 20, 30), map.findContaining(20).?.range);
    try testing.expect(map.containsRange(try r(Range, 12, 18)));
    try testing.expect(map.containsRange(try r(Range, 12, 30)));
    try testing.expect(!map.containsRange(try r(Range, 12, 40)));
    try testing.expect(map.containsRange(Range.empty(10)));
    try testing.expect(map.containsRange(Range.empty(30)));
    try testing.expect(!map.containsRange(Range.empty(35)));
    try testing.expect(!map.overlaps(try r(Range, 30, 40)));
    try testing.expect(!map.overlaps(Range.empty(15)));
    try testing.expectEqual(try r(Range, 40, 50), map.findIntersecting(try r(Range, 35, 45)).?.range);
}

test "unit: RangeMap coalesceAdjacent is explicit and callback-driven" {
    const Map = RangeMap.Static(u64, Kind, 5);
    const Range = Map.Range;
    var map = Map.init();
    try map.insert(try r(Range, 0, 10), .a);
    try map.insert(try r(Range, 10, 20), .a);
    try map.insert(try r(Range, 20, 30), .b);
    try map.insert(try r(Range, 40, 50), .a);

    try testing.expectEqual(@as(usize, 4), map.len());
    map.coalesceAdjacent({}, neverEql);
    try testing.expectEqual(@as(usize, 4), map.len());
    map.coalesceAdjacent({}, eqlKind);
    try expectEntries(Map, &.{
        .{ .range = try r(Range, 0, 20), .value = .a },
        .{ .range = try r(Range, 20, 30), .value = .b },
        .{ .range = try r(Range, 40, 50), .value = .a },
    }, map.asConstSlice());
}

test "model: RangeMap matches optional array over small domain" {
    const Map = RangeMap.Static(u8, Kind, 32);
    const Range = Map.Range;
    var map = Map.init();
    var model = [_]?Kind{null} ** 32;
    var prng = std.Random.Xoshiro256.init(0x87654321);
    const random = prng.random();

    var step: usize = 0;
    while (step < 180) : (step += 1) {
        const a = random.uintLessThan(u8, 32);
        const b = random.uintLessThan(u8, 32);
        const start = @min(a, b);
        const end = @max(a, b);
        const range = try r(Range, start, end);
        const value: Kind = switch (random.uintLessThan(u8, 3)) {
            0 => .a,
            1 => .b,
            else => .c,
        };

        switch (random.uintLessThan(u8, 4)) {
            0 => if (map.insert(range, value)) {
                for (model[start..end]) |*slot| slot.* = value;
            } else |err| switch (err) {
                error.Overlap => {},
                else => return err,
            },
            1, 2 => {
                try map.assign(range, value);
                for (model[start..end]) |*slot| slot.* = value;
            },
            else => {
                try map.remove(range);
                for (model[start..end]) |*slot| slot.* = null;
            },
        }
        if (random.boolean()) map.coalesceAdjacent({}, eqlKind);

        for (model, 0..) |slot, index| {
            const got = map.get(@intCast(index));
            if (slot) |want| {
                try testing.expectEqual(want, got.?.*);
            } else {
                try testing.expectEqual(@as(?*const Kind, null), got);
            }
        }

        for (map.asConstSlice()) |entry| {
            try testing.expect(entry.range.start < entry.range.end);
            for (entry.range.start..entry.range.end) |index| {
                try testing.expectEqual(entry.value, model[index].?);
            }
        }
    }
}

test "comptime: RangeMap mutates at compile time" {
    comptime {
        const Map = stdx.ranges.RangeMap.Static(u8, enum { a, b }, 4);
        const Range = Map.Range;

        var map = Map.init();
        try map.insert(Range.of(1, 3), .a);
        try map.assign(Range.of(2, 5), .b);

        std.debug.assert(map.contains(4));
        std.debug.assert(map.get(1).?.* == .a);
        std.debug.assert(map.get(2).?.* == .b);
        std.debug.assert(!map.contains(5));
    }
}
