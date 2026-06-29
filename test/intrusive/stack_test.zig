//! Intrusive Stack contract tests. Spec: docs/specs/intrusive/stack.md.

const std = @import("std");

const stdx = @import("stdx");
const List = stdx.intrusive.List;
const Stack = stdx.intrusive.Stack;
const testing = std.testing;

const Item = struct {
    id: u32,
    node: List.SinglyLinkedNode = .{},
    other_node: List.SinglyLinkedNode = .{},
};

const Items = Stack(Item, "node");
const OtherItems = Stack(Item, "other_node");

fn expectDetached(item: *const Item) !void {
    try testing.expectEqual(@as(?*List.SinglyLinkedNode, null), item.node.next);
}

test "unit: intrusive stack construction and empty access" {
    var stack = Items.init();
    var default_stack: Items = .{};

    try testing.expect(stack.isEmpty());
    try testing.expect(default_stack.isEmpty());
    try testing.expectEqual(@as(?*Item, null), stack.peek());
    try testing.expectEqual(@as(?*const Item, null), stack.constPeek());
    try testing.expectEqual(@as(?*Item, null), stack.pop());
}

test "unit: intrusive stack preserves LIFO order" {
    var stack = Items.init();
    var a: Item = .{ .id = 1 };
    var b: Item = .{ .id = 2 };
    var c: Item = .{ .id = 3 };

    stack.push(&a);
    try testing.expectEqual(&a, stack.peek().?);
    try testing.expectEqual(@as(?*const Item, &a), stack.constPeek());
    stack.push(&b);
    stack.push(&c);
    try testing.expectEqual(&c, stack.peek().?);

    try testing.expectEqual(&c, stack.pop().?);
    try expectDetached(&c);
    try testing.expectEqual(&b, stack.peek().?);
    try testing.expectEqual(&b, stack.pop().?);
    try expectDetached(&b);
    try testing.expectEqual(&a, stack.pop().?);
    try expectDetached(&a);
    try testing.expect(stack.isEmpty());
    try testing.expectEqual(@as(?*Item, null), stack.pop());
}

test "unit: intrusive stack clear detaches and permits reinsertion" {
    var stack = Items.init();
    var a: Item = .{ .id = 1 };
    var b: Item = .{ .id = 2 };
    var c: Item = .{ .id = 3 };

    stack.clear();
    stack.push(&a);
    stack.clear();
    try testing.expect(stack.isEmpty());
    try expectDetached(&a);

    stack.push(&a);
    stack.push(&b);
    stack.push(&c);
    stack.clear();
    try testing.expect(stack.isEmpty());
    try expectDetached(&a);
    try expectDetached(&b);
    try expectDetached(&c);

    stack.push(&a);
    stack.push(&b);
    try testing.expectEqual(&b, stack.pop().?);
    try testing.expectEqual(&a, stack.pop().?);
    try testing.expect(stack.isEmpty());
}

test "unit: intrusive stack uses singly nodes and supports distinct memberships" {
    var ready = Items.init();
    var free = OtherItems.init();
    var a: Item = .{ .id = 1 };
    var b: Item = .{ .id = 2 };
    const a_address = &a;
    const b_address = &b;

    ready.push(&a);
    ready.push(&b);
    free.push(&b);
    free.push(&a);

    try testing.expectEqual(b_address, ready.peek().?);
    try testing.expectEqual(a_address, free.peek().?);
    try testing.expectEqual(b_address, ready.pop().?);
    try expectDetached(&b);
    try testing.expectEqual(a_address, ready.peek().?);
    try testing.expectEqual(a_address, free.pop().?);
    try testing.expectEqual(b_address, free.peek().?);
    ready.assertValid();
    free.assertValid();
}
