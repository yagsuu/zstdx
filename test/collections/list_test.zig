//! List contract tests.
//! See `docs/specs/collections/list/static.md` and `docs/specs/collections/list/bounded.md`.

const std = @import("std");

const stdx = @import("stdx");

const List = stdx.collections.List;

const testing = std.testing;

fn exerciseSequence(comptime L: type, list: *L) !void {
    try testing.expect(list.isEmpty());

    try list.append(1);
    try list.appendSlice(&.{ 2, 3 });

    try testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, list.asConstSlice());
    try testing.expectError(error.Full, list.append(4));
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, list.asConstSlice());
    try testing.expectError(error.OutOfBounds, list.insert(4, 9));
    try testing.expectEqual(@as(u8, 2), (try list.at(1)).*);
    try testing.expectEqual(@as(u8, 3), (try list.constAt(2)).*);
    try testing.expectEqual(@as(u8, 2), try list.orderedRemove(1));
    try testing.expectEqualSlices(u8, &.{ 1, 3 }, list.asConstSlice());

    try list.insert(1, 2);

    try testing.expectEqual(@as(u8, 1), try list.swapRemove(0));
    try testing.expectEqual(@as(usize, 2), list.len());

    _ = list.pop();
    _ = list.pop();

    try testing.expectEqual(@as(?u8, null), list.pop());

    list.clearRetainingCapacity();
    list.assertValid();
}

test "unit: List.Static runs the append/remove/insert sequence" {
    var stat = List.Static(u8, 3).init();
    try exerciseSequence(@TypeOf(stat), &stat);
}

test "unit: List.Bounded runs the same sequence over borrowed storage" {
    var backing: [3]u8 = undefined;
    var bounded = List.Bounded(u8).wrap(&backing);
    try exerciseSequence(@TypeOf(bounded), &bounded);
}

test "unit: List.Bounded models the sibling table-list shape" {
    var scratch: [4]u32 = undefined;
    var tables = List.Bounded(u32).wrap(&scratch);
    try tables.appendSlice(&.{ 10, 20 });
    try testing.expectEqualSlices(u32, &.{ 10, 20 }, tables.asConstSlice());
}
