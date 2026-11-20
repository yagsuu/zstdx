//! Intrusive binary heap. See `docs/specs/intrusive/heap.md`.

const std = @import("std");

const debug = @import("core").debug;

pub fn Heap(
    comptime T: type,
    comptime field: []const u8,
    comptime less: fn (lhs: *const T, rhs: *const T) bool,
) type {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            if (info.layout == .@"packed") @compileError("Heap requires an addressable Node field");
        },
        else => @compileError("Heap requires a struct with a Node field"),
    }

    if (!@hasField(T, field)) @compileError("Heap node field does not exist");
    if (@FieldType(T, field) != Node) @compileError("Heap node field must have type intrusive.heap.Node");

    return struct {
        root: ?*Node = null,
        count: usize = 0,

        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        pub fn len(self: *const Self) usize {
            return self.count;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.count == 0;
        }

        pub fn peek(self: *const Self) ?*const T {
            const node = self.root orelse return null;
            return @as(*const T, @fieldParentPtr(field, node));
        }

        pub fn peekMut(self: *Self) ?*T {
            const node = self.root orelse return null;
            return @as(*T, @fieldParentPtr(field, node));
        }

        pub fn insert(self: *Self, item: *T) void {
            const node = &@field(item.*, field);

            if (comptime debug.checksEnabled()) {
                std.debug.assert(!node.linked);
                std.debug.assert(node.parent == null and node.left == null and node.right == null);
            }

            if (self.root == null) {
                std.debug.assert(self.count == 0);
                self.root = node;
                self.count = 1;
                node.linked = true;
                return;
            }

            const index = self.count + 1;
            const parent = self.nodeAt(index / 2);
            const link = if (index % 2 == 0) &parent.left else &parent.right;
            std.debug.assert(link.* == null);

            link.* = node;
            node.parent = parent;
            node.linked = true;
            self.count = index;

            _ = self.siftUp(node);

            std.debug.assert(self.root.?.parent == null);
        }

        pub fn pop(self: *Self) ?*T {
            const node = self.root orelse return null;
            std.debug.assert(self.count != 0);
            std.debug.assert(node.parent == null);

            const item: *T = @fieldParentPtr(field, node);
            self.removeNode(node);
            return item;
        }

        pub fn remove(self: *Self, item: *T) void {
            const node = &@field(item.*, field);
            if (comptime debug.checksEnabled()) self.assertMember(node);
            self.removeNode(node);
        }

        pub fn update(self: *Self, item: *T) void {
            const node = &@field(item.*, field);
            if (comptime debug.checksEnabled()) self.assertMember(node);
            if (!self.siftUp(node)) self.siftDown(node);
        }

        pub fn clear(self: *Self) void {
            std.debug.assert((self.root == null) == (self.count == 0));

            if (self.root) |root| {
                std.debug.assert(root.parent == null);
            }

            var current = self.root;
            while (current) |node| {
                if (node.left) |left| {
                    node.left = null;
                    current = left;
                    continue;
                }

                if (node.right) |right| {
                    node.right = null;
                    current = right;
                    continue;
                }

                current = node.parent;
                node.* = .{};
            }

            self.root = null;
            self.count = 0;
        }

        pub fn assertValid(self: *const Self) void {
            std.debug.assert((self.root == null) == (self.count == 0));

            const root = self.root orelse return;
            std.debug.assert(root.parent == null);

            var current: *const Node = root;
            var previous: ?*const Node = null;
            var index: usize = 1;
            var visited: usize = 0;

            while (true) {
                const entering = previous == current.parent;
                if (entering) {
                    std.debug.assert(visited < self.count);
                    visited += 1;
                    self.assertNode(current, index);
                }

                const next_left = if (entering) current.left else null;
                if (next_left) |left| {
                    previous = current;
                    current = left;
                    index *= 2;
                    continue;
                }

                const returning_from_left = previous == current.left;
                const next_right = if (entering or returning_from_left) current.right else null;
                if (next_right) |right| {
                    previous = current;
                    current = right;
                    index = index * 2 + 1;
                    continue;
                }

                std.debug.assert(entering or returning_from_left or previous == current.right);

                const parent = current.parent orelse break;
                previous = current;
                current = parent;
                index /= 2;
            }

            std.debug.assert(visited == self.count);
        }

        fn removeNode(self: *Self, node: *Node) void {
            std.debug.assert(node.linked);
            std.debug.assert(self.count != 0);

            const last = self.nodeAt(self.count);
            self.linkTo(last).* = null;
            self.count -= 1;

            if (last == node) {
                node.* = .{};
                return;
            }

            const new_root = node == self.root;
            node.replaceWith(last);

            if (new_root) {
                self.root = last;
            }

            if (!self.siftUp(last)) {
                self.siftDown(last);
            }
        }

        fn siftUp(self: *Self, node: *Node) bool {
            std.debug.assert(node.linked);
            std.debug.assert(self.count != 0);

            var moved = false;
            while (node.parent) |parent| {
                if (!less(@fieldParentPtr(field, node), @fieldParentPtr(field, parent))) break;
                self.swapWithParent(node);
                moved = true;
            }

            return moved;
        }

        fn siftDown(self: *Self, node: *Node) void {
            std.debug.assert(node.linked);
            std.debug.assert(self.count != 0);

            while (node.left) |left| {
                var child = left;
                if (node.right) |right| {
                    if (less(@fieldParentPtr(field, right), @fieldParentPtr(field, left))) {
                        child = right;
                    }
                }

                if (!less(@fieldParentPtr(field, child), @fieldParentPtr(field, node))) {
                    break;
                }

                self.swapWithParent(child);
            }
        }

        fn swapWithParent(self: *Self, child: *Node) void {
            const replaces_root = child.parent == self.root;
            child.swapWithParent();
            if (replaces_root) self.root = child;
        }

        fn nodeAt(self: *const Self, index: usize) *Node {
            std.debug.assert(index >= 1 and index <= self.count);
            std.debug.assert(self.root != null);

            var current = self.root.?;
            var bit = @as(usize, 1) << @intCast(std.math.log2_int(usize, index));

            bit >>= 1;

            while (bit != 0) : (bit >>= 1) {
                current = if (index & bit == 0) current.left.? else current.right.?;
            }

            return current;
        }

        fn linkTo(self: *Self, node: *Node) *?*Node {
            std.debug.assert(node.linked);

            const parent = node.parent orelse {
                std.debug.assert(self.root == node);
                return &self.root;
            };

            if (parent.left == node) {
                return &parent.left;
            }

            std.debug.assert(parent.right == node);
            return &parent.right;
        }

        fn assertNode(self: *const Self, node: *const Node, index: usize) void {
            std.debug.assert(index >= 1 and index <= self.count);
            std.debug.assert(node.linked);

            const left_expected = index <= self.count / 2;
            const right_expected = index <= (self.count - 1) / 2;
            std.debug.assert((node.left != null) == left_expected);
            std.debug.assert((node.right != null) == right_expected);

            if (node.left) |left| {
                std.debug.assert(left.parent == node);
                std.debug.assert(!less(@fieldParentPtr(field, left), @fieldParentPtr(field, node)));
                std.debug.assert(node.right != left);
            }

            if (node.right) |right| {
                std.debug.assert(right.parent == node);
                std.debug.assert(!less(@fieldParentPtr(field, right), @fieldParentPtr(field, node)));
            }
        }

        fn assertMember(self: *const Self, node: *const Node) void {
            std.debug.assert(node.linked);
            std.debug.assert(self.count != 0);

            var current = node;
            var remaining = std.math.log2_int(usize, self.count);
            while (current.parent) |parent| {
                std.debug.assert(remaining != 0);
                remaining -= 1;
                std.debug.assert(parent.left == current or parent.right == current);
                current = parent;
            }

            std.debug.assert(current == self.root);
        }
    };
}

pub const Node = struct {
    parent: ?*Node = null,
    left: ?*Node = null,
    right: ?*Node = null,
    linked: bool = false,

    /// `replacement` must be a leaf already unlinked from its previous position.
    fn replaceWith(self: *Node, replacement: *Node) void {
        std.debug.assert(self != replacement);
        std.debug.assert(self.linked and replacement.linked);
        std.debug.assert(replacement.left == null and replacement.right == null);

        if (self.parent) |parent| {
            if (parent.left == self) {
                parent.left = replacement;
            } else {
                std.debug.assert(parent.right == self);
                parent.right = replacement;
            }
        }

        replacement.parent = self.parent;
        replacement.left = self.left;
        replacement.right = self.right;

        if (replacement.left) |left| {
            left.parent = replacement;
        }

        if (replacement.right) |right| {
            right.parent = replacement;
        }

        self.* = .{};
    }

    fn swapWithParent(self: *Node) void {
        const parent = self.parent.?;
        std.debug.assert(parent.left == self or parent.right == self);
        std.debug.assert(self.linked and parent.linked);

        const grandparent = parent.parent;
        const was_left = parent.left == self;
        const sibling = if (was_left) parent.right else parent.left;
        const child_left = self.left;
        const child_right = self.right;

        if (grandparent) |node| {
            if (node.left == parent) {
                node.left = self;
            } else {
                std.debug.assert(node.right == parent);
                node.right = self;
            }
        }

        self.parent = grandparent;

        if (was_left) {
            self.left = parent;
            self.right = sibling;
        } else {
            self.left = sibling;
            self.right = parent;
        }

        if (sibling) |node| {
            node.parent = self;
        }

        parent.parent = self;
        parent.left = child_left;
        parent.right = child_right;

        if (child_left) |node| {
            node.parent = parent;
        }
        if (child_right) |node| {
            node.parent = parent;
        }
    }
};

pub const unit = struct {
    const testing = std.testing;

    const Item = struct {
        id: usize = 0,
        priority: i32,
        node: Node = .{},
        other_node: Node = .{},

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

    const Items = Heap(Item, "node", Item.less);
    const OtherItems = Heap(Item, "other_node", Item.less);
    const MaxItems = Heap(Item, "other_node", Item.greater);

    test "intrusive heap detaches nodes across singleton transitions" {
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

    test "intrusive heap preserves objects through updates and replacement" {
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
        var reference: [storage.len]ReferenceItem = @splat(.{});
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

    fn expectDetached(node: *const Node) !void {
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
};
