//! Intrusive LIFO stack. Spec: docs/specs/intrusive/stack.md.

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

        pub fn peek(self: *Self) ?*T {
            return self.top;
        }

        pub fn constPeek(self: *const Self) ?*const T {
            return self.top;
        }

        pub fn push(self: *Self, item: *T) void {
            assertDetached(item);

            node(item).next = if (self.top) |top_item| node(top_item) else null;
            self.top = item;
        }

        pub fn pop(self: *Self) ?*T {
            const item = self.top orelse return null;

            const item_node = node(item);
            self.top = if (item_node.next) |next_node| itemFromNode(next_node) else null;
            item_node.next = null;
            return item;
        }

        pub fn clear(self: *Self) void {
            var current = self.top;
            while (current) |item| {
                const item_node = node(item);
                current = if (item_node.next) |next_node| itemFromNode(next_node) else null;
                item_node.next = null;
            }
            self.top = null;
        }

        pub fn assertValid(self: *const Self) void {
            var slow: ?*const T = self.top;
            var fast: ?*const T = self.top;
            while (fast) |fast_item| {
                const next_fast = constNext(fast_item) orelse break;
                fast = constNext(next_fast);
                slow = if (slow) |slow_item| constNext(slow_item) else null;
                if (fast != null and slow != null and fast.? == slow.?) unreachable;
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
