//! Forest topology tests. Spec: docs/specs/graph/forest.md.

const std = @import("std");
const stdx = @import("stdx");

const Forest = stdx.graph.Forest;

const testing = std.testing;

test "unit: Forest.Static(0) is empty and rejects node ids" {
    const F = Forest.Static(0);
    var forest = F.init();

    try testing.expectEqual(@as(usize, 0), forest.capacity());
    try testing.expect(forest.isEmpty());
    try testing.expectEqual(@as(?F.NodeId, null), forest.firstRoot());
    try testing.expectEqual(@as(?F.NodeId, null), forest.lastRoot());
    try testing.expectError(error.OutOfBounds, forest.nodeId(0));
    forest.assertValid();
}

test "unit: Forest.Static appends roots in insertion order" {
    const F = Forest.Static(4);
    var forest = F.init();
    const n0 = try forest.nodeId(0);
    const n1 = try forest.nodeId(1);

    try forest.appendRoot(n0);
    try forest.appendRoot(n1);

    try testing.expectEqual(@as(usize, 4), forest.capacity());
    try testing.expect(!forest.isEmpty());
    try testing.expectEqual(@as(?F.NodeId, n0), forest.firstRoot());
    try testing.expectEqual(@as(?F.NodeId, n1), try forest.nextSibling(n0));
    try testing.expectEqual(@as(?F.NodeId, n1), forest.lastRoot());
    try testing.expectEqual(@as(?F.NodeId, null), try forest.parent(n0));
    forest.assertValid();
}

test "unit: Forest.Static appends children and removes leaves" {
    const F = Forest.Static(4);
    var forest = F.init();
    const parent = try forest.nodeId(0);
    const child_a = try forest.nodeId(1);
    const child_b = try forest.nodeId(2);

    try forest.appendRoot(parent);
    try forest.appendChild(parent, child_a);
    try forest.appendChild(parent, child_b);

    try testing.expectEqual(@as(?F.NodeId, child_a), try forest.firstChild(parent));
    try testing.expectEqual(@as(?F.NodeId, child_b), try forest.nextSibling(child_a));
    try testing.expectEqual(@as(?F.NodeId, child_b), try forest.lastChild(parent));
    try testing.expectEqual(@as(?F.NodeId, parent), try forest.parent(child_b));

    try forest.remove(child_a);

    try testing.expectEqual(@as(?F.NodeId, child_b), try forest.firstChild(parent));
    try testing.expectEqual(@as(?F.NodeId, child_b), try forest.lastChild(parent));
    try testing.expectEqual(@as(?F.NodeId, null), try forest.parent(child_a));
    try testing.expectEqual(@as(?F.NodeId, null), try forest.nextSibling(child_a));
    forest.assertValid();
}

test "unit: Forest.Static detaches a subtree without clearing descendants" {
    const F = Forest.Static(4);
    var forest = F.init();
    const root = try forest.nodeId(0);
    const child = try forest.nodeId(1);
    const grandchild = try forest.nodeId(2);

    try forest.appendRoot(root);
    try forest.appendChild(root, child);
    try forest.appendChild(child, grandchild);
    try forest.remove(child);

    try testing.expectEqual(@as(?F.NodeId, null), try forest.firstChild(root));
    try testing.expectEqual(@as(?F.NodeId, null), try forest.lastChild(root));
    try testing.expectEqual(@as(?F.NodeId, null), try forest.parent(child));
    try testing.expectEqual(@as(?F.NodeId, grandchild), try forest.firstChild(child));
    try testing.expectEqual(@as(?F.NodeId, grandchild), try forest.lastChild(child));
    try testing.expectEqual(@as(?F.NodeId, child), try forest.parent(grandchild));
    forest.assertValid();
}

test "unit: Forest.Static invalid operations do not mutate" {
    const F = Forest.Static(2);
    var forest = F.init();
    const n0 = try forest.nodeId(0);
    const n1 = try forest.nodeId(1);
    const bad: F.NodeId = @enumFromInt(2);

    try forest.appendRoot(n0);
    try testing.expectError(error.AlreadyLinked, forest.appendRoot(n0));
    try testing.expectError(error.AlreadyLinked, forest.appendChild(n0, n0));
    try testing.expectError(error.OutOfBounds, forest.appendRoot(bad));
    try testing.expectError(error.NotLinked, forest.remove(n1));

    try testing.expectEqual(@as(?F.NodeId, n0), forest.firstRoot());
    try testing.expectEqual(@as(?F.NodeId, n0), forest.lastRoot());
    try testing.expectEqual(@as(?F.NodeId, null), try forest.nextSibling(n0));
    forest.assertValid();
}

test "unit: Forest.Static clearRetainingCapacity clears topology" {
    const F = Forest.Static(3);
    var forest = F.init();
    const root = try forest.nodeId(0);
    const child = try forest.nodeId(1);

    try forest.appendRoot(root);
    try forest.appendChild(root, child);
    forest.clearRetainingCapacity();

    try testing.expect(forest.isEmpty());
    try testing.expectEqual(@as(?F.NodeId, null), forest.lastRoot());
    try testing.expectEqual(@as(?F.NodeId, null), try forest.parent(child));
    try testing.expectEqual(@as(?F.NodeId, null), try forest.firstChild(root));
    try testing.expectEqual(@as(?F.NodeId, null), try forest.lastChild(root));
    forest.assertValid();
}

test "unit: Forest.Bounded.wrap clears caller-provided links" {
    const F = Forest.Bounded();
    var links = [_]F.Links{
        .{
            .parent = @enumFromInt(0),
            .children = .{ .head = @enumFromInt(1), .tail = @enumFromInt(1) },
            .next_sibling = @enumFromInt(1),
        },
        .{ .parent = @enumFromInt(0) },
    };

    var forest = F.wrap(&links);

    try testing.expectEqual(@as(usize, 2), forest.capacity());
    try testing.expect(forest.isEmpty());
    try testing.expectEqual(F.Links{}, links[0]);
    try testing.expectEqual(F.Links{}, links[1]);
    forest.assertValid();
}

test "unit: Forest.Bounded supports zero-length backing" {
    const F = Forest.Bounded();
    var forest = F.wrap(&.{});

    try testing.expectEqual(@as(usize, 0), forest.capacity());
    try testing.expect(forest.isEmpty());
    try testing.expectError(error.OutOfBounds, forest.nodeId(0));
    forest.assertValid();
}

test "unit: Forest.Bounded mirrors Static topology operations" {
    const F = Forest.Bounded();
    var links: [4]F.Links = undefined;
    var forest = F.wrap(&links);
    const root_a = try forest.nodeId(0);
    const root_b = try forest.nodeId(1);
    const child = try forest.nodeId(2);

    try forest.appendRoot(root_a);
    try forest.appendRoot(root_b);
    try forest.appendChild(root_a, child);

    try testing.expectEqual(@as(?F.NodeId, root_a), forest.firstRoot());
    try testing.expectEqual(@as(?F.NodeId, root_b), try forest.nextSibling(root_a));
    try testing.expectEqual(@as(?F.NodeId, root_b), forest.lastRoot());
    try testing.expectEqual(@as(?F.NodeId, child), try forest.firstChild(root_a));
    try testing.expectEqual(@as(?F.NodeId, child), try forest.lastChild(root_a));
    try testing.expectEqual(@as(?F.NodeId, root_a), try forest.parent(child));
    forest.assertValid();
}

const Item = struct {
    value: u8,
    node: Forest.LinkedNode = .{},
    other_node: Forest.LinkedNode = .{},
};

test "unit: Forest.Linked appends roots and children in insertion order" {
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
    try testing.expect(F.nextSibling(&a) == &b);
    try testing.expect(forest.lastRoot() == &b);
    try testing.expect(F.firstChild(&a) == &c);
    try testing.expect(F.lastChild(&a) == &d);
    try testing.expect(F.nextSibling(&c) == &d);
    try testing.expect(F.parent(&d) == &a);
}

test "unit: Forest.Linked removes a child and clears local links" {
    const F = Forest.Linked(Item, "node");
    var forest = F.init();
    var a = Item{ .value = 1 };
    var b = Item{ .value = 2 };
    var c = Item{ .value = 3 };

    forest.appendRoot(&a);
    F.appendChild(&a, &b);
    F.appendChild(&a, &c);
    forest.remove(&b);

    try testing.expect(F.firstChild(&a) == &c);
    try testing.expect(F.lastChild(&a) == &c);
    try testing.expect(F.parent(&b) == null);
    try testing.expect(F.nextSibling(&b) == null);
}

test "unit: Forest.Linked detaches a subtree without clearing descendants" {
    const F = Forest.Linked(Item, "node");
    var forest = F.init();
    var a = Item{ .value = 1 };
    var b = Item{ .value = 2 };
    var c = Item{ .value = 3 };

    forest.appendRoot(&a);
    F.appendChild(&a, &b);
    F.appendChild(&b, &c);
    forest.remove(&b);

    try testing.expect(F.firstChild(&a) == null);
    try testing.expect(F.lastChild(&a) == null);
    try testing.expect(F.parent(&b) == null);
    try testing.expect(F.firstChild(&b) == &c);
    try testing.expect(F.lastChild(&b) == &c);
    try testing.expect(F.parent(&c) == &b);
}

test "unit: Forest.Linked supports custom node fields and const accessors" {
    const F = Forest.Linked(Item, "other_node");
    var forest = F.init();
    var a = Item{ .value = 1 };
    var b = Item{ .value = 2 };

    forest.appendRoot(&a);
    F.appendChild(&a, &b);

    const const_forest: *const F = &forest;
    const const_a: *const Item = &a;
    const const_b: *const Item = &b;
    try testing.expect(const_forest.constFirstRoot() == const_a);
    try testing.expect(const_forest.constLastRoot() == const_a);
    try testing.expect(F.constFirstChild(const_a) == const_b);
    try testing.expect(F.constLastChild(const_a) == const_b);
    try testing.expect(F.constParent(const_b) == const_a);
}
