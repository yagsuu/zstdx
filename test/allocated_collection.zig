const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;

const List = stdx.collections.List.Bounded(u32);

test "integration: arena-backed lists preserve values through collection and allocator exhaustion" {
    var storage: [64]u8 align(@alignOf(u32)) = undefined;
    var arena = stdx.mem.alloc.Arena.Bounded.wrap(&storage);

    const checkpoint = arena.mark();
    defer arena.restore(checkpoint);

    var first = List.wrap(try arena.allocSlice(u32, 4));
    defer first.clearRetainingCapacity();
    try first.appendSlice(&.{ 10, 20, 30, 40 });

    try testing.expectError(error.Full, first.append(50));
    try testing.expectEqualSlices(u32, &.{ 10, 20, 30, 40 }, first.slice());

    var second = List.wrap(try arena.allocSlice(u32, 12));
    defer second.clearRetainingCapacity();

    for (0..second.capacity()) |index| try second.append(@intCast(index * 3));

    try testing.expectEqual(@as(usize, 0), arena.remaining());
    const used = arena.used();

    try testing.expectError(error.OutOfMemory, arena.allocSlice(u32, 1));
    try testing.expectEqual(used, arena.used());
    try testing.expectEqualSlices(u32, &.{ 10, 20, 30, 40 }, first.slice());
    try testing.expectEqualSlices(u32, &.{ 0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33 }, second.slice());

    (try first.atMut(1)).* = 99;
    try testing.expectEqualSlices(u32, &.{ 10, 99, 30, 40 }, first.slice());
    try testing.expectEqual(@as(u32, 3), (try second.at(1)).*);
}

test "integration: arena checkpoint reclaims temporary list storage without changing earlier values" {
    var storage: [64]u8 align(@alignOf(u32)) = undefined;
    var arena = stdx.mem.alloc.Arena.Bounded.wrap(&storage);
    defer arena.reset();

    var retained = List.wrap(try arena.allocSlice(u32, 4));
    defer retained.clearRetainingCapacity();
    try retained.appendSlice(&.{ 2, 4, 6, 8 });

    const checkpoint = arena.mark();

    {
        defer arena.restore(checkpoint);

        var temporary = List.wrap(try arena.allocSlice(u32, 12));
        defer temporary.clearRetainingCapacity();

        try temporary.appendSlice(&.{ 11, 22, 33 });

        try testing.expectEqual(@as(u32, 22), try temporary.orderedRemove(1));
        try testing.expectEqualSlices(u32, &.{ 11, 33 }, temporary.slice());
        try testing.expectEqual(@as(usize, 0), arena.remaining());
    }

    try testing.expectEqual(checkpoint.index, arena.used());

    var replacement = List.wrap(try arena.allocSlice(u32, 12));
    defer replacement.clearRetainingCapacity();

    try replacement.appendSlice(&.{ 101, 102, 103 });
    try testing.expectEqualSlices(u32, &.{ 101, 102, 103 }, replacement.slice());
    try testing.expectEqualSlices(u32, &.{ 2, 4, 6, 8 }, retained.slice());
}
