# Forest

Status: Approved.

`stdx.graph.Forest` provides allocation-free forest topology. `Static` and
`Bounded` store topology by dense node identifier. `Linked` stores topology in
caller-owned objects with embedded link nodes.

## What this spec is

This specification defines the `stdx.graph.Forest` namespace, its static,
bounded, and intrusive linked variants, their topology, mutation and accessor
operations, ownership and invalidation rules, complexity, and required tests.

## What this spec is not

This specification does not define:

- payload storage or payload lifetime for dense forests;
- dynamic forest storage or node allocation;
- general directed graphs, multi-parent edges, sorting, uniqueness, key
  extraction, or lookup policy;
- traversal iterator objects or DFS, BFS, preorder, or postorder helpers;
- linked-forest owner tracking that detects every double insertion;
- locking, atomics, or internal synchronization; or
- ABI, wire-format, packed-layout, or field-layout guarantees.

`docs/specs/graph/traversal.md` owns generic traversal helpers.

## Terminology

- A **root** is a node in the forest root list.
- A **child** is a node in a parent node's child list.
- A **sibling list** is an ordered list with `head`, `tail`, and
  `next_sibling` links.
- A **detached node** has no parent and no next sibling. A detached node can
  have children.
- A **source list** is the root list or child list from which `remove` detaches
  a node.

## Public namespace and source ownership

The public import path is `stdx.graph.Forest`. `src/graph.zig` is a thin
facade that exports `forest` and `Forest` from `src/graph/forest.zig`.

This specification owns `src/graph.zig`, `src/graph/forest.zig`, and
`test/graph/forest_test.zig`.

## Cross-spec relationships

This specification composes with caller-owned payload storage. Dense forests
use payload side arrays indexed by `NodeID`; this specification does not own
those arrays or their elements. Linked forests compose with caller-owned
objects and do not own those objects.

## Data structures and representation

A forest contains zero or more ordered roots. Each node has at most one parent,
an ordered child list, and one next-sibling link. Root and child lists retain
both `head` and `tail` so that append operations are `O(1)`.

`Static(capacity_nodes)` stores its links in inline storage for exactly
`capacity_nodes` nodes. `capacity_nodes` MUST be nonzero; a zero value is a
compile error.

`Bounded()` borrows a caller-provided `[]Links` slice. `wrap(links)` clears each
element of `links` before it returns an empty forest with `links.len` capacity.
A zero-length slice is valid.

`Linked(T, node_field)` stores links in the `Forest.LinkedNode` field named by
`node_field` in each caller-owned `T`. `node_field` MUST name an addressable
`Forest.LinkedNode` field in `T`. Invalid field names, an incompatible field
type, non-addressable fields, and incompatible packed layouts are compile
errors where the language can diagnose them.

Each independent linked-forest membership requires a distinct embedded node
field. The caller MUST keep an inserted linked object alive and pointer-stable
until that object is removed or the forest and object storage are abandoned
together.

## Global invariants

Every operation that completes normally preserves these invariants:

- Each sibling list has `head == null` if and only if `tail == null`.
- A nonempty sibling list's `tail` is the final node reached from `head` by
  `next_sibling`; that node has `next_sibling == null`.
- Each sibling chain is in append order and has no cycle.
- A child node's parent link identifies the node whose child list contains the
  child.
- A root has no parent.
- A node belongs to at most one root or child list.
- `remove` detaches only its argument from its source list. It leaves the
  argument's child list and each descendant's parent link unchanged.
- No variant allocates or frees memory.

Dense variants reject any `NodeID` whose integer index is outside capacity with
`error.OutOfBounds`. Dense mutation operations leave all topology unchanged
when they return an error.

Linked operations require valid membership and detached-node preconditions as
specified below. Violating these preconditions is a programmer error. The
implementation uses debug assertions or an unreachable condition; it does not
return an error. A linked forest cannot reliably detect insertion into a
different forest that uses the same embedded node field.

All variants are externally synchronized. The caller MUST coordinate concurrent
mutation through the same forest or through the same linked nodes.

## API

```zig
pub const Forest = struct {
    pub fn Static(comptime capacity_nodes: usize) type;
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

### `Static(capacity_nodes)` returned type

```zig
pub const Self = struct {
    roots: SiblingList = .{},
    links: [capacity_nodes]Links = [_]Links{.{}} ** capacity_nodes,
    pub const node_capacity = capacity_nodes;
    pub const NodeID = enum(usize) { _ };
    pub const SiblingList = struct { head: ?NodeID = null, tail: ?NodeID = null };
    pub const Links = struct {
        parent: ?NodeID = null,
        children: SiblingList = .{},
        next_sibling: ?NodeID = null,
    };
    pub const BoundsError = error{OutOfBounds};
    pub const AppendError = error{ OutOfBounds, AlreadyLinked };
    pub const RemoveError = error{ OutOfBounds, NotLinked };
    pub const Error = BoundsError || AppendError || RemoveError;

    pub fn init() Self;
    pub fn capacity(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn nodeId(self: *const Self, index: usize) BoundsError!NodeID;
    pub fn indexOf(node: NodeID) usize;
    pub fn firstRoot(self: *const Self) ?NodeID;
    pub fn lastRoot(self: *const Self) ?NodeID;
    pub fn appendRoot(self: *Self, item: NodeID) AppendError!void;
    pub fn appendChild(self: *Self, parent_item: NodeID, child_item: NodeID) AppendError!void;
    pub fn remove(self: *Self, item: NodeID) RemoveError!void;
    pub fn parent(self: *const Self, item: NodeID) BoundsError!?NodeID;
    pub fn firstChild(self: *const Self, item: NodeID) BoundsError!?NodeID;
    pub fn lastChild(self: *const Self, item: NodeID) BoundsError!?NodeID;
    pub fn nextSibling(self: *const Self, item: NodeID) BoundsError!?NodeID;
    pub fn clearRetainingCapacity(self: *Self) void;
    pub fn assertValid(self: *const Self) void;
};
```

### `Bounded()` returned type

```zig
pub const Self = struct {
    roots: SiblingList = .{},
    links: []Links,
    pub const NodeID = enum(usize) { _ };
    pub const SiblingList = struct { head: ?NodeID = null, tail: ?NodeID = null };
    pub const Links = struct {
        parent: ?NodeID = null,
        children: SiblingList = .{},
        next_sibling: ?NodeID = null,
    };
    pub const BoundsError = error{OutOfBounds};
    pub const AppendError = error{ OutOfBounds, AlreadyLinked };
    pub const RemoveError = error{ OutOfBounds, NotLinked };
    pub const Error = BoundsError || AppendError || RemoveError;

    pub fn wrap(links: []Links) Self;
    pub fn capacity(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn nodeId(self: *const Self, index: usize) BoundsError!NodeID;
    pub fn indexOf(node: NodeID) usize;
    pub fn firstRoot(self: *const Self) ?NodeID;
    pub fn lastRoot(self: *const Self) ?NodeID;
    pub fn appendRoot(self: *Self, item: NodeID) AppendError!void;
    pub fn appendChild(self: *Self, parent_item: NodeID, child_item: NodeID) AppendError!void;
    pub fn remove(self: *Self, item: NodeID) RemoveError!void;
    pub fn parent(self: *const Self, item: NodeID) BoundsError!?NodeID;
    pub fn firstChild(self: *const Self, item: NodeID) BoundsError!?NodeID;
    pub fn lastChild(self: *const Self, item: NodeID) BoundsError!?NodeID;
    pub fn nextSibling(self: *const Self, item: NodeID) BoundsError!?NodeID;
    pub fn clearRetainingCapacity(self: *Self) void;
    pub fn assertValid(self: *const Self) void;
};
```

### `Linked(T, node_field)` returned type

```zig
pub const Self = struct {
    roots: RootList = .{},
    pub const Node = Forest.LinkedNode;
    pub const RootList = struct { head: ?*T = null, tail: ?*T = null };

    pub fn init() Self;
    pub fn isEmpty(self: *const Self) bool;
    pub fn firstRoot(self: *Self) ?*T;
    pub fn constFirstRoot(self: *const Self) ?*const T;
    pub fn lastRoot(self: *Self) ?*T;
    pub fn constLastRoot(self: *const Self) ?*const T;
    pub fn appendRoot(self: *Self, item: *T) void;
    pub fn appendChild(parent_item: *T, child_item: *T) void;
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

`Linked(T, node_field).Node` aliases `Forest.LinkedNode`. For example:

```zig
const Item = struct {
    node: stdx.graph.Forest.LinkedNode = .{},
};
const ItemForest = stdx.graph.Forest.Linked(Item, "node");
```

### Construction and accessors

`Static.init()` and `Linked.init()` return empty forests. `Bounded.wrap()`
returns an empty forest after clearing the borrowed links. `isEmpty()` is true
exactly when the root list is empty. `capacity()` returns the dense forest
capacity. `nodeId(index)` returns the `NodeID` for `index` or
`error.OutOfBounds` when `index >= capacity()`. `indexOf(node)` returns the raw
integer representation and does not validate it.

The root, parent, child, and sibling accessors return the corresponding link or
`null`. Dense link accessors return `error.OutOfBounds` for an out-of-capacity
argument and do not mutate the forest. Linked `const*` accessors return const
pointers and otherwise have the same result as their mutable counterparts.

Accessors allocate nothing, wait for nothing, and run in `O(1)` time.

### `appendRoot` and `appendChild`

`appendRoot` appends its node to the root list. `appendChild` appends its child
to the specified parent's child list and sets the child's parent link. Both
operations preserve append order.

For dense variants, `appendRoot` returns `error.OutOfBounds` when `item` is
outside capacity and `error.AlreadyLinked` when `item` is already linked.
`appendChild` returns `error.OutOfBounds` when either argument is outside
capacity. It returns `error.AlreadyLinked` when both arguments identify the
same node or when `child_item` is already linked. On either error, the dense
forest remains unchanged.

For linked variants, the caller MUST pass a detached `item` to `appendRoot`.
The caller MUST pass distinct objects and a detached `child_item` to
`appendChild`. Violating either condition is a programmer error.

These operations allocate nothing, wait for nothing, and run in `O(1)` time.

### `remove`

`remove` detaches `item` from its source list. On success, it clears `item`'s
parent and next-sibling links. It does not clear `item`'s children list.
Removing an item with children detaches the complete subtree, and descendant
parent links remain within that detached subtree.

For dense variants, `remove` returns `error.OutOfBounds` for an out-of-capacity
item and `error.NotLinked` when the item is neither a root nor a member of its
recorded parent list. On either error, the dense forest remains unchanged.

For linked variants, the caller MUST pass an item that is a root of `self` or a
member of its recorded parent's child list. Violating this condition is a
programmer error.

`remove` allocates nothing, waits for nothing, and runs in `O(number of nodes
in the source list)` time.

### `clearRetainingCapacity` and `assertValid`

`clearRetainingCapacity` applies only to dense variants. It empties the root
list and clears every dense link without releasing `Static` storage or changing
the borrowed `Bounded` slice. It invalidates all existing dense topology:
every node becomes detached. It allocates nothing, waits for nothing, and runs
in `O(capacity)` time.

`assertValid` applies only to dense variants. It asserts that every stored node
identifier is in bounds; that all root and child lists have consistent head and
tail links; that sibling chains are acyclic within capacity; that every child
records its owning parent; and that an empty forest has an empty root head and
tail. It allocates nothing, waits for nothing, and runs in
`O(capacity + sibling edges)` time. Linked forests intentionally do not expose
whole-forest validation.

## Implementation constraints

The implementation MUST retain root and child-list heads and tails. Dense
variants MUST use their supplied fixed storage only. Linked variants MUST store
topology in the specified embedded nodes and MUST NOT move caller objects. No
operation may allocate or free memory.

## Testing

Tests MUST exercise each dense variant against a small reference forest model.
After each generated or enumerated sequence of valid root appends, child
appends, removals, and clears, tests MUST compare root order, child order,
parent links, sibling links, and empty-state results to the model. This method
proves that mutations preserve the topology and ordering contract across state
transitions, not only for isolated operations.

Dense tests MUST verify `nodeId` boundaries, including the valid zero-length
`Bounded` backing slice and the compile-time nonzero `Static` capacity rule.
They MUST verify `wrap` clears every borrowed link, error values for invalid
identifiers and invalid mutation, and no mutation on each error path. Tests
MUST call `assertValid` after successful public mutations and after error paths
to verify the dense representation invariants.

Tests MUST cover removal from the head, middle, and tail of root and child
lists, and removal of a node with descendants. These boundaries prove correct
head/tail repair, sibling repair, subtree detachment, and descendant-link
retention.

Linked tests MUST construct objects with the default and a custom embedded node
field. They MUST verify root and child append order, parent and sibling links,
root and child removal repair, subtree detachment, and agreement between each
mutable accessor and its const accessor. Tests MUST verify that all variants
perform no allocation; this proves that callers can use the variants without an
allocator or hidden allocation path.
