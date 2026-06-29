//! Intrusive Queue contract tests. Spec: docs/specs/intrusive/queue.md.

const std = @import("std");

const zstdx = @import("zstdx");
const List = zstdx.intrusive.List;
const Queue = zstdx.intrusive.Queue;
const testing = std.testing;

const Item = struct {
    id: u32,
    node: List.SinglyLinkedNode = .{},
    other_node: List.SinglyLinkedNode = .{},
};

const Items = Queue(Item, "node");
const OtherItems = Queue(Item, "other_node");

fn expectDetached(item: *const Item) !void {
    try testing.expectEqual(@as(?*List.SinglyLinkedNode, null), item.node.next);
}

fn expectQueueOrder(queue: *Items, expected: []const *Item) !void {
    queue.assertValid();
    if (expected.len == 0) {
        try testing.expect(queue.isEmpty());
        try testing.expectEqual(@as(?*Item, null), queue.front());
        try testing.expectEqual(@as(?*Item, null), queue.back());
        return;
    }
    try testing.expectEqual(expected[0], queue.front().?);
    try testing.expectEqual(expected[expected.len - 1], queue.back().?);
}

test "unit: intrusive queue construction and empty access" {
    var queue = Items.init();
    var default_queue: Items = .{};

    try testing.expect(queue.isEmpty());
    try testing.expect(default_queue.isEmpty());
    try testing.expectEqual(@as(?*Item, null), queue.front());
    try testing.expectEqual(@as(?*const Item, null), queue.constFront());
    try testing.expectEqual(@as(?*Item, null), queue.back());
    try testing.expectEqual(@as(?*const Item, null), queue.constBack());
    try testing.expectEqual(@as(?*Item, null), queue.popFront());
}

test "unit: intrusive queue preserves FIFO order and endpoints" {
    var queue = Items.init();
    var a: Item = .{ .id = 1 };
    var b: Item = .{ .id = 2 };
    var c: Item = .{ .id = 3 };

    queue.pushBack(&a);
    try expectQueueOrder(&queue, &.{&a});
    try testing.expectEqual(@as(?*const Item, &a), queue.constFront());
    try testing.expectEqual(@as(?*const Item, &a), queue.constBack());

    queue.pushBack(&b);
    queue.pushBack(&c);
    try expectQueueOrder(&queue, &.{ &a, &b, &c });
    try testing.expectEqual(&a, queue.front().?);
    try testing.expectEqual(&c, queue.back().?);

    try testing.expectEqual(&a, queue.popFront().?);
    try expectDetached(&a);
    try expectQueueOrder(&queue, &.{ &b, &c });
    try testing.expectEqual(&b, queue.popFront().?);
    try expectDetached(&b);
    try expectQueueOrder(&queue, &.{&c});
    try testing.expectEqual(&c, queue.popFront().?);
    try expectDetached(&c);
    try expectQueueOrder(&queue, &.{});
}

test "unit: intrusive queue clear detaches and permits reinsertion" {
    var queue = Items.init();
    var a: Item = .{ .id = 1 };
    var b: Item = .{ .id = 2 };
    var c: Item = .{ .id = 3 };

    queue.clear();
    queue.pushBack(&a);
    queue.clear();
    try expectQueueOrder(&queue, &.{});
    try expectDetached(&a);

    queue.pushBack(&a);
    queue.pushBack(&b);
    queue.pushBack(&c);
    queue.clear();
    try expectQueueOrder(&queue, &.{});
    try expectDetached(&a);
    try expectDetached(&b);
    try expectDetached(&c);

    queue.pushBack(&a);
    queue.pushBack(&b);
    try expectQueueOrder(&queue, &.{ &a, &b });
}

test "unit: intrusive queue uses singly nodes and supports distinct memberships" {
    var ready = Items.init();
    var free = OtherItems.init();
    var a: Item = .{ .id = 1 };
    var b: Item = .{ .id = 2 };
    const a_address = &a;
    const b_address = &b;

    ready.pushBack(&a);
    ready.pushBack(&b);
    free.pushBack(&b);
    free.pushBack(&a);

    try testing.expectEqual(a_address, ready.front().?);
    try testing.expectEqual(b_address, ready.back().?);
    try testing.expectEqual(b_address, free.front().?);
    try testing.expectEqual(a_address, free.back().?);

    try testing.expectEqual(a_address, ready.popFront().?);
    try expectDetached(&a);
    try testing.expectEqual(a_address, free.back().?);
    try testing.expectEqual(b_address, ready.front().?);
    ready.assertValid();
    free.assertValid();
}
