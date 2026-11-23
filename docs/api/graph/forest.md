# `stdx.graph.Forest`

`stdx.graph.Forest` maintains ordered roots and ordered children in fixed storage
or caller-owned objects. Each node has at most one parent.

## Variants and storage

| Type | Construction and storage |
|---|---|
| `Forest.Static(N)` | `Forest.Static(N).init()` creates empty topology in an inline array of `N` links. Zero capacity is a compile error. |
| `Forest.Bounded()` | `Forest.Bounded().wrap(links)` clears the borrowed `[]Links` slice and creates empty topology. Empty backing is valid. Keep storage alive and stable throughout use. |
| `Forest.Linked(T, field)` | `Forest.Linked(T, field).init()` creates an empty root list. Each caller-owned `T` supplies an addressable `Forest.LinkedNode` field named by `field`. |

`Dense.*` denotes shared operations on `Forest.Static(N)` and `Forest.Bounded()`.
`Linked.*` denotes operations on `Forest.Linked(T, field)`.

Callers manage payload storage separately, indexed with `Dense.indexOf(node)`.

Linked objects remain caller-owned. Keep every referenced object alive and at
the same address, including objects in detached subtrees. Independent
memberships require distinct embedded node fields. Do not modify topology fields
directly or copy active linked objects to a new address.

All variants require external synchronization when concurrent access can mutate
the same topology. Operations neither allocate nor free storage.

## Dense identifiers and access

`Dense.NodeID` is an `enum(usize)` specific to its returned type.
`Dense.nodeId(index)` returns an identifier when `index < Dense.capacity()`.
Otherwise it returns `error.OutOfBounds`. `Dense.indexOf(node)` returns the raw
index without validation.

Identifiers retain their indices across removal, clearing, and reuse.
Callers track payload lifetime and instance ownership.

`Dense.firstRoot()` and `Dense.lastRoot()` return the root-list endpoints.
`Dense.parent(node)`, `Dense.firstChild(node)`, `Dense.lastChild(node)`, and
`Dense.nextSibling(node)` return the stored link or `null`. Each first checks
the argument's bounds. A detached node can still have children.
`Dense.isEmpty()` tests only whether the root list is empty, not whether
detached subtrees exist.

## Append, detach, and reattach

`Dense.appendRoot(item)` and `Linked.appendRoot(item)` append to the root list.
`Dense.appendChild(parent_item, child_item)` and
`Linked.appendChild(parent_item, child_item)` append to the parent's child list.
Both lists retain insertion order. A parent can itself be detached.

The child or root being appended must not already belong to a root or child
list. To move a subtree:

1. Remove its root from its current list. Removal preserves its children and descendants.
2. Append the root at the destination. Callers MUST NOT attach it below one of its descendants.

### Dense validation

| Operation | Validation order and errors |
|---|---|
| `Dense.appendRoot(item)` | Check `item` bounds, then return `error.AlreadyLinked` if it has a parent, has a next sibling, or occurs in the root list. |
| `Dense.appendChild(parent_item, child_item)` | Check parent bounds, then child bounds. Return `error.AlreadyLinked` for equal identifiers or an already-linked child. |
| `Dense.remove(item)` | Check item bounds, then search its recorded parent's child list, or the root list when its parent is `null`. Return `error.NotLinked` when absent. |

Out-of-range arguments return `error.OutOfBounds`. With valid stored topology,
these errors leave the forest unchanged. Appending an already-linked node does
not reposition it.

`Dense.remove(item)` repairs the source list and clears only the removed node's
`parent` and `sibling`. A successful removal leaves the node available for
reattachment. It neither releases a node slot nor changes payload storage.

### Linked preconditions and access

`Linked.appendChild()` is a type operation on two object pointers. The caller
MUST supply distinct objects and an unlinked child. `Linked.appendRoot()`
likewise requires an unlinked object. The selected embedded node must have
`parent == null` and `next_sibling == null` and belong to no root or child list
in any forest.

`Linked.remove(item)` requires an item in its recorded parent's child list or,
for a parentless item, in the receiving forest's root list.

`Linked.remove(item)` clears `parent` and `next_sibling` but retains children,
as in the dense variants. Removing an object does not destroy it.

`Linked.firstRoot()` and `Linked.lastRoot()` return `?*const T`.
`Linked.firstRootMut()` and `Linked.lastRootMut()` return `?*T`.
The type operations `Linked.parent()`, `Linked.firstChild()`,
`Linked.lastChild()`, and `Linked.nextSibling()` have corresponding `Mut`
operations. They return borrowed object pointers or `null`.
Topology changes can change relationships, but do not move the objects or
extend their lifetime. `Linked.isEmpty()` tests only the root list.

## Clearing and diagnostics

`Dense.clearRetainingCapacity()` clears all links and roots, including detached
subtrees, without changing capacity or borrowed-storage identity. Existing
identifiers retain their indices. All topology relationships are discarded.
Payloads remain under caller control.

`Dense.assertValid()` checks identifier bounds, sibling lists, and parent links.

## Costs

Let `C` be dense capacity, `R` the root-list length, and `S` the source-list
length for removal.

| Operation | Time |
|---|---|
| Construction or clearing of dense storage | O(C) |
| Dense queries, linked accessors, `Linked.init()` | O(1) |
| Dense append | O(R) worst case for membership checking. O(1) when the child's parent or sibling already proves membership |
| Linked append | O(1) |
| Removal | O(S) |
| `Dense.assertValid()` | O(C + traversed sibling links) |

Storage is O(C) for dense links and O(1) per embedded linked node.

## References

- [Forests](../../../src/graph/forest.zig)
