//! Intrusive FIFO queue. See `docs/specs/intrusive/queue.md`.

const std = @import("std");

const List = @import("list.zig").List;

pub fn Queue(comptime T: type, comptime node_field: []const u8) type {
    return struct {
        head: ?*T = null,
        tail: ?*T = null,

        const Node = List.SinglyLinkedNode;
        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.head == null;
        }

        /// Returns a borrowed pointer to the oldest queued object.
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

        /// `item`'s node must be detached. Inserting an attached node is a programmer error.
        pub fn pushBack(self: *Self, item: *T) void {
            assertDetached(item);

            if (self.tail) |tail_item| {
                node(tail_item).next = node(item);
                self.tail = item;
                return;
            }

            self.head = item;
            self.tail = item;
        }

        /// A non-null return has its selected node detached.
        pub fn popFront(self: *Self) ?*T {
            const item = self.head orelse return null;

            const item_node = node(item);
            self.head = if (item_node.next) |next_node| itemFromNode(next_node) else null;

            if (self.tail == item) self.tail = self.head;

            item_node.next = null;
            return item;
        }

        /// Detaches every node; parent objects are not moved, freed, or zeroed.
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

        /// Invariant: Endpoint symmetry, tail reachability, a null terminal link, and no cycle reachable from `head`.
        pub fn assertValid(self: *const Self) void {
            if (self.head == null) {
                std.debug.assert(self.tail == null);
            } else {
                std.debug.assert(self.tail != null);
            }

            if (self.head == null) return;

            var slow: ?*const T = self.head;
            var fast: ?*const T = self.head;
            while (fast) |fast_item| {
                const next_fast = constNext(fast_item) orelse break;
                fast = constNext(next_fast);
                slow = if (slow) |slow_item| constNext(slow_item) else null;
                if (fast) |f| if (slow) |s| if (f == s) unreachable;
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
