//! Intrusive LIFO stack.

const std = @import("std");

const List = @import("list.zig").List;

pub fn Stack(comptime T: type, comptime node_field: []const u8) type {
    return struct {
        top: ?*T = null,

        const Node = List.SinglyLinkedNode;
        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.top == null;
        }

        /// Returns a borrowed pointer to the top object.
        pub fn peek(self: *Self) ?*T {
            return self.top;
        }

        pub fn constPeek(self: *const Self) ?*const T {
            return self.top;
        }

        /// `item`'s node must be detached. Inserting an attached node is a programmer error.
        pub fn push(self: *Self, item: *T) void {
            assertDetached(item);

            node(item).next = if (self.top) |top_item| node(top_item) else null;
            self.top = item;
        }

        /// A non-null return has its selected node detached.
        pub fn pop(self: *Self) ?*T {
            const item = self.top orelse return null;
            const item_node = node(item);

            self.top = if (item_node.next) |next_node| itemFromNode(next_node) else null;
            item_node.next = null;
            return item;
        }

        /// Detaches every node; parent objects are not moved, freed, or zeroed.
        pub fn clear(self: *Self) void {
            var current = self.top;
            while (current) |item| {
                const item_node = node(item);
                current = if (item_node.next) |next_node| itemFromNode(next_node) else null;
                item_node.next = null;
            }
            self.top = null;
        }

        /// Invariant: no cycle is reachable from `top`.
        pub fn assertValid(self: *const Self) void {
            var slow: ?*const T = self.top;
            var fast: ?*const T = self.top;
            while (fast) |fast_item| {
                const next_fast = constNext(fast_item) orelse break;
                fast = constNext(next_fast);
                slow = if (slow) |slow_item| constNext(slow_item) else null;

                if (fast) |f| if (slow) |s| {
                    if (f == s) unreachable;
                };
            }
        }

        fn node(item: *T) *Node {
            return &@field(item.*, node_field);
        }

        fn constNode(item: *const T) *const Node {
            return &@field(item.*, node_field);
        }

        fn itemFromNode(item_node: *Node) *T {
            return @fieldParentPtr(node_field, item_node);
        }

        fn constItemFromNode(item_node: *const Node) *const T {
            return @fieldParentPtr(node_field, item_node);
        }

        fn next(item: *T) ?*T {
            const next_node = node(item).next orelse return null;
            return itemFromNode(next_node);
        }

        fn constNext(item: *const T) ?*const T {
            const next_node = constNode(item).next orelse return null;
            return constItemFromNode(next_node);
        }

        fn assertDetached(item: *T) void {
            std.debug.assert(node(item).next == null);
        }
    };
}

pub const unit = struct {
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

    test "intrusive stack preserves LIFO order" {
        var stack = Items.init();
        var default_stack: Items = .{};

        try testing.expect(stack.isEmpty());
        try testing.expect(default_stack.isEmpty());
        try testing.expectEqual(@as(?*Item, null), stack.peek());
        try testing.expectEqual(@as(?*const Item, null), stack.constPeek());
        try testing.expectEqual(@as(?*Item, null), stack.pop());

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

    test "intrusive stack clear detaches and permits reinsertion" {
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

    test "intrusive stack uses singly nodes and supports distinct memberships" {
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
};
