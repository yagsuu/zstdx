//! Intrusive Heap contract tests. See `docs/specs/intrusive/heap.md`.

const std = @import("std");
const testing = std.testing;

const stdx = @import("stdx");
const heap = stdx.intrusive.heap;

const Item = struct {
    id: usize = 0,
    priority: i32,
    node: heap.Node = .{},
    other_node: heap.Node = .{},

    fn less(lhs: *const Item, rhs: *const Item) bool {
        return lhs.priority < rhs.priority;
    }

    fn greater(lhs: *const Item, rhs: *const Item) bool {
        return lhs.priority > rhs.priority;
    }
};

const ReferenceItem = struct {
    priority: i32 = 0,
    present: bool = false,
};

const Items = heap.Heap(Item, "node", Item.less);
const OtherItems = heap.Heap(Item, "other_node", Item.less);
const MaxItems = heap.Heap(Item, "other_node", Item.greater);

test "unit: intrusive heap detaches nodes across singleton transitions" {
    var items: Items = .{};
    var item: Item = .{ .priority = 7 };

    const read_only: *const Items = &items;

    try testing.expectEqual(@as(usize, 0), items.len());
    try testing.expect(read_only.peek() == null);
    try testing.expect(items.peekMut() == null);
    try testing.expect(items.pop() == null);

    items.insert(&item);
    items.assertValid();

    try testing.expectEqual(@as(usize, 1), items.len());
    try testing.expectEqual(@as(?*const Item, &item), read_only.peek());

    const popped = items.pop().?;
    items.assertValid();

    try testing.expectEqual(&item, popped);
    try expectDetached(&item.node);
    try testing.expect(items.isEmpty());

    items.insert(&item);
    items.remove(&item);
    items.assertValid();

    try expectDetached(&item.node);
    try testing.expect(items.isEmpty());

    items.insert(&item);
    items.clear();
    items.assertValid();

    try expectDetached(&item.node);
    try testing.expect(items.isEmpty());

    items.clear();
    items.assertValid();

    try testing.expectEqual(@as(usize, 0), items.len());
}

test "ordering: intrusive heap supports reversed comparison and duplicate priorities" {
    const priorities = [_]i32{ 3, -1, 3, 0, 9, -1, 2 };
    const expected = [_]i32{ -1, -1, 0, 2, 3, 3, 9 };

    var storage: [priorities.len]Item = undefined;
    var minimum = Items.init();
    var maximum = MaxItems.init();

    for (&storage, priorities) |*item, priority| {
        item.* = .{ .priority = priority };
        minimum.insert(item);
        maximum.insert(item);
    }

    minimum.assertValid();
    maximum.assertValid();

    for (expected, 0..) |priority, index| {
        const smallest = minimum.pop().?;
        const largest = maximum.pop().?;

        try testing.expectEqual(priority, smallest.priority);
        try testing.expectEqual(expected[expected.len - index - 1], largest.priority);
        try expectDetached(&smallest.node);
        try expectDetached(&largest.other_node);

        minimum.assertValid();
        maximum.assertValid();
    }

    try testing.expect(minimum.pop() == null);
    try testing.expect(maximum.pop() == null);
}

test "unit: intrusive heap preserves objects through updates and replacement" {
    var storage: [7]Item = undefined;
    var items = Items.init();

    for (&storage, 0..) |*item, index| {
        item.* = .{ .priority = @intCast(index) };
        items.insert(item);
    }

    storage[6].priority = -1;
    items.update(&storage[6]);

    items.assertValid();
    try testing.expectEqual(@as(?*const Item, &storage[6]), items.peek());

    const minimum = items.peekMut().?;
    minimum.priority = 10;

    items.update(minimum);
    items.assertValid();

    try testing.expectEqual(@as(?*const Item, &storage[0]), items.peek());

    items.update(&storage[3]);
    items.assertValid();

    for (&storage) |*expected| {
        const actual = items.pop().?;

        try testing.expectEqual(expected, actual);
        try expectDetached(&actual.node);
        items.assertValid();
    }

    for ([_]usize{ 2, 3, 7 }) |count| {
        for (0..count) |removed| {
            var fresh = Items.init();
            for (storage[0..count], 0..) |*item, index| {
                item.* = .{ .priority = @intCast(index) };
                fresh.insert(item);
            }

            fresh.remove(&storage[removed]);
            fresh.assertValid();

            try testing.expectEqual(count - 1, fresh.len());
            try expectDetached(&storage[removed].node);

            fresh.insert(&storage[removed]);
            fresh.assertValid();

            try testing.expectEqual(count, fresh.len());

            for (storage[0..count]) |*expected| {
                const actual = fresh.pop().?;

                try testing.expectEqual(expected, actual);
                try expectDetached(&actual.node);
                fresh.assertValid();
            }
        }
    }
}

test "contract: intrusive heap memberships remain independent" {
    var first = Items.init();
    var second = OtherItems.init();

    var storage = [_]Item{
        .{ .priority = 3 },
        .{ .priority = 1 },
        .{ .priority = 2 },
    };

    for (&storage) |*item| {
        first.insert(item);
        second.insert(item);
    }

    first.remove(&storage[0]);
    first.assertValid();
    second.assertValid();

    try expectDetached(&storage[0].node);
    try testing.expect(storage[0].other_node.linked);
    try testing.expectEqual(@as(usize, 3), second.len());
    try testing.expectEqual(@as(?*const Item, &storage[1]), second.peek());

    first.clear();
    first.assertValid();
    second.assertValid();

    for (&storage) |*item| {
        try expectDetached(&item.node);
        try testing.expect(item.other_node.linked);
    }

    for (&storage) |*item| {
        first.insert(item);
    }

    for ([_]usize{ 1, 2, 0 }) |index| {
        const from_first = first.pop().?;
        const from_second = second.pop().?;

        try testing.expectEqual(&storage[index], from_first);
        try testing.expectEqual(&storage[index], from_second);
        try expectDetached(&from_first.node);
        try expectDetached(&from_second.other_node);

        first.assertValid();
        second.assertValid();
    }
}

test "model: intrusive heap matches reference priorities and object identities" {
    const Operation = enum { insert, update, remove, pop };

    var storage: [33]Item = undefined;
    var reference = [_]ReferenceItem{.{}} ** storage.len;
    var items = Items.init();
    var random = std.Random.DefaultPrng.init(0x8e9142b7);

    const rng = random.random();

    for (&storage, &reference, 0..) |*item, *expected, index| {
        const priority = rng.intRangeAtMost(i32, -8, 8);
        item.* = .{ .id = index, .priority = priority };
        expected.* = .{ .priority = priority };
    }

    for (&storage, &reference) |*item, *expected| {
        expected.present = true;
        items.insert(item);

        try expectModel(&items, &storage, &reference);
    }

    const operations = [_]Operation{ .insert, .insert, .update, .remove, .pop };

    for (0..512) |_| {
        var operation = operations[rng.uintLessThan(usize, operations.len)];

        if (items.isEmpty()) {
            operation = .insert;
        }

        if (items.len() == storage.len and operation == .insert) {
            operation = .update;
        }

        if (operation == .pop) {
            try expectModelPop(&items, &storage, &reference);
        } else {
            const needs_present = operation != .insert;
            const start = rng.uintLessThan(usize, storage.len);
            const index = try referenceSlot(&reference, needs_present, start);

            switch (operation) {
                .insert => {
                    const priority = rng.intRangeAtMost(i32, -8, 8);
                    storage[index].priority = priority;
                    items.insert(&storage[index]);
                    reference[index] = .{ .priority = priority, .present = true };
                },
                .update => {
                    const priority = rng.intRangeAtMost(i32, -8, 8);
                    storage[index].priority = priority;
                    items.update(&storage[index]);
                    reference[index].priority = priority;
                },
                .remove => {
                    items.remove(&storage[index]);
                    reference[index].present = false;
                },
                .pop => unreachable,
            }
        }

        try expectModel(&items, &storage, &reference);
    }

    const remaining = items.len();
    for (0..remaining) |_| {
        try expectModelPop(&items, &storage, &reference);
        try expectModel(&items, &storage, &reference);
    }
}

fn expectDetached(node: *const heap.Node) !void {
    try testing.expect(!node.linked);
    try testing.expect(node.parent == null);
    try testing.expect(node.left == null);
    try testing.expect(node.right == null);
}

fn expectModel(items: *const Items, storage: []const Item, reference: []const ReferenceItem) !void {
    var expected_count: usize = 0;
    for (storage, reference, 0..) |*item, expected, index| {
        try testing.expectEqual(index, item.id);
        try testing.expectEqual(expected.priority, item.priority);
        if (expected.present) {
            expected_count += 1;
            try testing.expect(item.node.linked);
        } else {
            try expectDetached(&item.node);
        }
    }

    items.assertValid();
    try testing.expectEqual(expected_count, items.len());

    const minimum = referenceMinimum(reference);
    if (items.peek()) |item| {
        try testing.expect(item.id < storage.len);
        try testing.expectEqual(&storage[item.id], item);
        try testing.expect(reference[item.id].present);
        try testing.expect(minimum != null);
        try testing.expectEqual(minimum.?, item.priority);
    } else {
        try testing.expect(minimum == null);
    }
}

fn expectModelPop(items: *Items, storage: []const Item, reference: []ReferenceItem) !void {
    const minimum = referenceMinimum(reference) orelse return error.UnexpectedEmptyReference;
    const item = items.pop() orelse return error.UnexpectedEmptyHeap;

    try testing.expect(item.id < storage.len);
    try testing.expectEqual(&storage[item.id], @as(*const Item, item));
    try testing.expect(reference[item.id].present);
    try testing.expectEqual(minimum, item.priority);
    try expectDetached(&item.node);

    reference[item.id].present = false;
}

fn referenceMinimum(reference: []const ReferenceItem) ?i32 {
    var minimum: ?i32 = null;
    for (reference) |item| {
        if (!item.present) continue;
        if (minimum == null or item.priority < minimum.?) minimum = item.priority;
    }
    return minimum;
}

fn referenceSlot(reference: []const ReferenceItem, present: bool, start: usize) !usize {
    for (0..reference.len) |offset| {
        const index = (start + offset) % reference.len;
        if (reference[index].present == present) return index;
    }
    return error.NoMatchingReferenceSlot;
}
