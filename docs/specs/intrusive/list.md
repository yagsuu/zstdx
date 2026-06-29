# Intrusive linked lists

Status: Approved.

`stdx.intrusive.List.SinglyLinked(T, field)` and
`stdx.intrusive.List.DoublyLinked(T, field)` are caller-node-backed linked
lists. They never allocate, never move parent objects, and store membership in an
embedded node field owned by the caller's object.

## Owned scope

This spec owns:

- `intrusive.List`;
- `intrusive.List.SinglyLinkedNode`;
- `intrusive.List.DoublyLinkedNode`;
- `intrusive.List.SinglyLinked(T, field)`;
- `intrusive.List.DoublyLinked(T, field)`;
- parent-object recovery from an embedded node field;
- local list topology invariants;
- endpoint access, insertion, removal, clearing, and traversal semantics;
- allocation, waiting, invalidation, concurrency, and ordering behavior;
- required tests.

This spec does not own:

- `intrusive.Queue`, `intrusive.Stack`, `intrusive.Deque`, or
  `intrusive.FreeList`;
- hash-list, tree, heap, interval-tree, or LRU policy;
- managed or unmanaged heap allocation;
- owner pointers, generation counters, handles, tombstones, or poisoning;
- automatic node-state tracking for double-insert or double-remove detection;
- sorted insertion, key extraction, comparison callbacks, or uniqueness checks;
- lock-free, atomic, SPSC, MPSC, MPMC, or externally locked behavior;
- ABI, wire, or packed layout guarantees for parent objects.

## Public namespace

`List` lives under `stdx.intrusive`:

```zig
stdx.intrusive.List
```

It is not root-promoted. Callers use the intrusive namespace explicitly.

Source ownership:

```text
src/intrusive.zig
src/intrusive/list.zig
test/intrusive/list_test.zig
```

`src/intrusive.zig` re-exports:

```zig
pub const list = @import("intrusive/list.zig");

pub const List = list.List;
```

`src/stdx.zig` re-exports the namespace only:

```zig
pub const intrusive = @import("intrusive.zig");
```

There is no `stdx.List.SinglyLinked`, `stdx.SinglyLinkedList`, or
`stdx.DoublyLinkedList` root alias.

## Approved API

```zig
pub const List = struct {
    pub const SinglyLinkedNode = struct {
        next: ?*@This() = null,
    };

    pub const DoublyLinkedNode = struct {
        prev: ?*@This() = null,
        next: ?*@This() = null,
    };

    pub fn SinglyLinked(comptime T: type, comptime node_field: []const u8) type;
    pub fn DoublyLinked(comptime T: type, comptime node_field: []const u8) type;
};
```

Returned `SinglyLinked` type:

```zig
pub const Self = struct {
    head: ?*T = null,
    tail: ?*T = null,

    pub fn init() Self;

    pub fn isEmpty(self: *const Self) bool;

    pub fn front(self: *Self) ?*T;
    pub fn constFront(self: *const Self) ?*const T;
    pub fn back(self: *Self) ?*T;
    pub fn constBack(self: *const Self) ?*const T;

    pub fn next(item: *T) ?*T;
    pub fn constNext(item: *const T) ?*const T;

    pub fn pushFront(self: *Self, item: *T) void;
    pub fn pushBack(self: *Self, item: *T) void;
    pub fn insertAfter(self: *Self, previous: *T, item: *T) void;

    pub fn popFront(self: *Self) ?*T;
    pub fn tryRemove(self: *Self, item: *T) bool;

    pub fn clear(self: *Self) void;

    pub fn assertValid(self: *const Self) void;
};
```

Returned `DoublyLinked` type:

```zig
pub const Self = struct {
    head: ?*T = null,
    tail: ?*T = null,

    pub fn init() Self;

    pub fn isEmpty(self: *const Self) bool;

    pub fn front(self: *Self) ?*T;
    pub fn constFront(self: *const Self) ?*const T;
    pub fn back(self: *Self) ?*T;
    pub fn constBack(self: *const Self) ?*const T;

    pub fn next(item: *T) ?*T;
    pub fn constNext(item: *const T) ?*const T;
    pub fn previous(item: *T) ?*T;
    pub fn constPrevious(item: *const T) ?*const T;

    pub fn pushFront(self: *Self, item: *T) void;
    pub fn pushBack(self: *Self, item: *T) void;
    pub fn insertBefore(self: *Self, next_item: *T, item: *T) void;
    pub fn insertAfter(self: *Self, previous_item: *T, item: *T) void;

    pub fn popFront(self: *Self) ?*T;
    pub fn popBack(self: *Self) ?*T;
    pub fn remove(self: *Self, item: *T) void;

    pub fn clear(self: *Self) void;

    pub fn assertValid(self: *const Self) void;
};
```

There is no `len`, `capacity`, `remaining`, `isFull`, `asSlice`, `peek`,
`enqueue`, `dequeue`, `orderedRemove`, `swapRemove`, `append`, `prepend`,
`popFirst`, `popLast`, `first`, or `last` alias.

## Type and node-field contract

`SinglyLinked(T, field)` requires `field` to name an addressable field of type
`List.SinglyLinkedNode` within `T`.

`DoublyLinked(T, field)` requires `field` to name an addressable field of type
`List.DoublyLinkedNode` within `T`.

Invalid field names, wrong node types, non-addressable fields, and incompatible
packed layouts are compile errors where practical.

The node field stores list membership. Each independent intrusive membership
requires a distinct embedded node field.

Example:

```zig
const Task = struct {
    id: u32,
    ready_node: stdx.intrusive.List.SinglyLinkedNode = .{},
    all_node: stdx.intrusive.List.DoublyLinkedNode = .{},
};

const ReadyList = stdx.intrusive.List.SinglyLinked(Task, "ready_node");
const AllList = stdx.intrusive.List.DoublyLinked(Task, "all_node");

var ready = ReadyList.init();
var all = AllList.init();
var task: Task = .{ .id = 1 };

ready.pushBack(&task);
all.pushBack(&task);
```

A node must be initialized to `.{}` before its first insertion. Insert operations
require the selected node to be detached. Pop, remove, and clear operations
detach nodes before returning.

## Ownership and lifetime

The list value owns only endpoint pointers and structural invariants. It does not
own, allocate, free, move, copy, or destroy parent objects.

The caller owns each parent object and must keep it alive while it is linked and
while any pointer returned by the list is used.

Moving a list value does not move parent objects. Moving a parent object while it
is linked is outside the contract because embedded node pointers in neighboring
objects would still point at the old address.

Copying a list value copies endpoint pointers, not membership. Divergent mutable
copies over the same nodes are outside this primitive's contract. Use one
authoritative mutable list value for each intrusive membership chain.

External mutation of node fields while linked is outside the contract unless the
mutation preserves every invariant owned by the list.

## Construction

`init()` is equivalent to `.{}`. Both create an empty list with
`head = null` and `tail = null`.

`isEmpty()` returns `head == null`. A valid list satisfies `head == null` iff
`tail == null`.

## Endpoint and traversal access

`front()` returns `head`, or `null` when empty.

`constFront()` returns the read-only equivalent.

`back()` returns `tail`, or `null` when empty.

`constBack()` returns the read-only equivalent.

`next(item)` returns the next parent object stored in `item`'s embedded node, or
`null` when `item` has no next object.

`constNext(item)` returns the read-only equivalent.

`DoublyLinked.previous(item)` returns the previous parent object stored in
`item`'s embedded node, or `null` when `item` has no previous object.

`constPrevious(item)` returns the read-only equivalent.

Calling traversal helpers on an object whose selected node is not linked in the
expected list is outside the contract unless the node is detached and all links
are null.

## Singly linked insertion

`pushFront(item)` inserts `item` before the current head. When the list is empty,
it sets both `head` and `tail` to `item`.

`pushBack(item)` inserts `item` after the current tail in O(1). When the list is
empty, it sets both `head` and `tail` to `item`.

`insertAfter(previous, item)` inserts `item` immediately after `previous`.
`previous` must be linked in this list. If `previous` is the tail, `item` becomes
the new tail.

All singly linked insertion operations require `item`'s selected node to be
detached.

## Singly linked removal

`popFront()` removes and returns the head object. It returns `null` when empty.
When the removed object was the tail, the list becomes empty.

`tryRemove(item)` scans from `head`. If `item` is found, it unlinks `item`, updates
`head` and `tail` as needed, detaches `item`'s selected node, and returns `true`.
If `item` is not found, it leaves the list unchanged and returns `false`. The
`Try` prefix marks the scan-and-report contract; `DoublyLinked.remove` is the
O(1) precondition counterpart.

Singly linked removal preserves the relative order of remaining objects.

## Doubly linked insertion

`pushFront(item)` inserts `item` before the current head. When the list is empty,
it sets both `head` and `tail` to `item`.

`pushBack(item)` inserts `item` after the current tail. When the list is empty, it
sets both `head` and `tail` to `item`.

`insertBefore(next_item, item)` inserts `item` immediately before `next_item`.
`next_item` must be linked in this list. If `next_item` is the head, `item`
becomes the new head.

`insertAfter(previous_item, item)` inserts `item` immediately after
`previous_item`. `previous_item` must be linked in this list. If `previous_item`
is the tail, `item` becomes the new tail.

All doubly linked insertion operations require `item`'s selected node to be
detached.

## Doubly linked removal

`popFront()` removes and returns the head object. It returns `null` when empty.
When the removed object was the tail, the list becomes empty.

`popBack()` removes and returns the tail object. It returns `null` when empty.
When the removed object was the head, the list becomes empty.

`remove(item)` unlinks `item` in O(1). `item` must be linked in this list. The
removed object's selected node is detached before return.

Doubly linked removal preserves the relative order of remaining objects.

## Clearing

`clear()` walks the list, detaches every linked node, and then sets
`head = null` and `tail = null`.

`clear()` does not destroy, zero, free, poison, or move parent objects.

There is no `clearRetainingCapacity` because intrusive lists have no capacity and
own no backing storage. There is no `clearAndFree` or `deinit` because intrusive
lists own no resources.

## Invalidation and ordering

Intrusive lists do not invalidate parent-object pointers by moving objects. They
only change list membership and link-neighbor relationships.

Insertion changes endpoint pointers when inserting before the old head or after
the old tail. It changes the predecessor or successor relationship at the
insertion point.

Removing an object invalidates that object's list membership and its former
neighbor relationships. Remaining objects stay at the same addresses.

`clear()` invalidates every membership in the list and detaches every node.

Iteration order is link order from `front()` through repeated `next()` calls.
`DoublyLinked` reverse order is link order from `back()` through repeated
`previous()` calls.

## Behavior contract

Singly linked operations:

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `SinglyLinked` | never | never | comptime | none | type factory | none |
| `init` | never | never | O(1) | none | caller-owned value | empty |
| `isEmpty` | never | never | O(1) | none | caller-owned value | none |
| endpoint access | never | never | O(1) | none | caller-owned value | link order |
| `next` | never | never | O(1) | none | caller-owned value | link order |
| `pushFront` | never | never | O(1) | head endpoint | caller-owned value | inserts at head |
| `pushBack` | never | never | O(1) | tail endpoint | caller-owned value | inserts at tail |
| `insertAfter` | never | never | O(1) | successor of anchor | caller-owned value | inserts after anchor |
| `popFront` | never | never | O(1) | removed head | caller-owned value | removes head |
| `tryRemove` | never | never | O(n) | removed item | caller-owned value | preserves order |
| `clear` | never | never | O(n) | all memberships | caller-owned value | empty |
| `assertValid` | never | never | O(n) | none | caller-owned value | verifies topology |

Doubly linked operations:

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `DoublyLinked` | never | never | comptime | none | type factory | none |
| `init` | never | never | O(1) | none | caller-owned value | empty |
| `isEmpty` | never | never | O(1) | none | caller-owned value | none |
| endpoint access | never | never | O(1) | none | caller-owned value | link order |
| `next` / `previous` | never | never | O(1) | none | caller-owned value | link order |
| `pushFront` | never | never | O(1) | head endpoint | caller-owned value | inserts at head |
| `pushBack` | never | never | O(1) | tail endpoint | caller-owned value | inserts at tail |
| `insertBefore` | never | never | O(1) | predecessor of anchor | caller-owned value | inserts before anchor |
| `insertAfter` | never | never | O(1) | successor of anchor | caller-owned value | inserts after anchor |
| `popFront` | never | never | O(1) | removed head | caller-owned value | removes head |
| `popBack` | never | never | O(1) | removed tail | caller-owned value | removes tail |
| `remove` | never | never | O(1) | removed item | caller-owned value | preserves order |
| `clear` | never | never | O(n) | all memberships | caller-owned value | empty |
| `assertValid` | never | never | O(n) | none | caller-owned value | verifies topology |

These operations perform no heap allocation, waiting, hidden global access,
atomics, barriers, volatile access, target probing, syscalls, locks, or I/O.

## Error behavior

The public API has no error set.

- empty endpoint access returns `null`;
- empty pops return `null`;
- `SinglyLinked.tryRemove(item)` returns `false` when `item` is not found;
- invalid type and field combinations are compile errors where practical;
- double insert is a programmer error;
- removing a node through the wrong list is a programmer error;
- using an insertion anchor that is not linked in the list is a programmer error;
- externally corrupted links are a programmer error.

Operations with programmer-error preconditions may assert those preconditions
when practical, but the spec does not require runtime owner tracking.

## Implementation constraints

- intrusive list values do not maintain a `count`. Operations that would require a count must not exist on the public surface.
- intrusive list values do not embed another `List.SinglyLinked`, `Queue`, or `Stack` value.
- `clear()` must detach every node's selected field; dropping endpoint pointers without detaching is prohibited.
- `popFront`, `popBack`, `tryRemove`, and `remove` must detach the returned node's selected `next` and `prev` fields to `null` before returning.
- the public `Self` value does not expose anything beyond endpoints and the operations declared above.

## Concurrency

Intrusive lists are not thread-safe. Concurrent access from multiple threads requires caller-owned external synchronization. Immutable reads through an immutable list value require no synchronization beyond ordinary Zig aliasing rules.

## Iteration with removal

`tryRemove` and `remove` invalidate the removed object's link neighbors. A caller iterating via `next()`/`previous()` MUST cache the next pointer before calling `tryRemove`/`remove` on the current item:

```zig
var it: ?*T = list.front();
while (it) |item| {
    const next_item = ReadyList.next(item);
    if (shouldRemove(item)) _ = list.tryRemove(item);
    it = next_item;
}
```

Alternatively, callers may drain via destructive `while (list.popFront()) |item| { ... }` iteration when relative order is not required.

## Shared node-type aliasing

`List.SinglyLinkedNode` is the embedded node type for `List.SinglyLinked`, `Queue`, and `Stack`. The comptime type check is identical across the three primitives. The same physical `SinglyLinkedNode` field MUST NOT be wired into more than one `List.SinglyLinked`, `Queue`, or `Stack` instance simultaneously. Comptime type checking is not sufficient to prevent this; reuse is a programmer-error precondition and may be detected by `assertValid` in some configurations but is not guaranteed.

## Debug assertion behavior

`assertValid()` checks local topology reachable from this list's endpoints. It
does not prove node ownership, detect all double inserts, or make removal through
the wrong list safe.

`SinglyLinked.assertValid()` checks where practical:

- `head == null` iff `tail == null`;
- if non-empty, `tail` is reachable from `head`;
- if non-empty, `tail.next == null`;
- no cycle is reachable from `head`.

`DoublyLinked.assertValid()` checks where practical:

- `head == null` iff `tail == null`;
- if non-empty, `head.prev == null`;
- if non-empty, `tail.next == null`;
- every forward link's `next.prev` points back to the current node;
- every backward link's `prev.next` points forward to the current node;
- no cycle is reachable from `head`.

Mutating operations may call `assertValid()` before and after mutation when
`core.checksEnabled(opts.safety)` or an equivalent module safety option requires
runtime invariant checks.

## Examples

Singly linked ready list:

```zig
const Thread = struct {
    id: u32,
    ready_node: stdx.intrusive.List.SinglyLinkedNode = .{},
};

const ReadyList = stdx.intrusive.List.SinglyLinked(Thread, "ready_node");

var ready = ReadyList.init();
var thread_a: Thread = .{ .id = 1 };
var thread_b: Thread = .{ .id = 2 };

ready.pushBack(&thread_a);
ready.pushBack(&thread_b);

while (ready.popFront()) |thread| {
    consume(thread);
}
```

Doubly linked all-objects list:

```zig
const Device = struct {
    id: u32,
    all_node: stdx.intrusive.List.DoublyLinkedNode = .{},
};

const Devices = stdx.intrusive.List.DoublyLinked(Device, "all_node");

var devices = Devices.init();
var device: Device = .{ .id = 7 };

devices.pushBack(&device);
devices.remove(&device);
```

Multi-membership:

```zig
const Task = struct {
    id: u32,
    ready_node: stdx.intrusive.List.SinglyLinkedNode = .{},
    all_node: stdx.intrusive.List.DoublyLinkedNode = .{},
};

const Ready = stdx.intrusive.List.SinglyLinked(Task, "ready_node");
const All = stdx.intrusive.List.DoublyLinked(Task, "all_node");
```

## Required tests

Construction tests:

- empty singly linked list;
- empty doubly linked list;
- `init()` equals default initialization;
- endpoint access on empty lists returns `null`.

Singly linked tests:

- pushFront into empty list;
- pushBack into empty list;
- pushFront before existing head;
- pushBack after existing tail;
- insert after head, interior item, and tail;
- pop the only item;
- pop head from a multi-item list;
- remove head, interior item, and tail;
- `tryRemove` of a missing item returns `false` and preserves the list;
- reinsert an item after removal;
- clear empty, one-item, and multi-item lists;
- traversal with repeated `next()` observes link order.

Doubly linked tests:

- pushFront into empty list;
- pushBack into empty list;
- insert before head, interior item, and tail;
- insert after head, interior item, and tail;
- popFront from one-item and multi-item lists;
- popBack from one-item and multi-item lists;
- remove head, interior item, and tail;
- reinsert an item after removal;
- clear empty, one-item, and multi-item lists;
- forward traversal with repeated `next()` observes link order;
- reverse traversal with repeated `previous()` observes reverse link order.

Cross-cutting tests:

- multi-membership through distinct embedded node fields;
- parent object addresses stay stable across list operations;
- removed and cleared nodes are detached;
- `assertValid()` succeeds after every public mutation;
- structural corruption tests where practical for broken endpoint and link
  symmetry.

## Open questions

None.
