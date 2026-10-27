const std = @import("std");

const stdx = @import("stdx");

const Arena = stdx.mem.alloc.Arena;
const testing = std.testing;

test "integration: borrowed arena preserves ArrayList values through growth and exhaustion" {
    var storage: [512]u8 align(8) = undefined;
    var arena = Arena.Bounded.wrap(storage[1..]);
    try exerciseList(&arena);
}

test "integration: inline arena preserves ArrayList values through growth and exhaustion" {
    var arena = Arena.Static(512).init();
    try exerciseList(&arena);
}

fn exerciseList(arena: anytype) !void {
    const allocator = arena.allocator();
    var list = std.ArrayListUnmanaged(u32).empty;
    defer list.deinit(allocator);

    try list.append(allocator, 11);
    const first_ptr = list.items.ptr;
    const first_capacity = list.capacity;
    for (1..first_capacity + 1) |i| {
        try list.append(allocator, @intCast(i + 11));
    }

    try testing.expect(list.items.ptr != first_ptr);
    try testing.expect(list.capacity > first_capacity);
    for (list.items, 0..) |value, i| {
        try testing.expectEqual(@as(u32, @intCast(i + 11)), value);
    }

    while (true) {
        const used_before = arena.used();
        const len_before = list.items.len;
        const ptr_before = list.items.ptr;
        list.append(allocator, @intCast(len_before + 11)) catch |err| {
            try testing.expectEqual(error.OutOfMemory, err);
            try testing.expectEqual(used_before, arena.used());
            try testing.expectEqual(len_before, list.items.len);
            try testing.expectEqual(ptr_before, list.items.ptr);
            break;
        };
    }

    for (list.items, 0..) |value, i| {
        try testing.expectEqual(@as(u32, @intCast(i + 11)), value);
    }
    try testing.expect(arena.isValid());
}
