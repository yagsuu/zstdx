//! Intrusive linked lists.

const std = @import("std");

pub const List = struct {
    pub const SinglyLinkedNode = std.SinglyLinkedList.Node;
    pub const DoublyLinkedNode = std.DoublyLinkedList.Node;

    pub fn SinglyLinked(comptime T: type, comptime field: []const u8) type {
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

            /// `item`'s node must be detached. Inserting an attached node is a programmer error.
            pub fn pushFront(self: *Self, item: *T) void {
                assertDetached(item);

                const item_node = node(item);
                item_node.next = if (self.head) |head_item| node(head_item) else null;

                self.head = item;

                if (self.tail == null) self.tail = item;
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

            /// `previous` must belong to this list; `item`'s node must be detached.
            pub fn insertAfter(self: *Self, previous: *T, item: *T) void {
                assertDetached(item);

                const previous_node = node(previous);
                const item_node = node(item);

                item_node.next = previous_node.next;
                previous_node.next = item_node;

                if (self.tail == previous) self.tail = item;
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

            /// A successful removal detaches `item`; a failed removal leaves the list unchanged.
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
                return &@field(item.*, field);
            }

            fn constNode(item: *const T) *const Node {
                return &@field(item.*, field);
            }

            fn itemFromNode(item_node: *Node) *T {
                return @fieldParentPtr(field, item_node);
            }

            fn constItemFromNode(item_node: *const Node) *const T {
                return @fieldParentPtr(field, item_node);
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

            /// `item`'s node must be detached. Inserting an attached node is a programmer error.
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

            /// `item`'s node must be detached. Inserting an attached node is a programmer error.
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

            /// A non-null return has its selected node detached.
            pub fn popFront(self: *Self) ?*T {
                const item = self.head orelse return null;
                self.remove(item);
                return item;
            }

            /// A non-null return has its selected node detached.
            pub fn popBack(self: *Self) ?*T {
                const item = self.tail orelse return null;
                self.remove(item);
                return item;
            }

            /// Requirements: `item` belongs to this list.
            /// Effects: Detaches `item`'s node before return.
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

            /// Invariant: Endpoint and link symmetry, and no cycle reachable from `head`.
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

pub const unit = struct {
    const testing = std.testing;

    const Item = struct {
        id: u32,
        singly: List.SinglyLinkedNode = .{},
        singly_other: List.SinglyLinkedNode = .{},
        doubly: List.DoublyLinkedNode = .{},
        doubly_other: List.DoublyLinkedNode = .{},
    };

    const Singly = List.SinglyLinked(Item, "singly");
    const SinglyOther = List.SinglyLinked(Item, "singly_other");
    const Doubly = List.DoublyLinked(Item, "doubly");
    const DoublyOther = List.DoublyLinked(Item, "doubly_other");

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
        try testing.expectEqual(@as(?*List.SinglyLinkedNode, null), item.singly.next);
    }

    fn expectDetachedDoubly(item: *const Item) !void {
        try testing.expectEqual(@as(?*List.DoublyLinkedNode, null), item.doubly.prev);
        try testing.expectEqual(@as(?*List.DoublyLinkedNode, null), item.doubly.next);
    }

    test "intrusive singly insertion traversal removal and reinsertion" {
        var list = Singly.init();
        var default_list: Singly = .{};

        try testing.expect(default_list.isEmpty());
        try testing.expect(list.isEmpty());
        try testing.expectEqual(@as(?*const Item, null), list.constFront());
        try testing.expectEqual(@as(?*const Item, null), list.constBack());
        try expectSinglyOrder(&list, &.{});

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

    test "intrusive singly pushBack empty insertAfter tail and clear detach" {
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

    test "intrusive doubly insertion traversal removal and reinsertion" {
        var list = Doubly.init();
        var default_list: Doubly = .{};

        try testing.expect(default_list.isEmpty());
        try testing.expect(list.isEmpty());
        try testing.expectEqual(@as(?*const Item, null), list.constFront());
        try testing.expectEqual(@as(?*const Item, null), list.constBack());
        try expectDoublyOrder(&list, &.{});

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

    test "intrusive doubly pops and clear detach nodes" {
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

    test "intrusive lists preserve addresses and support distinct memberships" {
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
};
