//! Forest topology families for dense node IDs and embedded linked nodes.
//! See `docs/specs/graph/forest.md`.

const std = @import("std");

/// Forest topology families. Dense variants store topology by `NodeID`; the
/// linked variant stores topology in caller-owned embedded nodes.
pub const Forest = struct {
    pub fn Static(comptime capacity_nodes: usize) type {
        comptime if (capacity_nodes == 0) @compileError("Forest.Static capacity_nodes must be non-zero");

        return struct {
            roots: SiblingList = .{},
            links: [capacity_nodes]Links = [_]Links{.{}} ** capacity_nodes,

            const Self = @This();

            pub const node_capacity = capacity_nodes;

            pub const NodeID = enum(usize) {
                _,
            };

            pub const SiblingList = struct {
                head: ?NodeID = null,
                tail: ?NodeID = null,
            };

            pub const Links = struct {
                parent: ?NodeID = null,
                children: SiblingList = .{},
                next_sibling: ?NodeID = null,
            };

            pub const BoundsError = error{OutOfBounds};
            pub const AppendError = error{ OutOfBounds, AlreadyLinked };
            pub const RemoveError = error{ OutOfBounds, NotLinked };
            pub const Error = BoundsError || AppendError || RemoveError;

            pub fn init() Self {
                return .{};
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return node_capacity;
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.roots.head == null;
            }

            pub fn nodeId(self: *const Self, index: usize) BoundsError!NodeID {
                if (index >= self.capacity()) return error.OutOfBounds;
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

            /// Faults: `error.OutOfBounds` if `item` is outside capacity; `error.AlreadyLinked` if `item` is already a root or child.
            /// Effects: On error, this function does not change the forest.
            pub fn appendRoot(self: *Self, item: NodeID) AppendError!void {
                const item_links = try self.link(item);
                if (try self.isLinked(item, item_links)) return error.AlreadyLinked;

                if (self.roots.tail) |tail| {
                    (try self.link(tail)).next_sibling = item;
                } else {
                    self.roots.head = item;
                }

                self.roots.tail = item;
            }

            /// Faults: `error.OutOfBounds` if `parent_item` or `child_item` is outside capacity; `error.AlreadyLinked` if the items are equal or `child_item` is linked.
            /// Effects: On error, this function does not change the forest.
            pub fn appendChild(self: *Self, parent_item: NodeID, child_item: NodeID) AppendError!void {
                const parent_links = try self.link(parent_item);
                const child_links = try self.link(child_item);

                if (parent_item == child_item) return error.AlreadyLinked;
                if (try self.isLinked(child_item, child_links)) return error.AlreadyLinked;

                if (parent_links.children.tail) |tail| {
                    (try self.link(tail)).next_sibling = child_item;
                } else {
                    parent_links.children.head = child_item;
                }

                parent_links.children.tail = child_item;
                child_links.parent = parent_item;
            }

            /// Faults: `error.OutOfBounds` if `item` is outside capacity; `error.NotLinked` if `item` is not in its expected list.
            /// Effects: On success, this function clears `item`'s parent and next-sibling links. Its descendants remain attached to `item`.
            /// Cost: O(source-list length).
            pub fn remove(self: *Self, item: NodeID) RemoveError!void {
                const item_links = try self.link(item);

                if (item_links.parent) |parent_item| {
                    const parent_links = try self.link(parent_item);
                    try self.removeFromList(&parent_links.children, item, item_links);
                } else {
                    try self.removeFromList(&self.roots, item, item_links);
                }

                item_links.parent = null;
                item_links.next_sibling = null;
            }

            /// Faults: `error.OutOfBounds` if `indexOf(item) >= capacity()`.
            pub fn parent(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try self.constLink(item)).parent;
            }

            /// Faults: `error.OutOfBounds` if `indexOf(item) >= capacity()`.
            pub fn firstChild(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try self.constLink(item)).children.head;
            }

            pub fn lastChild(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try self.constLink(item)).children.tail;
            }

            /// Faults: `error.OutOfBounds` if `indexOf(item) >= capacity()`.
            pub fn nextSibling(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try self.constLink(item)).next_sibling;
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.roots = .{};
                for (&self.links) |*item_links| item_links.* = .{};
            }

            pub fn assertValid(self: *const Self) void {
                self.assertSiblingList(self.roots, null);

                for (self.links, 0..) |item_links, index| {
                    const item: NodeID = @enumFromInt(index);
                    if (item_links.parent) |parent_item| self.assertInBounds(parent_item);
                    if (item_links.children.head) |child_item| self.assertInBounds(child_item);
                    if (item_links.children.tail) |child_item| self.assertInBounds(child_item);
                    if (item_links.next_sibling) |sibling_item| self.assertInBounds(sibling_item);
                    self.assertSiblingList(item_links.children, item);
                }
            }

            fn link(self: *Self, item: NodeID) BoundsError!*Links {
                const index = indexOf(item);
                if (index >= self.capacity()) return error.OutOfBounds;
                if (capacity_nodes == 0) return error.OutOfBounds;
                return &self.links[index];
            }

            fn constLink(self: *const Self, item: NodeID) BoundsError!*const Links {
                const index = indexOf(item);
                if (index >= self.capacity()) return error.OutOfBounds;
                if (capacity_nodes == 0) return error.OutOfBounds;
                return &self.links[index];
            }

            fn isLinked(self: *const Self, item: NodeID, item_links: *const Links) BoundsError!bool {
                if (item_links.parent != null) return true;
                if (item_links.next_sibling != null) return true;
                return self.contains(self.roots.head, item);
            }

            fn contains(self: *const Self, head: ?NodeID, item: NodeID) BoundsError!bool {
                var current = head;
                var steps: usize = 0;
                while (current) |current_item| : (steps += 1) {
                    std.debug.assert(steps < self.capacity());
                    if (current_item == item) return true;
                    current = (try self.constLink(current_item)).next_sibling;
                }
                return false;
            }

            fn removeFromList(
                self: *Self,
                list: *SiblingList,
                item: NodeID,
                item_links: *Links,
            ) RemoveError!void {
                var previous: ?NodeID = null;
                var current = list.head;
                var steps: usize = 0;
                while (current) |current_item| : (steps += 1) {
                    std.debug.assert(steps < self.capacity());
                    if (current_item == item) {
                        const next = item_links.next_sibling;
                        if (previous) |previous_item| {
                            (try self.link(previous_item)).next_sibling = next;
                        } else {
                            list.head = next;
                        }
                        if (list.tail == item) list.tail = previous;
                        return;
                    }
                    previous = current_item;
                    current = (try self.link(current_item)).next_sibling;
                }
                return error.NotLinked;
            }

            fn assertInBounds(self: *const Self, item: NodeID) void {
                std.debug.assert(indexOf(item) < self.capacity());
            }

            fn assertSiblingList(self: *const Self, list: SiblingList, expected_parent: ?NodeID) void {
                if (list.head == null) {
                    std.debug.assert(list.tail == null);
                    return;
                }

                std.debug.assert(list.tail != null);

                var current = list.head;
                var last: ?NodeID = null;
                var steps: usize = 0;
                while (current) |item| : (steps += 1) {
                    std.debug.assert(steps < self.capacity());

                    self.assertInBounds(item);
                    const item_links = self.constLink(item) catch unreachable;

                    std.debug.assert(item_links.parent == expected_parent);

                    last = item;
                    current = item_links.next_sibling;
                }

                std.debug.assert(last == list.tail);

                const tail_item = list.tail.?;
                self.assertInBounds(tail_item);

                std.debug.assert((self.constLink(tail_item) catch unreachable).next_sibling == null);
            }
        };
    }

    pub fn Bounded() type {
        return struct {
            roots: SiblingList = .{},
            links: []Links,

            const Self = @This();

            pub const NodeID = enum(usize) {
                _,
            };

            pub const SiblingList = struct {
                head: ?NodeID = null,
                tail: ?NodeID = null,
            };

            pub const Links = struct {
                parent: ?NodeID = null,
                children: SiblingList = .{},
                next_sibling: ?NodeID = null,
            };

            pub const BoundsError = error{OutOfBounds};
            pub const AppendError = error{ OutOfBounds, AlreadyLinked };
            pub const RemoveError = error{ OutOfBounds, NotLinked };
            pub const Error = BoundsError || AppendError || RemoveError;

            pub fn wrap(links: []Links) Self {
                for (links) |*item_links| item_links.* = .{};
                return .{ .links = links };
            }

            pub fn capacity(self: *const Self) usize {
                return self.links.len;
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.roots.head == null;
            }

            pub fn nodeId(self: *const Self, index: usize) BoundsError!NodeID {
                if (index >= self.capacity()) return error.OutOfBounds;
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

            /// Faults: `error.OutOfBounds` if `item` is outside capacity; `error.AlreadyLinked` if `item` is already a root or child.
            /// Effects: On error, this function does not change the forest.
            pub fn appendRoot(self: *Self, item: NodeID) AppendError!void {
                const item_links = try self.link(item);
                if (try self.isLinked(item, item_links)) return error.AlreadyLinked;

                if (self.roots.tail) |tail| {
                    (try self.link(tail)).next_sibling = item;
                } else {
                    self.roots.head = item;
                }

                self.roots.tail = item;
            }

            /// Faults: `error.OutOfBounds` if `parent_item` or `child_item` is outside capacity; `error.AlreadyLinked` if the items are equal or `child_item` is linked.
            /// Effects: On error, this function does not change the forest.
            pub fn appendChild(self: *Self, parent_item: NodeID, child_item: NodeID) AppendError!void {
                const parent_links = try self.link(parent_item);
                const child_links = try self.link(child_item);

                if (parent_item == child_item) return error.AlreadyLinked;
                if (try self.isLinked(child_item, child_links)) return error.AlreadyLinked;

                if (parent_links.children.tail) |tail| {
                    (try self.link(tail)).next_sibling = child_item;
                } else {
                    parent_links.children.head = child_item;
                }

                parent_links.children.tail = child_item;
                child_links.parent = parent_item;
            }

            /// Faults: `error.OutOfBounds` if `item` is outside capacity; `error.NotLinked` if `item` is not in its expected list.
            /// Effects: On success, this function clears `item`'s parent and next-sibling links. Its descendants remain attached to `item`.
            /// Cost: O(source-list length).
            pub fn remove(self: *Self, item: NodeID) RemoveError!void {
                const item_links = try self.link(item);
                if (item_links.parent) |parent_item| {
                    const parent_links = try self.link(parent_item);
                    try self.removeFromList(&parent_links.children, item, item_links);
                } else {
                    try self.removeFromList(&self.roots, item, item_links);
                }

                item_links.parent = null;
                item_links.next_sibling = null;
            }

            /// Faults: `error.OutOfBounds` if `indexOf(item) >= capacity()`.
            pub fn parent(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try self.constLink(item)).parent;
            }

            /// Faults: `error.OutOfBounds` if `indexOf(item) >= capacity()`.
            pub fn firstChild(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try self.constLink(item)).children.head;
            }

            pub fn lastChild(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try self.constLink(item)).children.tail;
            }

            /// Faults: `error.OutOfBounds` if `indexOf(item) >= capacity()`.
            pub fn nextSibling(self: *const Self, item: NodeID) BoundsError!?NodeID {
                return (try self.constLink(item)).next_sibling;
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.roots = .{};
                for (self.links) |*item_links| item_links.* = .{};
            }

            pub fn assertValid(self: *const Self) void {
                self.assertSiblingList(self.roots, null);

                for (self.links, 0..) |item_links, index| {
                    const item: NodeID = @enumFromInt(index);
                    if (item_links.parent) |parent_item| self.assertInBounds(parent_item);
                    if (item_links.children.head) |child_item| self.assertInBounds(child_item);
                    if (item_links.children.tail) |child_item| self.assertInBounds(child_item);
                    if (item_links.next_sibling) |sibling_item| self.assertInBounds(sibling_item);
                    self.assertSiblingList(item_links.children, item);
                }
            }

            fn link(self: *Self, item: NodeID) BoundsError!*Links {
                const index = indexOf(item);
                if (index >= self.capacity()) return error.OutOfBounds;
                return &self.links[index];
            }

            fn constLink(self: *const Self, item: NodeID) BoundsError!*const Links {
                const index = indexOf(item);
                if (index >= self.capacity()) return error.OutOfBounds;
                return &self.links[index];
            }

            fn isLinked(self: *const Self, item: NodeID, item_links: *const Links) BoundsError!bool {
                if (item_links.parent != null) return true;
                if (item_links.next_sibling != null) return true;
                return self.contains(self.roots.head, item);
            }

            fn contains(self: *const Self, head: ?NodeID, item: NodeID) BoundsError!bool {
                var current = head;
                var steps: usize = 0;
                while (current) |current_item| : (steps += 1) {
                    std.debug.assert(steps < self.capacity());
                    if (current_item == item) return true;
                    current = (try self.constLink(current_item)).next_sibling;
                }
                return false;
            }

            fn removeFromList(
                self: *Self,
                list: *SiblingList,
                item: NodeID,
                item_links: *Links,
            ) RemoveError!void {
                var previous: ?NodeID = null;
                var current = list.head;
                var steps: usize = 0;

                while (current) |current_item| : (steps += 1) {
                    std.debug.assert(steps < self.capacity());

                    if (current_item == item) {
                        const next = item_links.next_sibling;

                        if (previous) |previous_item| {
                            (try self.link(previous_item)).next_sibling = next;
                        } else {
                            list.head = next;
                        }

                        if (list.tail == item) list.tail = previous;
                        return;
                    }

                    previous = current_item;
                    current = (try self.link(current_item)).next_sibling;
                }

                return error.NotLinked;
            }

            fn assertInBounds(self: *const Self, item: NodeID) void {
                std.debug.assert(indexOf(item) < self.capacity());
            }

            fn assertSiblingList(self: *const Self, list: SiblingList, expected_parent: ?NodeID) void {
                if (list.head == null) {
                    std.debug.assert(list.tail == null);
                    return;
                }

                std.debug.assert(list.tail != null);

                var current = list.head;
                var last: ?NodeID = null;
                var steps: usize = 0;

                while (current) |item| : (steps += 1) {
                    std.debug.assert(steps < self.capacity());
                    self.assertInBounds(item);
                    const item_links = self.constLink(item) catch unreachable;
                    std.debug.assert(item_links.parent == expected_parent);
                    last = item;
                    current = item_links.next_sibling;
                }

                std.debug.assert(last == list.tail);

                const tail_item = list.tail.?;
                self.assertInBounds(tail_item);

                std.debug.assert((self.constLink(tail_item) catch unreachable).next_sibling == null);
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

    pub fn Linked(comptime T: type, comptime node_field: []const u8) type {
        return struct {
            roots: RootList = .{},

            const Self = @This();

            pub const Node = LinkedNode;

            pub const RootList = struct {
                head: ?*T = null,
                tail: ?*T = null,
            };

            pub fn init() Self {
                return .{};
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.roots.head == null;
            }

            pub fn firstRoot(self: *Self) ?*T {
                return self.roots.head;
            }

            pub fn constFirstRoot(self: *const Self) ?*const T {
                return self.roots.head;
            }

            pub fn lastRoot(self: *Self) ?*T {
                return self.roots.tail;
            }

            pub fn constLastRoot(self: *const Self) ?*const T {
                return self.roots.tail;
            }

            pub fn appendRoot(self: *Self, item: *T) void {
                assertDetached(item);

                if (self.roots.tail) |tail| {
                    std.debug.assert(tail != item);
                    node(tail).next_sibling = node(item);
                } else {
                    self.roots.head = item;
                }

                self.roots.tail = item;
            }

            pub fn appendChild(parent_item: *T, child_item: *T) void {
                std.debug.assert(parent_item != child_item);
                assertDetached(child_item);

                const parent_node = node(parent_item);
                const child_node = node(child_item);
                if (parent_node.children.tail) |tail| {
                    std.debug.assert(tail != child_node);
                    tail.next_sibling = child_node;
                } else {
                    parent_node.children.head = child_node;
                }

                parent_node.children.tail = child_node;
                child_node.parent = parent_node;
            }

            pub fn remove(self: *Self, item: *T) void {
                const item_node = node(item);
                if (item_node.parent) |parent_node| {
                    removeFromNodeList(&parent_node.children, item_node);
                } else {
                    removeFromRootList(&self.roots, item, item_node);
                }

                item_node.parent = null;
                item_node.next_sibling = null;
            }

            pub fn parent(item: *T) ?*T {
                const parent_node = node(item).parent orelse return null;
                return itemFromNode(parent_node);
            }

            pub fn constParent(item: *const T) ?*const T {
                const parent_node = constNode(item).parent orelse return null;
                return constItemFromNode(parent_node);
            }

            pub fn firstChild(item: *T) ?*T {
                const child_node = node(item).children.head orelse return null;
                return itemFromNode(child_node);
            }

            pub fn constFirstChild(item: *const T) ?*const T {
                const child_node = constNode(item).children.head orelse return null;
                return constItemFromNode(child_node);
            }

            pub fn lastChild(item: *T) ?*T {
                const child_node = node(item).children.tail orelse return null;
                return itemFromNode(child_node);
            }

            pub fn constLastChild(item: *const T) ?*const T {
                const child_node = constNode(item).children.tail orelse return null;
                return constItemFromNode(child_node);
            }

            pub fn nextSibling(item: *T) ?*T {
                const sibling_node = node(item).next_sibling orelse return null;
                return itemFromNode(sibling_node);
            }

            pub fn constNextSibling(item: *const T) ?*const T {
                const sibling_node = constNode(item).next_sibling orelse return null;
                return constItemFromNode(sibling_node);
            }

            fn removeFromNodeList(list: *LinkedNode.ChildList, item_node: *LinkedNode) void {
                var previous: ?*LinkedNode = null;
                var current = list.head;

                while (current) |candidate_node| {
                    if (candidate_node == item_node) {
                        const next = item_node.next_sibling;

                        if (previous) |previous_node| {
                            previous_node.next_sibling = next;
                        } else {
                            list.head = next;
                        }

                        if (list.tail == item_node) list.tail = previous;
                        return;
                    }

                    previous = candidate_node;
                    current = candidate_node.next_sibling;
                }

                unreachable;
            }

            fn removeFromRootList(list: *RootList, item: *T, item_node: *LinkedNode) void {
                var previous: ?*T = null;
                var current = list.head;

                while (current) |candidate| {
                    if (candidate == item) {
                        const next = if (item_node.next_sibling) |next_node| itemFromNode(next_node) else null;

                        if (previous) |previous_item| {
                            node(previous_item).next_sibling = item_node.next_sibling;
                        } else {
                            list.head = next;
                        }

                        if (list.tail == item) list.tail = previous;
                        return;
                    }

                    previous = candidate;
                    current = nextSibling(candidate);
                }

                unreachable;
            }

            fn node(item: *T) *LinkedNode {
                return &@field(item.*, node_field);
            }

            fn constNode(item: *const T) *const LinkedNode {
                return &@field(item.*, node_field);
            }

            fn itemFromNode(item_node: *LinkedNode) *T {
                return @fieldParentPtr(node_field, item_node);
            }

            fn constItemFromNode(item_node: *const LinkedNode) *const T {
                return @fieldParentPtr(node_field, item_node);
            }

            fn assertDetached(item: *T) void {
                const item_node = node(item);
                std.debug.assert(item_node.parent == null);
                std.debug.assert(item_node.next_sibling == null);
            }
        };
    }
};
