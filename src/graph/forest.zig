//! Forest topology for dense node IDs and embedded linked nodes.
//! See `docs/specs/graph/forest.md`.

const std = @import("std");

pub const Forest = struct {
    pub fn Static(comptime capacity_nodes: usize) type {
        comptime {
            if (capacity_nodes == 0) {
                @compileError("Forest.Static capacity_nodes must be non-zero");
            }
        }

        return struct {
            roots: SiblingList = .{},
            links: [capacity_nodes]Links = @splat(.{}),

            pub const NodeID = enum(usize) { _ };

            pub const SiblingList = struct {
                head: ?NodeID = null,
                tail: ?NodeID = null,
            };

            pub const Links = struct {
                parent: ?NodeID = null,
                children: SiblingList = .{},
                sibling: ?NodeID = null,
            };

            pub const BoundsError = error{OutOfBounds};
            pub const AppendError = error{ OutOfBounds, AlreadyLinked };
            pub const RemoveError = error{ OutOfBounds, NotLinked };
            pub const Error = BoundsError || AppendError || RemoveError;

            const Self = @This();

            pub fn init() Self {
                return .{};
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return capacity_nodes;
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.roots.head == null;
            }

            pub fn nodeId(self: *const Self, index: usize) BoundsError!NodeID {
                if (index >= self.links.len) {
                    return error.OutOfBounds;
                }
                return @enumFromInt(index);
            }

            pub fn indexOf(node: NodeID) usize {
                return @intFromEnum(node);
            }

            pub fn firstRoot(self: *const Self) ?NodeID {
                return self.roots.head;
            }

            pub fn lastRoot(self: *const Self) ?NodeID {
                return self.roots.tail;
            }

            pub fn appendRoot(self: *Self, item: NodeID) AppendError!void {
                return Impl.appendRoot(Self, self, item);
            }

            pub fn appendChild(self: *Self, parent_item: NodeID, child_item: NodeID) AppendError!void {
                return Impl.appendChild(Self, self, parent_item, child_item);
            }

            pub fn remove(self: *Self, item: NodeID) RemoveError!void {
                return Impl.remove(Self, self, item);
            }

            pub fn parent(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try Impl.link(Self, self, item)).parent;
            }

            pub fn firstChild(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try Impl.link(Self, self, item)).children.head;
            }

            pub fn lastChild(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try Impl.link(Self, self, item)).children.tail;
            }

            pub fn nextSibling(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try Impl.link(Self, self, item)).sibling;
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.roots = .{};
                @memset(&self.links, .{});
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertValid(Self, self);
            }
        };
    }

    pub fn Bounded() type {
        return struct {
            roots: SiblingList = .{},
            links: []Links,

            pub const NodeID = enum(usize) { _ };
            pub const SiblingList = struct {
                head: ?NodeID = null,
                tail: ?NodeID = null,
            };

            pub const Links = struct {
                parent: ?NodeID = null,
                children: SiblingList = .{},
                sibling: ?NodeID = null,
            };

            pub const BoundsError = error{OutOfBounds};
            pub const AppendError = error{ OutOfBounds, AlreadyLinked };
            pub const RemoveError = error{ OutOfBounds, NotLinked };
            pub const Error = BoundsError || AppendError || RemoveError;

            const Self = @This();

            pub fn wrap(links: []Links) Self {
                @memset(links, .{});
                return .{ .links = links };
            }

            pub fn capacity(self: *const Self) usize {
                return self.links.len;
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.roots.head == null;
            }

            pub fn nodeId(self: *const Self, index: usize) BoundsError!NodeID {
                if (index >= self.links.len) {
                    return error.OutOfBounds;
                }
                return @enumFromInt(index);
            }

            pub fn indexOf(node: NodeID) usize {
                return @intFromEnum(node);
            }

            pub fn firstRoot(self: *const Self) ?NodeID {
                return self.roots.head;
            }

            pub fn lastRoot(self: *const Self) ?NodeID {
                return self.roots.tail;
            }

            pub fn appendRoot(self: *Self, item: NodeID) AppendError!void {
                return Impl.appendRoot(Self, self, item);
            }

            pub fn appendChild(self: *Self, parent_item: NodeID, child_item: NodeID) AppendError!void {
                return Impl.appendChild(Self, self, parent_item, child_item);
            }

            pub fn remove(self: *Self, item: NodeID) RemoveError!void {
                return Impl.remove(Self, self, item);
            }

            pub fn parent(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try Impl.link(Self, self, item)).parent;
            }

            pub fn firstChild(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try Impl.link(Self, self, item)).children.head;
            }

            pub fn lastChild(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try Impl.link(Self, self, item)).children.tail;
            }

            pub fn nextSibling(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try Impl.link(Self, self, item)).sibling;
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.roots = .{};
                @memset(self.links, .{});
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertValid(Self, self);
            }
        };
    }

    pub const LinkedNode = struct {
        parent: ?*LinkedNode = null,
        children: ChildList = .{},
        next_sibling: ?*LinkedNode = null,

        pub const ChildList = struct {
            head: ?*LinkedNode = null,
            tail: ?*LinkedNode = null,
        };
    };

    pub fn Linked(comptime T: type, comptime field: []const u8) type {
        return struct {
            roots: RootList = .{},

            pub const Node = LinkedNode;
            pub const RootList = struct {
                head: ?*T = null,
                tail: ?*T = null,
            };

            const Self = @This();

            pub fn init() Self {
                return .{};
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.roots.head == null;
            }

            pub fn firstRoot(self: *const Self) ?*const T {
                return self.roots.head;
            }

            pub fn firstRootMut(self: *Self) ?*T {
                return self.roots.head;
            }

            pub fn lastRoot(self: *const Self) ?*const T {
                return self.roots.tail;
            }

            pub fn lastRootMut(self: *Self) ?*T {
                return self.roots.tail;
            }

            /// Item must be detached from any root or child list.
            pub fn appendRoot(self: *Self, item: *T) void {
                assertDetached(item);

                if (self.roots.tail) |tail| {
                    std.debug.assert(tail != item);
                    @field(tail.*, field).next_sibling = &@field(item.*, field);
                } else {
                    self.roots.head = item;
                }
                self.roots.tail = item;
            }

            /// Child must be detached and distinct from parent.
            pub fn appendChild(parent_item: *T, child_item: *T) void {
                std.debug.assert(parent_item != child_item);
                assertDetached(child_item);

                const parent_node = &@field(parent_item.*, field);
                const child_node = &@field(child_item.*, field);
                if (parent_node.children.tail) |tail| {
                    std.debug.assert(tail != child_node);
                    tail.next_sibling = child_node;
                } else {
                    parent_node.children.head = child_node;
                }
                parent_node.children.tail = child_node;
                child_node.parent = parent_node;
            }

            /// Item must be linked here. Descendants stay attached; removal scans siblings.
            pub fn remove(self: *Self, item: *T) void {
                const node = &@field(item.*, field);
                if (node.parent) |parent_node| {
                    removeFromNodeList(&parent_node.children, node);
                } else {
                    removeFromRootList(&self.roots, item, node);
                }
                node.parent = null;
                node.next_sibling = null;
            }

            pub fn parent(item: *const T) ?*const T {
                const node = @field(item.*, field).parent orelse return null;
                return @as(*const T, @fieldParentPtr(field, node));
            }

            pub fn parentMut(item: *T) ?*T {
                const node = @field(item.*, field).parent orelse return null;
                return @as(*T, @fieldParentPtr(field, node));
            }

            pub fn firstChild(item: *const T) ?*const T {
                const node = @field(item.*, field).children.head orelse return null;
                return @as(*const T, @fieldParentPtr(field, node));
            }

            pub fn firstChildMut(item: *T) ?*T {
                const node = @field(item.*, field).children.head orelse return null;
                return @as(*T, @fieldParentPtr(field, node));
            }

            pub fn lastChild(item: *const T) ?*const T {
                const node = @field(item.*, field).children.tail orelse return null;
                return @as(*const T, @fieldParentPtr(field, node));
            }

            pub fn lastChildMut(item: *T) ?*T {
                const node = @field(item.*, field).children.tail orelse return null;
                return @as(*T, @fieldParentPtr(field, node));
            }

            pub fn nextSibling(item: *const T) ?*const T {
                const node = @field(item.*, field).next_sibling orelse return null;
                return @as(*const T, @fieldParentPtr(field, node));
            }

            pub fn nextSiblingMut(item: *T) ?*T {
                const node = @field(item.*, field).next_sibling orelse return null;
                return @as(*T, @fieldParentPtr(field, node));
            }

            fn removeFromNodeList(list: *LinkedNode.ChildList, item: *LinkedNode) void {
                var previous: ?*LinkedNode = null;
                var current = list.head;
                while (current) |candidate| {
                    if (candidate == item) {
                        if (previous) |prev| {
                            prev.next_sibling = item.next_sibling;
                        } else {
                            list.head = item.next_sibling;
                        }
                        if (list.tail == item) {
                            list.tail = previous;
                        }
                        return;
                    }
                    previous = candidate;
                    current = candidate.next_sibling;
                }
                unreachable;
            }

            fn removeFromRootList(list: *RootList, item: *T, node: *LinkedNode) void {
                var previous: ?*T = null;
                var current = list.head;
                while (current) |candidate| {
                    if (candidate == item) {
                        if (previous) |prev| {
                            @field(prev.*, field).next_sibling = node.next_sibling;
                        } else {
                            list.head = if (node.next_sibling) |next|
                                @as(*T, @fieldParentPtr(field, next))
                            else
                                null;
                        }
                        if (list.tail == item) {
                            list.tail = previous;
                        }
                        return;
                    }
                    previous = candidate;
                    const next = @field(candidate.*, field).next_sibling orelse break;
                    current = @as(*T, @fieldParentPtr(field, next));
                }
                unreachable;
            }

            fn assertDetached(item: *T) void {
                const node = &@field(item.*, field);
                std.debug.assert(node.parent == null);
                std.debug.assert(node.next_sibling == null);
            }
        };
    }
};

const Impl = struct {
    fn appendRoot(comptime F: type, self: *F, item: F.NodeID) F.AppendError!void {
        const links = try linkMut(F, self, item);
        if (try isLinked(F, self, item, links)) {
            return error.AlreadyLinked;
        }

        if (self.roots.tail) |tail| {
            (try linkMut(F, self, tail)).sibling = item;
        } else {
            self.roots.head = item;
        }
        self.roots.tail = item;
    }

    fn appendChild(comptime F: type, self: *F, parent: F.NodeID, child: F.NodeID) F.AppendError!void {
        const parent_links = try linkMut(F, self, parent);
        const child_links = try linkMut(F, self, child);
        if (parent == child or try isLinked(F, self, child, child_links)) {
            return error.AlreadyLinked;
        }

        if (parent_links.children.tail) |tail| {
            (try linkMut(F, self, tail)).sibling = child;
        } else {
            parent_links.children.head = child;
        }
        parent_links.children.tail = child;
        child_links.parent = parent;
    }

    fn remove(comptime F: type, self: *F, item: F.NodeID) F.RemoveError!void {
        const links = try linkMut(F, self, item);
        if (links.parent) |parent| {
            const parent_links = try linkMut(F, self, parent);
            try removeFromList(F, self, &parent_links.children, item, links);
        } else {
            try removeFromList(F, self, &self.roots, item, links);
        }
        links.parent = null;
        links.sibling = null;
    }

    fn assertValid(comptime F: type, self: *const F) void {
        assertSiblingList(F, self, self.roots, null);
        for (self.links, 0..) |links, index| {
            if (links.parent) |parent| {
                std.debug.assert(@intFromEnum(parent) < self.links.len);
            }
            if (links.sibling) |next| {
                std.debug.assert(@intFromEnum(next) < self.links.len);
            }
            assertSiblingList(F, self, links.children, @enumFromInt(index));
        }
    }

    fn link(comptime F: type, self: *const F, item: F.NodeID) F.BoundsError!*const F.Links {
        const index = @intFromEnum(item);
        if (index >= self.links.len) {
            return error.OutOfBounds;
        }
        return &self.links[index];
    }

    fn linkMut(comptime F: type, self: *F, item: F.NodeID) F.BoundsError!*F.Links {
        const index = @intFromEnum(item);
        if (index >= self.links.len) {
            return error.OutOfBounds;
        }
        return &self.links[index];
    }

    fn isLinked(comptime F: type, self: *const F, item: F.NodeID, links: *const F.Links) F.BoundsError!bool {
        if (links.parent != null or links.sibling != null) {
            return true;
        }
        return contains(F, self, self.roots.head, item);
    }

    fn contains(comptime F: type, self: *const F, head: ?F.NodeID, item: F.NodeID) F.BoundsError!bool {
        var current = head;
        var steps: usize = 0;
        while (current) |candidate| : (steps += 1) {
            std.debug.assert(steps < self.links.len);
            if (candidate == item) {
                return true;
            }
            current = (try link(F, self, candidate)).sibling;
        }
        return false;
    }

    fn removeFromList(
        comptime F: type,
        self: *F,
        list: *F.SiblingList,
        item: F.NodeID,
        links: *F.Links,
    ) F.RemoveError!void {
        var previous: ?F.NodeID = null;
        var current = list.head;
        var steps: usize = 0;

        while (current) |candidate| : (steps += 1) {
            std.debug.assert(steps < self.links.len);

            if (candidate == item) {
                if (previous) |prev| {
                    self.links[@intFromEnum(prev)].sibling = links.sibling;
                } else {
                    list.head = links.sibling;
                }

                if (list.tail == item) {
                    list.tail = previous;
                }

                return;
            }

            const candidate_links = try linkMut(F, self, candidate);
            previous = candidate;
            current = candidate_links.sibling;
        }

        return error.NotLinked;
    }

    fn assertSiblingList(comptime F: type, self: *const F, list: F.SiblingList, parent: ?F.NodeID) void {
        if (list.head == null) {
            std.debug.assert(list.tail == null);
            return;
        }

        std.debug.assert(list.tail != null);

        var current = list.head;
        var last: ?F.NodeID = null;
        var steps: usize = 0;

        while (current) |item| : (steps += 1) {
            std.debug.assert(steps < self.links.len);
            const links = link(F, self, item) catch unreachable;
            std.debug.assert(links.parent == parent);

            last = item;
            current = links.sibling;
        }

        std.debug.assert(last == list.tail);
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "unit: dense forest orders siblings and detaches leaves" {
        const F = Forest.Static(4);
        var forest = F.init();

        const root = try forest.nodeId(0);
        const other = try forest.nodeId(1);
        const a = try forest.nodeId(2);
        const b = try forest.nodeId(3);

        try Impl.appendRoot(F, &forest, root);
        try Impl.appendRoot(F, &forest, other);
        try Impl.appendChild(F, &forest, root, a);
        try Impl.appendChild(F, &forest, root, b);

        try testing.expectEqual(F.SiblingList{ .head = root, .tail = other }, forest.roots);
        try testing.expectEqual(@as(?F.NodeID, other), forest.links[0].sibling);
        try testing.expectEqual(F.SiblingList{ .head = a, .tail = b }, forest.links[0].children);
        try testing.expectEqual(@as(?F.NodeID, b), forest.links[2].sibling);
        try testing.expectEqual(@as(?F.NodeID, root), forest.links[3].parent);
        Impl.assertValid(F, &forest);

        try Impl.remove(F, &forest, other);

        try testing.expectEqual(F.SiblingList{ .head = root, .tail = root }, forest.roots);
        try testing.expectEqual(@as(?F.NodeID, null), forest.links[0].sibling);
        try testing.expectEqual(F.Links{}, forest.links[1]);
        Impl.assertValid(F, &forest);

        try Impl.remove(F, &forest, a);

        try testing.expectEqual(F.SiblingList{ .head = b, .tail = b }, forest.links[0].children);
        try testing.expectEqual(F.Links{}, forest.links[2]);
        Impl.assertValid(F, &forest);
    }

    test "unit: dense forest detaches a subtree without clearing descendants" {
        const F = Forest.Static(3);
        var forest = F.init();

        const root = try forest.nodeId(0);
        const child = try forest.nodeId(1);
        const grandchild = try forest.nodeId(2);

        try Impl.appendRoot(F, &forest, root);
        try Impl.appendChild(F, &forest, root, child);
        try Impl.appendChild(F, &forest, child, grandchild);

        try Impl.remove(F, &forest, child);

        try testing.expectEqual(F.SiblingList{}, forest.links[0].children);
        try testing.expectEqual(@as(?F.NodeID, null), forest.links[1].parent);
        try testing.expectEqual(@as(?F.NodeID, null), forest.links[1].sibling);
        try testing.expectEqual(F.SiblingList{ .head = grandchild, .tail = grandchild }, forest.links[1].children);
        try testing.expectEqual(@as(?F.NodeID, child), forest.links[2].parent);

        Impl.assertValid(F, &forest);
    }

    test "unit: dense forest rejects invalid operations without mutation" {
        const F = Forest.Static(2);
        var forest = F.init();

        const root = try forest.nodeId(0);
        const detached = try forest.nodeId(1);
        const bad: F.NodeID = @enumFromInt(2);

        try Impl.appendRoot(F, &forest, root);

        const roots = forest.roots;
        const links = forest.links;

        try testing.expectError(error.AlreadyLinked, Impl.appendRoot(F, &forest, root));
        try testing.expectError(error.AlreadyLinked, Impl.appendChild(F, &forest, root, root));
        try testing.expectError(error.OutOfBounds, Impl.appendRoot(F, &forest, bad));
        try testing.expectError(error.NotLinked, Impl.remove(F, &forest, detached));

        try testing.expectEqual(roots, forest.roots);
        try testing.expectEqualSlices(F.Links, &links, &forest.links);

        Impl.assertValid(F, &forest);
    }

    test "unit: Forest.Static clears inline topology" {
        const F = Forest.Static(2);
        var forest = F.init();

        const root = try forest.nodeId(0);
        const child = try forest.nodeId(1);

        try forest.appendRoot(root);
        try forest.appendChild(root, child);

        forest.clearRetainingCapacity();

        try testing.expect(forest.isEmpty());
        try testing.expectEqual(@as(?F.NodeID, null), forest.lastRoot());
        try testing.expectEqual(@as(?F.NodeID, null), try forest.parent(child));
        try testing.expectEqual(@as(?F.NodeID, null), try forest.firstChild(root));
        try testing.expectEqual(@as(?F.NodeID, null), try forest.lastChild(root));

        forest.assertValid();
    }

    test "unit: Forest.Bounded resets and updates borrowed links" {
        const F = Forest.Bounded();
        var links = [_]F.Links{
            .{
                .parent = @enumFromInt(0),
                .children = .{ .head = @enumFromInt(1), .tail = @enumFromInt(1) },
                .sibling = @enumFromInt(1),
            },
            .{ .parent = @enumFromInt(0) },
        };

        var forest = F.wrap(&links);

        try testing.expect(forest.isEmpty());
        try testing.expectEqual(F.Links{}, links[0]);
        try testing.expectEqual(F.Links{}, links[1]);

        const root = try forest.nodeId(0);
        const child = try forest.nodeId(1);
        try forest.appendRoot(root);
        try forest.appendChild(root, child);

        try testing.expectEqual(@as(?F.NodeID, root), links[1].parent);
        try testing.expectEqual(F.SiblingList{ .head = child, .tail = child }, links[0].children);
        forest.assertValid();
    }

    test "unit: Forest.Bounded accepts empty backing" {
        const F = Forest.Bounded();
        var forest = F.wrap(&.{});
        const bad: F.NodeID = @enumFromInt(0);

        try testing.expect(forest.isEmpty());
        try testing.expectError(error.OutOfBounds, forest.nodeId(0));
        try testing.expectError(error.OutOfBounds, forest.appendRoot(bad));
        forest.assertValid();
    }

    const Item = struct {
        value: u8,
        node: Forest.LinkedNode = .{},
        other_node: Forest.LinkedNode = .{},
    };

    test "unit: Forest.Linked orders and detaches children and subtrees" {
        const F = Forest.Linked(Item, "node");
        var forest = F.init();
        var a = Item{ .value = 1 };
        var b = Item{ .value = 2 };
        var c = Item{ .value = 3 };
        var d = Item{ .value = 4 };
        forest.appendRoot(&a);
        forest.appendRoot(&b);
        F.appendChild(&a, &c);
        F.appendChild(&a, &d);

        try testing.expect(forest.firstRoot() == &a);
        try testing.expect(forest.lastRoot() == &b);
        try testing.expect(F.nextSibling(&a) == &b);
        try testing.expect(F.firstChild(&a) == &c);
        try testing.expect(F.lastChild(&a) == &d);
        try testing.expect(F.nextSibling(&c) == &d);
        try testing.expect(F.parent(&d) == &a);

        forest.remove(&c);

        try testing.expect(F.firstChild(&a) == &d);
        try testing.expect(F.lastChild(&a) == &d);
        try testing.expect(F.parent(&c) == null);
        try testing.expect(F.nextSibling(&c) == null);

        F.appendChild(&d, &c);
        forest.remove(&d);

        try testing.expect(F.firstChild(&a) == null);
        try testing.expect(F.lastChild(&a) == null);
        try testing.expect(F.parent(&d) == null);
        try testing.expect(F.firstChild(&d) == &c);
        try testing.expect(F.lastChild(&d) == &c);
        try testing.expect(F.parent(&c) == &d);
    }

    test "unit: Forest.Linked custom field and mutable accessors" {
        const F = Forest.Linked(Item, "other_node");

        var forest = F.init();
        var a = Item{ .value = 1 };
        var b = Item{ .value = 2 };
        var c = Item{ .value = 3 };
        var d = Item{ .value = 4 };

        forest.appendRoot(&a);
        forest.appendRoot(&b);
        F.appendChild(&a, &c);
        F.appendChild(&a, &d);

        const view: *const F = &forest;
        const const_a: *const Item = &a;
        const const_c: *const Item = &c;

        forest.firstRootMut().?.value += 10;
        forest.lastRootMut().?.value += 20;
        F.parentMut(&d).?.value += 100;
        F.firstChildMut(&a).?.value += 30;
        F.lastChildMut(&a).?.value += 40;
        F.nextSiblingMut(&c).?.value += 100;

        try testing.expectEqual(@as(u8, 111), a.value);
        try testing.expectEqual(@as(u8, 22), b.value);
        try testing.expectEqual(@as(u8, 33), c.value);
        try testing.expectEqual(@as(u8, 144), d.value);
        try testing.expect(view.firstRoot() == const_a);
        try testing.expect(view.lastRoot() == &b);
        try testing.expect(F.firstChild(const_a) == const_c);
        try testing.expect(F.lastChild(const_a) == &d);
        try testing.expect(F.nextSibling(const_c) == &d);
        try testing.expect(F.parent(&d) == const_a);
        try testing.expectEqual(Forest.LinkedNode{}, c.node);
    }
};
