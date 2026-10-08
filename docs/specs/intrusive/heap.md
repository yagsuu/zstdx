# Intrusive Heap

Status: Approved.

`stdx.intrusive.heap.Heap(T, field, less)` is an allocation-free min-heap over caller-owned objects with an embedded `stdx.intrusive.heap.Node` selected by field name.

## Data structures and representation

The heap MUST use a linked complete binary tree and maintain an exact `usize` item count. Each object supplies the selected `Node`.

```zig
pub const Node = struct {
    parent: ?*Node = null,
    left: ?*Node = null,
    right: ?*Node = null,
    linked: bool = false,
};
```

A detached node has null links and `linked == false`. Every attached node has `linked == true`, including a singleton root. The root has `parent == null`. Each child has a reciprocal parent link.

`field` MUST name an addressable `Node` field in `T`. The factory MUST reject invalid field names, incompatible node types, and non-addressable layouts at compile time.

## Global invariants

- The heap MUST contain each attached node exactly once.
- The heap MUST preserve complete-tree shape and reciprocal links.
- The stored count MUST equal the number of attached objects.
- For each parent/child pair, `less(child, parent)` MUST be false, except during the caller's change/update sequence below.
- The heap MUST NOT allocate, free, move, copy, or destroy parent objects.
- The caller MUST keep attached objects alive and at stable addresses.
- The caller MUST modify attached node fields only through heap operations.
- Each selected node MUST belong to at most one heap. Distinct node fields MAY support independent memberships.
- The caller MUST maintain one authoritative mutable heap value. Copying a non-empty heap does not create independent membership.
- The caller MUST externally synchronize concurrent access that includes mutation of the heap or comparator-visible object fields.

`less` MUST define a strict weak ordering. The comparator MUST NOT mutate objects or re-enter the heap. The caller MUST keep the ordering relation unchanged while objects are attached, except for one object's change/update sequence. Equal-priority removal order is unspecified.

## API

```zig
pub fn Heap(
    comptime T: type,
    comptime field: []const u8,
    comptime less: fn (lhs: *const T, rhs: *const T) bool,
) type;
```

Methods on the returned type:

```zig
pub fn init() Self;
pub fn len(self: *const Self) usize;
pub fn isEmpty(self: *const Self) bool;

pub fn peek(self: *const Self) ?*const T;
pub fn peekMut(self: *Self) ?*T;

pub fn insert(self: *Self, item: *T) void;
pub fn pop(self: *Self) ?*T;
pub fn remove(self: *Self, item: *T) void;
pub fn update(self: *Self, item: *T) void;

pub fn clear(self: *Self) void;
pub fn assertValid(self: *const Self) void;
```

## Construction and inspection

`init()` and `.{}` MUST produce an empty heap. The caller MUST initialize each selected node to `.{}` before its first insertion.

`len()` MUST return the exact count. `isEmpty()` MUST return whether the count is zero.

`peek()` and `peekMut()` MUST return a borrowed pointer to a minimum item, or `null` when empty. Neither operation changes the heap. Heap maintenance MUST preserve object addresses; returned pointers remain subject to the caller's object lifetime. Removal ends membership, not object lifetime.

## `insert`

The caller MUST provide a detached node. `insert()` MUST attach the object, increment the count, and restore heap order.

## `pop`

On an empty heap, `pop()` MUST return `null` without mutation. Otherwise, it MUST remove and return a minimum item, decrement the count, restore heap order, and reset the removed node to `.{}`.

## `remove`

The caller MUST provide an object attached to this heap. `remove()` MUST remove that object, decrement the count, restore heap order, and reset its node to `.{}`.

## `update`

The caller MUST provide an object attached to this heap. After changing comparator-visible fields in that object, the caller MUST invoke `update(item)` before another heap operation. The caller MUST leave other objects' comparator-visible fields unchanged during this sequence.

`update()` MUST restore order for a priority increase, decrease, or unchanged priority. It MUST preserve membership and count.

## `clear`

`clear()` MUST reset every attached node to `.{}` and leave the heap empty. It MUST NOT evaluate `less`. Pop, removal, and clear MUST permit subsequent reinsertion of detached nodes.

## `assertValid`

`assertValid()` MUST check complete-tree shape, reciprocal links, attached-node membership state, count, and heap order without mutation.

## Implementation constraints

When `core.debug.checksEnabled()` is true, insertion MUST assert detached state, and removal/update MUST assert membership in the receiving heap. Duplicate insertion and wrong-heap removal/update are caller-contract violations.

| Operations | Worst-case time |
| --- | --- |
| Construction, count, empty check, peek | O(1) |
| Insert, pop, remove, update | O(log n) |
| Clear, validation | O(n) |

Operations MUST use O(1) auxiliary storage without allocation or recursion. The heap MUST NOT synchronize internally. Comparator execution time is excluded from the operation bounds; comparison counts MUST satisfy the stated bounds. Construction, count, empty checks, peek, and clear MUST NOT invoke the comparator.

## Testing

Required tests MUST cover:

- Empty, singleton, and multi-item transitions.
- Ascending, descending, equal-priority, and reversed-comparator ordering.
- Root, interior, and last-node removal.
- Priority increases, decreases, and unchanged priorities.
- Detach/reinsert after pop, removal, and clear.
- Independent memberships through distinct fields.
- Stable object addresses across heap maintenance.
- Mixed operations against a reference model, with validation after mutations.
- Const inspection and explicit mutable inspection.
