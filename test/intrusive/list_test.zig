//! Intrusive List contract tests. Spec: docs/specs/intrusive/list.md.

const std = @import("std");

const stdx = @import("stdx");
const IntrusiveList = stdx.intrusive.List;
const testing = std.testing;

const Item = struct {
    id: u32,
    singly: IntrusiveList.SinglyLinkedNode = .{},
    singly_other: IntrusiveList.SinglyLinkedNode = .{},
    doubly: IntrusiveList.DoublyLinkedNode = .{},
    doubly_other: IntrusiveList.DoublyLinkedNode = .{},
};

const Singly = IntrusiveList.SinglyLinked(Item, "singly");
const SinglyOther = IntrusiveList.SinglyLinked(Item, "singly_other");
const Doubly = IntrusiveList.DoublyLinked(Item, "doubly");
const DoublyOther = IntrusiveList.DoublyLinked(Item, "doubly_other");

fn expectSinglyOrder(list: *Singly, expected: []const *Item) !void {
    list.assertValid();
    var current = list.front();
    var index: usize = 0;
    while (current) |item| {
        try testing.expect(index < expected.len);
        try testing.expectEqual(expected[index], item);
        current = Singly.next(item);
        index += 1;
    }
    try testing.expectEqual(expected.len, index);
    if (expected.len == 0) {
        try testing.expectEqual(@as(?*Item, null), list.back());
    } else {
        try testing.expectEqual(expected[expected.len - 1], list.back().?);
    }
}

fn expectDoublyOrder(list: *Doubly, expected: []const *Item) !void {
    list.assertValid();
    var current = list.front();
    var index: usize = 0;
    while (current) |item| {
        try testing.expect(index < expected.len);
        try testing.expectEqual(expected[index], item);
        current = Doubly.next(item);
        index += 1;
    }
    try testing.expectEqual(expected.len, index);

    var reverse = list.back();
    index = expected.len;
    while (reverse) |item| {
        try testing.expect(index > 0);
        index -= 1;
        try testing.expectEqual(expected[index], item);
        reverse = Doubly.previous(item);
    }
    try testing.expectEqual(@as(usize, 0), index);
}

fn expectDetachedSingly(item: *const Item) !void {
    try testing.expectEqual(@as(?*IntrusiveList.SinglyLinkedNode, null), item.singly.next);
}

fn expectDetachedDoubly(item: *const Item) !void {
    try testing.expectEqual(@as(?*IntrusiveList.DoublyLinkedNode, null), item.doubly.prev);
    try testing.expectEqual(@as(?*IntrusiveList.DoublyLinkedNode, null), item.doubly.next);
}

test "unit: intrusive singly and doubly construction is empty" {
    var singly = Singly.init();
    var singly_default: Singly = .{};
    var doubly = Doubly.init();
    var doubly_default: Doubly = .{};

    try testing.expect(singly.isEmpty());
    try testing.expect(doubly.isEmpty());
    try testing.expect(singly_default.isEmpty());
    try testing.expect(doubly_default.isEmpty());
    try testing.expectEqual(@as(?*Item, null), singly.front());
    try testing.expectEqual(@as(?*const Item, null), singly.constFront());
    try testing.expectEqual(@as(?*Item, null), singly.back());
    try testing.expectEqual(@as(?*const Item, null), singly.constBack());
    try testing.expectEqual(@as(?*Item, null), doubly.front());
    try testing.expectEqual(@as(?*const Item, null), doubly.constFront());
    try testing.expectEqual(@as(?*Item, null), doubly.back());
    try testing.expectEqual(@as(?*const Item, null), doubly.constBack());
}

test "unit: intrusive singly insertion traversal removal and reinsertion" {
    var list = Singly.init();
    var a: Item = .{ .id = 1 };
    var b: Item = .{ .id = 2 };
    var c: Item = .{ .id = 3 };
    var d: Item = .{ .id = 4 };

    list.pushFront(&b);
    try expectSinglyOrder(&list, &.{&b});
    list.pushFront(&a);
    try expectSinglyOrder(&list, &.{ &a, &b });
    list.pushBack(&d);
    try expectSinglyOrder(&list, &.{ &a, &b, &d });
    list.insertAfter(&b, &c);
    try expectSinglyOrder(&list, &.{ &a, &b, &c, &d });
    try testing.expectEqual(&c, Singly.next(&b).?);
    try testing.expectEqual(&c, Singly.constNext(&b).?);

    var missing: Item = .{ .id = 99 };
    try testing.expect(!list.tryRemove(&missing));
    try expectSinglyOrder(&list, &.{ &a, &b, &c, &d });

    try testing.expect(list.tryRemove(&a));
    try expectDetachedSingly(&a);
    try expectSinglyOrder(&list, &.{ &b, &c, &d });
    try testing.expect(list.tryRemove(&c));
    try expectDetachedSingly(&c);
    try expectSinglyOrder(&list, &.{ &b, &d });
    try testing.expect(list.tryRemove(&d));
    try expectDetachedSingly(&d);
    try expectSinglyOrder(&list, &.{&b});

    list.pushBack(&d);
    try expectSinglyOrder(&list, &.{ &b, &d });
    try testing.expectEqual(&b, list.popFront().?);
    try expectDetachedSingly(&b);
    try expectSinglyOrder(&list, &.{&d});
    try testing.expectEqual(&d, list.popFront().?);
    try expectDetachedSingly(&d);
    try testing.expectEqual(@as(?*Item, null), list.popFront());
    try expectSinglyOrder(&list, &.{});
}

test "unit: intrusive singly pushBack empty insertAfter tail and clear detach" {
    var list = Singly.init();
    var a: Item = .{ .id = 1 };
    var b: Item = .{ .id = 2 };
    var c: Item = .{ .id = 3 };

    list.clear();
    list.pushBack(&a);
    try expectSinglyOrder(&list, &.{&a});
    list.insertAfter(&a, &b);
    try expectSinglyOrder(&list, &.{ &a, &b });
    list.insertAfter(&b, &c);
    try expectSinglyOrder(&list, &.{ &a, &b, &c });
    list.clear();
    try expectSinglyOrder(&list, &.{});
    try expectDetachedSingly(&a);
    try expectDetachedSingly(&b);
    try expectDetachedSingly(&c);

    list.pushFront(&a);
    list.clear();
    try expectDetachedSingly(&a);
    list.pushBack(&a);
    try expectSinglyOrder(&list, &.{&a});
}

test "unit: intrusive doubly insertion traversal removal and reinsertion" {
    var list = Doubly.init();
    var a: Item = .{ .id = 1 };
    var b: Item = .{ .id = 2 };
    var c: Item = .{ .id = 3 };
    var d: Item = .{ .id = 4 };
    var e: Item = .{ .id = 5 };

    list.pushFront(&c);
    try expectDoublyOrder(&list, &.{&c});
    list.pushFront(&a);
    try expectDoublyOrder(&list, &.{ &a, &c });
    list.pushBack(&e);
    try expectDoublyOrder(&list, &.{ &a, &c, &e });
    list.insertAfter(&a, &b);
    try expectDoublyOrder(&list, &.{ &a, &b, &c, &e });
    list.insertBefore(&e, &d);
    try expectDoublyOrder(&list, &.{ &a, &b, &c, &d, &e });
    try testing.expectEqual(&c, Doubly.next(&b).?);
    try testing.expectEqual(&b, Doubly.previous(&c).?);
    try testing.expectEqual(&c, Doubly.constNext(&b).?);
    try testing.expectEqual(&b, Doubly.constPrevious(&c).?);

    list.remove(&a);
    try expectDetachedDoubly(&a);
    try expectDoublyOrder(&list, &.{ &b, &c, &d, &e });
    list.remove(&c);
    try expectDetachedDoubly(&c);
    try expectDoublyOrder(&list, &.{ &b, &d, &e });
    list.remove(&e);
    try expectDetachedDoubly(&e);
    try expectDoublyOrder(&list, &.{ &b, &d });

    list.insertBefore(&b, &a);
    list.insertAfter(&d, &e);
    list.insertBefore(&d, &c);
    try expectDoublyOrder(&list, &.{ &a, &b, &c, &d, &e });
}

test "unit: intrusive doubly pops and clear detach nodes" {
    var list = Doubly.init();
    var a: Item = .{ .id = 1 };
    var b: Item = .{ .id = 2 };
    var c: Item = .{ .id = 3 };
    var d: Item = .{ .id = 4 };

    try testing.expectEqual(@as(?*Item, null), list.popFront());
    try testing.expectEqual(@as(?*Item, null), list.popBack());
    list.pushBack(&a);
    try testing.expectEqual(&a, list.popBack().?);
    try expectDetachedDoubly(&a);
    try expectDoublyOrder(&list, &.{});

    list.pushBack(&a);
    try testing.expectEqual(&a, list.popFront().?);
    try expectDetachedDoubly(&a);
    try expectDoublyOrder(&list, &.{});

    list.pushBack(&a);
    list.pushBack(&b);
    list.pushBack(&c);
    try testing.expectEqual(&a, list.popFront().?);
    try expectDetachedDoubly(&a);
    try expectDoublyOrder(&list, &.{ &b, &c });
    try testing.expectEqual(&c, list.popBack().?);
    try expectDetachedDoubly(&c);
    try expectDoublyOrder(&list, &.{&b});

    list.insertBefore(&b, &a);
    list.insertAfter(&b, &c);
    list.insertAfter(&c, &d);
    list.clear();
    try expectDoublyOrder(&list, &.{});
    try expectDetachedDoubly(&a);
    try expectDetachedDoubly(&b);
    try expectDetachedDoubly(&c);
    try expectDetachedDoubly(&d);

    list.clear();
    list.pushFront(&a);
    try expectDoublyOrder(&list, &.{&a});
}

test "unit: intrusive lists preserve addresses and support distinct memberships" {
    var ready = Singly.init();
    var other_singly = SinglyOther.init();
    var all = Doubly.init();
    var other_doubly = DoublyOther.init();
    var a: Item = .{ .id = 1 };
    var b: Item = .{ .id = 2 };
    const a_address = &a;
    const b_address = &b;

    ready.pushBack(&a);
    ready.pushBack(&b);
    other_singly.pushBack(&b);
    other_singly.pushBack(&a);
    all.pushBack(&a);
    all.pushBack(&b);
    other_doubly.pushBack(&b);
    other_doubly.pushBack(&a);

    try testing.expectEqual(a_address, ready.front().?);
    try testing.expectEqual(b_address, ready.back().?);
    try testing.expectEqual(b_address, other_singly.front().?);
    try testing.expectEqual(a_address, other_singly.back().?);
    try testing.expectEqual(a_address, all.front().?);
    try testing.expectEqual(b_address, all.back().?);
    try testing.expectEqual(b_address, other_doubly.front().?);
    try testing.expectEqual(a_address, other_doubly.back().?);

    _ = ready.popFront();
    all.remove(&b);
    try expectDetachedSingly(&a);
    try expectDetachedDoubly(&b);
    try testing.expectEqual(a_address, other_singly.back().?);
    try testing.expectEqual(b_address, other_doubly.front().?);
}
