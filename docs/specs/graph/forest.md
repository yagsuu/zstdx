# Forest

Status: Approved.

`stdx.graph.Forest` owns reusable forest topology. It provides dense node-id
forests for caller payload side arrays and pointer-linked forests for
caller-owned objects with embedded nodes.

A forest is zero or more roots. Every node has at most one parent, an ordered
child list, and an ordered next-sibling link. Root and child lists store both
`head` and `tail`, so appending roots or children is `O(1)`.

## Owned scope

This spec owns:

- the `stdx.graph` namespace surface for forest topology;
- `graph.Forest`;
- `graph.Forest.Static(capacity)`;
- `graph.Forest.Bounded()`;
- `graph.Forest.LinkedNode`;
- `graph.Forest.Linked(T, node_field)`;
- parent, child-list, and next-sibling topology;
- root-list ownership;
- append-root, append-child, remove/detach, clear, validation, and accessor
  operations;
- no-allocation behavior for all variants;
- no-mutation-on-error behavior for dense variants;
- pointer stability and invalidation contracts;
- deterministic sibling order;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- payload storage;
- managed dynamic forests;
- node allocation;
- general directed graphs or multi-parent edges;
- traversal iterator objects;
- DFS/BFS/preorder/postorder traversal helpers;
- sorting, uniqueness, key extraction, or lookup policy;
- owner tracking for perfect double-insert detection in linked forests;
- lock-free, atomic, or internally synchronized access;
- ABI, wire, or packed layout guarantees.

Generic traversal helpers belong to `docs/specs/graph/traversal.md`.

## Public namespace

`Forest` lives under `stdx.graph`:

```zig
stdx.graph.Forest
stdx.graph.Forest.Static
stdx.graph.Forest.Bounded
stdx.graph.Forest.Linked
```

It is not root-promoted:

```zig
stdx.Forest // not exported
```

The root package facade exports the `graph` namespace:

```zig
pub const graph = @import("graph.zig");
```

## Source ownership

```text
src/graph.zig
src/graph/forest.zig
test/graph/forest_test.zig
```

`src/graph.zig` is a thin facade:

```zig
pub const forest = @import("graph/forest.zig");

pub const Forest = forest.Forest;
```

## Approved API

```zig
pub const Forest = struct {
    pub fn Static(comptime capacity: usize) type;
    pub fn Bounded() type;

    pub const LinkedNode = struct {
        parent: ?*LinkedNode = null,
        children: ChildList = .{},
        next_sibling: ?*LinkedNode = null,

        pub const ChildList = struct {
            head: ?*LinkedNode = null,
            tail: ?*LinkedNode = null,
        };
    };

    pub fn Linked(comptime T: type, comptime node_field: []const u8) type;
};
```

### `Static(capacity)` returned type

```zig
pub const Self = struct {
    roots: SiblingList = .{},
    links: [capacity]Links = [_]Links{.{}} ** capacity,

    pub const node_capacity = capacity;

    pub const NodeId = enum(usize) { _ };

    pub const SiblingList = struct {
        head: ?NodeId = null,
        tail: ?NodeId = null,
    };

    pub const Links = struct {
        parent: ?NodeId = null,
        children: SiblingList = .{},
        next_sibling: ?NodeId = null,
    };

    pub const BoundsError = error{OutOfBounds};
    pub const AppendError = error{ OutOfBounds, AlreadyLinked };
    pub const RemoveError = error{ OutOfBounds, NotLinked };
    pub const Error = BoundsError || AppendError || RemoveError;

    pub fn init() Self;

    pub fn capacity(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;

    pub fn nodeId(self: *const Self, index: usize) BoundsError!NodeId;
    pub fn indexOf(node: NodeId) usize;

    pub fn firstRoot(self: *const Self) ?NodeId;
    pub fn lastRoot(self: *const Self) ?NodeId;

    pub fn appendRoot(self: *Self, node: NodeId) AppendError!void;
    pub fn appendChild(self: *Self, parent: NodeId, child: NodeId) AppendError!void;
    pub fn remove(self: *Self, node: NodeId) RemoveError!void;

    pub fn parent(self: *const Self, node: NodeId) BoundsError!?NodeId;
    pub fn firstChild(self: *const Self, node: NodeId) BoundsError!?NodeId;
    pub fn lastChild(self: *const Self, node: NodeId) BoundsError!?NodeId;
    pub fn nextSibling(self: *const Self, node: NodeId) BoundsError!?NodeId;

    pub fn clearRetainingCapacity(self: *Self) void;
    pub fn assertValid(self: *const Self) void;
};
```

### `Bounded()` returned type

```zig
pub const Self = struct {
    roots: SiblingList = .{},
    links: []Links,

    pub const NodeId = enum(usize) { _ };

    pub const SiblingList = struct {
        head: ?NodeId = null,
        tail: ?NodeId = null,
    };

    pub const Links = struct {
        parent: ?NodeId = null,
        children: SiblingList = .{},
        next_sibling: ?NodeId = null,
    };

    pub const BoundsError = error{OutOfBounds};
    pub const AppendError = error{ OutOfBounds, AlreadyLinked };
    pub const RemoveError = error{ OutOfBounds, NotLinked };
    pub const Error = BoundsError || AppendError || RemoveError;

    pub fn wrap(links: []Links) Self;

    pub fn capacity(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;

    pub fn nodeId(self: *const Self, index: usize) BoundsError!NodeId;
    pub fn indexOf(node: NodeId) usize;

    pub fn firstRoot(self: *const Self) ?NodeId;
    pub fn lastRoot(self: *const Self) ?NodeId;

    pub fn appendRoot(self: *Self, node: NodeId) AppendError!void;
    pub fn appendChild(self: *Self, parent: NodeId, child: NodeId) AppendError!void;
    pub fn remove(self: *Self, node: NodeId) RemoveError!void;

    pub fn parent(self: *const Self, node: NodeId) BoundsError!?NodeId;
    pub fn firstChild(self: *const Self, node: NodeId) BoundsError!?NodeId;
    pub fn lastChild(self: *const Self, node: NodeId) BoundsError!?NodeId;
    pub fn nextSibling(self: *const Self, node: NodeId) BoundsError!?NodeId;

    pub fn clearRetainingCapacity(self: *Self) void;
    pub fn assertValid(self: *const Self) void;
};
```

### `Linked(T, node_field)` returned type

```zig
pub const Self = struct {
    roots: RootList = .{},

    pub const Node = Forest.LinkedNode;

    pub const RootList = struct {
        head: ?*T = null,
        tail: ?*T = null,
    };

    pub fn init() Self;

    pub fn isEmpty(self: *const Self) bool;

    pub fn firstRoot(self: *Self) ?*T;
    pub fn constFirstRoot(self: *const Self) ?*const T;
    pub fn lastRoot(self: *Self) ?*T;
    pub fn constLastRoot(self: *const Self) ?*const T;

    pub fn appendRoot(self: *Self, item: *T) void;
    pub fn appendChild(parent: *T, child: *T) void;
    pub fn remove(self: *Self, item: *T) void;

    pub fn parent(item: *T) ?*T;
    pub fn constParent(item: *const T) ?*const T;
    pub fn firstChild(item: *T) ?*T;
    pub fn constFirstChild(item: *const T) ?*const T;
    pub fn lastChild(item: *T) ?*T;
    pub fn constLastChild(item: *const T) ?*const T;
    pub fn nextSibling(item: *T) ?*T;
    pub fn constNextSibling(item: *const T) ?*const T;
};
```

`Linked(T, node_field).Node` is an alias for `Forest.LinkedNode`. Caller structs
use the standalone node type to avoid recursive type construction:

```zig
const Item = struct {
    node: stdx.graph.Forest.LinkedNode = .{},
};

const ItemForest = stdx.graph.Forest.Linked(Item, "node");
```

## Dense forest model

`Static` and `Bounded` store topology in dense link tables. Payloads live in
caller-owned side arrays indexed by `NodeId`.

`Static(capacity)` owns inline `[capacity]Links` storage. `capacity == 0` is
valid.

`Bounded.wrap(links)` borrows `links`, clears every entry, and returns an empty
forest with `links.len` capacity. A zero-length slice is valid.

`NodeId` is a strong type nested under each returned forest type. Methods reject
`NodeId` values whose integer index is outside the forest capacity with
`error.OutOfBounds`.

`nodeId(index)` returns `error.OutOfBounds` when `index >= capacity()`.
`indexOf(node)` returns the raw dense index and does not validate capacity.

Dense operations return:

- `error.OutOfBounds` for any out-of-range node id;
- `error.AlreadyLinked` when inserting a node already linked into that forest;
- `error.NotLinked` when removing a node that is not linked as either a root or
  a child of its recorded parent.

Dense operations must leave the forest unchanged on error.

## Linked forest model

`Linked` stores topology in caller objects via an embedded `Forest.LinkedNode`
field. It never allocates and never moves parent objects.

`node_field` must name an addressable `Forest.LinkedNode` field inside `T`.
Invalid field names, wrong node types, non-addressable fields, and incompatible
packed layouts are compile errors where practical.

Each independent forest membership requires a distinct embedded node field.
Inserted objects must remain alive and pointer-stable until removed or until the
whole forest is abandoned with the object storage.

Linked invalid membership operations are programmer errors and use debug
assertions, matching existing intrusive structures.

## Operation semantics

`init()` returns an empty `Static` or `Linked` forest. `wrap()` returns an empty
`Bounded` forest over caller-provided storage.

`isEmpty()` is true when no top-level root exists.

`firstRoot()` and `lastRoot()` return the root list head and tail. Root siblings
are reached through `nextSibling`.

`appendRoot(node)` appends `node` to the top-level root list in `O(1)`. Root
siblings preserve append order.

`appendChild(parent, child)` appends `child` to `parent.children` in `O(1)`.
Child siblings preserve append order. The child's parent link becomes `parent`.

`remove(node)` detaches `node` from its parent child list or from the top-level
root list. It clears the removed node's parent and next-sibling links. It does
not clear the removed node's children list; removing a node with children
detaches the whole subtree. Descendant parent links remain pointed at their
existing parent inside the detached subtree.

`clearRetainingCapacity()` on dense forests clears every link and sets the root
list empty without releasing storage.

## Invariants

For every root or child sibling list, `head == null` if and only if
`tail == null`.

For every linked child, `parent(child)` points at the node whose child list
contains it.

For every sibling list, each `next_sibling` points at the next node in insertion
order or `null` at the tail. The list's `tail` is the final node in that chain.

Dense `assertValid()` asserts:

- every stored node id is in bounds;
- every root and child list has consistent `head`/`tail` fields;
- root and child sibling chains are acyclic within capacity;
- every child chain member records the owning parent;
- empty forests have empty root head and tail.

Linked forests do not expose `assertValid()` in this slice. Full linked-tree
validation needs traversal and owner policy beyond the local mutation contracts.

## Complexity

Dense variants:

- `capacity`, `isEmpty`, `nodeId`, `indexOf`, root and link accessors: `O(1)`;
- `appendRoot`, `appendChild`: `O(1)`;
- `remove`: `O(number of siblings in the source list)`;
- `clearRetainingCapacity`: `O(capacity)`;
- `assertValid`: `O(capacity + sibling edges)`.

Linked variant:

- root and link accessors: `O(1)`;
- `appendRoot`, `appendChild`: `O(1)`;
- `remove`: `O(number of siblings in the source list)`.

No variant allocates or frees memory.

## Threading

All variants are externally synchronized. Concurrent mutation through the same
forest or through the same linked nodes must be coordinated by the caller.

## Required tests

Static tests must cover:

1. zero capacity is empty and rejects node ids;
2. nonzero init is empty;
3. `nodeId` rejects out-of-bounds indexes;
4. root append preserves sibling order and root tail;
5. child append preserves sibling order, child tail, and parent links;
6. removing a leaf child repairs the sibling chain and child tail;
7. removing a top-level root repairs the root chain and root tail;
8. removing a node with children detaches the subtree;
9. invalid operations return errors without mutation;
10. `clearRetainingCapacity` clears topology;
11. `assertValid` succeeds after public mutations.

Bounded tests must cover the same behavior plus:

1. `wrap` clears caller-provided links;
2. capacity comes from `links.len`;
3. zero-length backing is valid.

Linked tests must cover:

1. initialized forest is empty;
2. appending roots preserves sibling order and root tail;
3. appending children sets parent links and preserves child order and child tail;
4. removing a child clears embedded parent/next links and repairs child tail;
5. removing a root repairs the root chain and root tail;
6. removing a subtree leaves descendant parent links intact;
7. custom node field names work;
8. const accessors mirror mutable accessors;
9. operations do not allocate.
