//! Intrusive linked lists. Spec: docs/specs/intrusive/list.md.

const std = @import("std");

pub const List = struct {
    pub const SinglyLinkedNode = struct {
        next: ?*@This() = null,
    };

    pub const DoublyLinkedNode = struct {
        prev: ?*@This() = null,
        next: ?*@This() = null,
    };

    pub fn SinglyLinked(comptime T: type, comptime node_field: []const u8) type {
        return struct {
            head: ?*T = null,
            tail: ?*T = null,

            const Node = SinglyLinkedNode;
            const Self = @This();

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

            pub fn next(item: *T) ?*T {
                const next_node = node(item).next orelse return null;
                return itemFromNode(next_node);
            }

            pub fn constNext(item: *const T) ?*const T {
                const next_node = constNode(item).next orelse return null;
                return constItemFromNode(next_node);
            }

            /// `item`'s node must be detached; double insert is a programmer error.
            pub fn pushFront(self: *Self, item: *T) void {
                assertDetached(item);

                const item_node = node(item);
                item_node.next = if (self.head) |head_item| node(head_item) else null;
                self.head = item;
                if (self.tail == null) self.tail = item;
            }

            /// `item`'s node must be detached; double insert is a programmer error.
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

            /// `previous` must belong to this list; `item`'s node must be detached.
            pub fn insertAfter(self: *Self, previous: *T, item: *T) void {
                assertDetached(item);

                const previous_node = node(previous);
                const item_node = node(item);
                item_node.next = previous_node.next;
                previous_node.next = item_node;
                if (self.tail == previous) self.tail = item;
            }

            /// Returned node is detached before return.
            pub fn popFront(self: *Self) ?*T {
                const item = self.head orelse return null;

                const item_node = node(item);
                self.head = if (item_node.next) |next_node| itemFromNode(next_node) else null;
                if (self.tail == item) self.tail = self.head;
                item_node.next = null;
                return item;
            }

            /// Success detaches `item`; failure leaves the list unchanged.
            pub fn tryRemove(self: *Self, item: *T) bool {
                var previous: ?*T = null;
                var current = self.head;
                while (current) |current_item| {
                    const current_node = node(current_item);
                    if (current_item == item) {
                        if (previous) |previous_item| {
                            node(previous_item).next = current_node.next;
                        } else {
                            self.head = if (current_node.next) |next_node| itemFromNode(next_node) else null;
                        }
                        if (self.tail == item) self.tail = previous;
                        current_node.next = null;
                        return true;
                    }
                    previous = current_item;
                    current = if (current_node.next) |next_node| itemFromNode(next_node) else null;
                }

                return false;
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

            /// Checks endpoint symmetry, tail reachability, terminal null, and absence of a head cycle.
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

            fn assertDetached(item: *T) void {
                std.debug.assert(node(item).next == null);
            }
        };
    }

    pub fn DoublyLinked(comptime T: type, comptime node_field: []const u8) type {
        return struct {
            head: ?*T = null,
            tail: ?*T = null,

            const Node = DoublyLinkedNode;
            const Self = @This();

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

            pub fn next(item: *T) ?*T {
                const next_node = node(item).next orelse return null;
                return itemFromNode(next_node);
            }

            pub fn constNext(item: *const T) ?*const T {
                const next_node = constNode(item).next orelse return null;
                return constItemFromNode(next_node);
            }

            pub fn previous(item: *T) ?*T {
                const previous_node = node(item).prev orelse return null;
                return itemFromNode(previous_node);
            }

            pub fn constPrevious(item: *const T) ?*const T {
                const previous_node = constNode(item).prev orelse return null;
                return constItemFromNode(previous_node);
            }

            /// `item`'s node must be detached; double insert is a programmer error.
            pub fn pushFront(self: *Self, item: *T) void {
                assertDetached(item);

                const item_node = node(item);
                if (self.head) |head_item| {
                    item_node.next = node(head_item);
                    node(head_item).prev = item_node;
                    self.head = item;
                } else {
                    self.head = item;
                    self.tail = item;
                }
            }

            /// `item`'s node must be detached; double insert is a programmer error.
            pub fn pushBack(self: *Self, item: *T) void {
                assertDetached(item);

                const item_node = node(item);
                if (self.tail) |tail_item| {
                    item_node.prev = node(tail_item);
                    node(tail_item).next = item_node;
                    self.tail = item;
                } else {
                    self.head = item;
                    self.tail = item;
                }
            }

            /// `next_item` must belong to this list; `item`'s node must be detached.
            pub fn insertBefore(self: *Self, next_item: *T, item: *T) void {
                assertDetached(item);

                const next_node = node(next_item);
                const item_node = node(item);
                item_node.prev = next_node.prev;
                item_node.next = next_node;

                if (next_node.prev) |previous_node| {
                    previous_node.next = item_node;
                } else {
                    self.head = item;
                }

                next_node.prev = item_node;
            }

            /// `previous_item` must belong to this list; `item`'s node must be detached.
            pub fn insertAfter(self: *Self, previous_item: *T, item: *T) void {
                assertDetached(item);

                const previous_node = node(previous_item);
                const item_node = node(item);
                item_node.prev = previous_node;
                item_node.next = previous_node.next;

                if (previous_node.next) |next_node| {
                    next_node.prev = item_node;
                } else {
                    self.tail = item;
                }

                previous_node.next = item_node;
            }

            /// Returned node is detached before return.
            pub fn popFront(self: *Self) ?*T {
                const item = self.head orelse return null;
                self.remove(item);
                return item;
            }

            /// Returned node is detached before return.
            pub fn popBack(self: *Self) ?*T {
                const item = self.tail orelse return null;
                self.remove(item);
                return item;
            }

            /// `item` must belong to this list; success detaches it before return.
            pub fn remove(self: *Self, item: *T) void {
                self.assertAttached(item);
                const item_node = node(item);

                if (item_node.prev) |previous_node| {
                    previous_node.next = item_node.next;
                } else {
                    self.head = if (item_node.next) |next_node| itemFromNode(next_node) else null;
                }

                if (item_node.next) |next_node| {
                    next_node.prev = item_node.prev;
                } else {
                    self.tail = if (item_node.prev) |previous_node| itemFromNode(previous_node) else null;
                }

                item_node.prev = null;
                item_node.next = null;
            }

            /// Detaches every node; parent objects are not moved, freed, or zeroed.
            pub fn clear(self: *Self) void {
                var current = self.head;
                while (current) |item| {
                    const item_node = node(item);
                    current = if (item_node.next) |next_node| itemFromNode(next_node) else null;
                    item_node.prev = null;
                    item_node.next = null;
                }
                self.head = null;
                self.tail = null;
            }

            /// Checks endpoint and link symmetry plus absence of a head cycle.
            pub fn assertValid(self: *const Self) void {
                if (self.head == null) {
                    std.debug.assert(self.tail == null);
                } else {
                    std.debug.assert(self.tail != null);
                }
                if (self.head == null) return;

                std.debug.assert(constNode(self.head.?).prev == null);
                std.debug.assert(constNode(self.tail.?).next == null);

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
                    if (constNext(item)) |next_item| {
                        std.debug.assert(constPrevious(next_item) == item);
                    }
                    last = item;
                    current = constNext(item);
                }
                std.debug.assert(last == self.tail);

                current = self.tail;
                last = null;
                while (current) |item| {
                    if (constPrevious(item)) |previous_item| {
                        std.debug.assert(constNext(previous_item) == item);
                    }
                    last = item;
                    current = constPrevious(item);
                }
                std.debug.assert(last == self.head);
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

            fn assertDetached(item: *T) void {
                const item_node = node(item);
                std.debug.assert(item_node.prev == null);
                std.debug.assert(item_node.next == null);
            }

            fn assertAttached(self: *const Self, item: *T) void {
                const item_node = node(item);
                std.debug.assert(item_node.prev != null or item_node.next != null or self.head == item);
            }
        };
    }
};
