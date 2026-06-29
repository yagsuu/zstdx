//! List contract tests.
//! Specs: docs/specs/collections/list-static.md and docs/specs/collections/list-bounded.md.

const std = @import("std");

const zstdx = @import("zstdx");

const List = zstdx.List;

const testing = std.testing;

fn exerciseSequence(comptime L: type, list_ptr: *L) !void {
    try testing.expect(list_ptr.isEmpty());
    try list_ptr.append(1);
    try list_ptr.appendSlice(&.{ 2, 3 });
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, list_ptr.asConstSlice());
    try testing.expectError(error.Full, list_ptr.append(4));
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, list_ptr.asConstSlice());
    try testing.expectError(error.OutOfBounds, list_ptr.insert(4, 9));
    try testing.expectEqual(@as(u8, 2), (try list_ptr.at(1)).*);
    try testing.expectEqual(@as(u8, 3), (try list_ptr.constAt(2)).*);
    try testing.expectEqual(@as(u8, 2), try list_ptr.orderedRemove(1));
    try testing.expectEqualSlices(u8, &.{ 1, 3 }, list_ptr.asConstSlice());
    try list_ptr.insert(1, 2);
    try testing.expectEqual(@as(u8, 1), try list_ptr.swapRemove(0));
    try testing.expectEqual(@as(usize, 2), list_ptr.len());
    _ = list_ptr.pop();
    _ = list_ptr.pop();
    try testing.expectEqual(@as(?u8, null), list_ptr.pop());
    list_ptr.clearRetainingCapacity();
    list_ptr.assertValid();
}

test "unit: List.Static(T, 0) is both empty and full" {
    var zero = List.Static(u8, 0).init();
    try testing.expect(zero.isFull());
    try testing.expectError(error.Full, zero.append(1));
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
