//! Intrusive FIFO queue. Spec: docs/specs/intrusive/queue.md.

const std = @import("std");

const List = @import("list.zig").List;

pub fn Queue(comptime T: type, comptime node_field: []const u8) type {
    return struct {
        head: ?*T = null,
        tail: ?*T = null,

        const Self = @This();
        const Node = List.SinglyLinkedNode;

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

        pub fn init() Self {
            return .{};
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.head == null;
        }

        pub fn front(self: *Self) ?*T {
            return self.head;
        }

        pub fn constFront(self: *const Self) ?*const T {
            return self.head;
        }

        pub fn back(self: *Self) ?*T {
            return self.tail;
        }

        pub fn constBack(self: *const Self) ?*const T {
            return self.tail;
        }

        pub fn pushBack(self: *Self, item: *T) void {
            assertDetached(item);
            if (self.tail) |tail_item| {
                node(tail_item).next = node(item);
                self.tail = item;
            } else {
                self.head = item;
                self.tail = item;
            }
        }

        pub fn popFront(self: *Self) ?*T {
            const item = self.head orelse return null;
            const item_node = node(item);
            self.head = if (item_node.next) |next_node| itemFromNode(next_node) else null;
            if (self.tail == item) self.tail = self.head;
            item_node.next = null;
            return item;
        }

        pub fn clear(self: *Self) void {
            var current = self.head;
            while (current) |item| {
                const item_node = node(item);
                current = if (item_node.next) |next_node| itemFromNode(next_node) else null;
                item_node.next = null;
            }
            self.head = null;
            self.tail = null;
        }

        pub fn assertValid(self: *const Self) void {
            std.debug.assert((self.head == null) == (self.tail == null));
            if (self.head == null) return;

            var slow: ?*const T = self.head;
            var fast: ?*const T = self.head;
            while (fast) |fast_item| {
                const next_fast = constNext(fast_item) orelse break;
                fast = constNext(next_fast);
                slow = if (slow) |slow_item| constNext(slow_item) else null;
                if (fast != null and slow != null and fast.? == slow.?) unreachable;
            }

            var current: ?*const T = self.head;
            var last: ?*const T = null;
            while (current) |item| {
                last = item;
                current = constNext(item);
            }
            std.debug.assert(last == self.tail);
            std.debug.assert(constNode(self.tail.?).next == null);
        }
    };
}
