# Intrusive linked lists

Status: Approved.

`stdx.intrusive.List.SinglyLinked(T, field)` and `stdx.intrusive.List.DoublyLinked(T, field)` are caller-node-backed linked lists. They store membership in an embedded node field of each caller-owned object.

## What this spec is

This specification defines `intrusive.List`, its node types, parent-object recovery, endpoint and traversal access, insertion, removal, clearing, topology validation, and required verification.

## What this spec is not

This specification does not define `intrusive.Queue`, `intrusive.Stack`, `intrusive.Deque`, or `intrusive.FreeList`; allocation of parent objects; automatic owner tracking; sorted or unique insertion; synchronization; or ABI, wire, or packed-layout guarantees for parent objects.

## Terminology

- **selected node**: The embedded node field named by `field`.
- **detached singly linked node**: A `List.SinglyLinkedNode` whose `next` field is `null`.
- **detached doubly linked node**: A `List.DoublyLinkedNode` whose `prev` and `next` fields are `null`.
- **linked**: A parent object reachable from `head` through selected-node `next` links.

## Public namespace and source ownership

The public path is `stdx.intrusive.List`. `src/intrusive.zig` re-exports `List` from `src/intrusive/list.zig`. Required tests are in `test/intrusive/list_test.zig`.

## Data structures and representation

`SinglyLinked` and `DoublyLinked` values each have `head` and `tail` endpoint pointers. A list stores no count, backing storage, or parent object. `SinglyLinkedNode` is `std.SinglyLinkedList.Node`; `DoublyLinkedNode` is `std.DoublyLinkedList.Node`.

## Global invariants

- A valid list satisfies `head == null` if and only if `tail == null`.
- In a non-empty singly linked list, `tail` is reachable from `head`, `tail`'s selected-node `next` field is `null`, and no cycle is reachable from `head`.
- In a non-empty doubly linked list, `head`'s selected-node `prev` field is `null`, `tail`'s selected-node `next` field is `null`, forward and backward links are symmetric, and no cycle is reachable from `head`.
- The list owns only endpoint pointers and topology. The caller owns every parent object and MUST keep a linked object alive until the object is detached and until all borrowed pointers to it are no longer used.
- The list MUST NOT allocate, free, move, copy, destroy, zero, poison, or otherwise manage parent objects.
- The caller MUST NOT move a linked parent object. The caller MUST NOT mutate a selected node while it is linked except through its list.
- The caller MUST use one authoritative mutable list value for each membership chain. Copying a list copies endpoint pointers, not membership; divergent mutable copies are outside this contract.
- A parent object MAY participate in independent intrusive chains only when each chain uses a distinct embedded node field.
- All public operations are non-thread-safe. Concurrent access requires caller-owned external synchronization.

## API

```zig
pub const List = struct {
    pub const SinglyLinkedNode = std.SinglyLinkedList.Node;
    pub const DoublyLinkedNode = std.DoublyLinkedList.Node;

    pub fn SinglyLinked(comptime T: type, comptime node_field: []const u8) type;
    pub fn DoublyLinked(comptime T: type, comptime node_field: []const u8) type;
};
```

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

There is no `len`, `capacity`, `remaining`, `isFull`, `asSlice`, iterator, sorted-insertion, or backing-storage API.

## Type and node-field contract

`SinglyLinked(T, field)` requires `field` to name an addressable `List.SinglyLinkedNode` field in `T`. `DoublyLinked(T, field)` requires an addressable `List.DoublyLinkedNode` field in `T`. Invalid field names, wrong node types, non-addressable fields, and incompatible packed layouts MUST produce compile errors.

Before first insertion, the caller MUST initialize a selected node to `.{}`. Before an insertion, the caller MUST provide a detached selected node. The caller MUST NOT insert a selected node that is linked by this or another intrusive object. A violation is a programmer error; the implementation MAY assert it and does not provide runtime owner tracking.

## Operations

### Construction, endpoints, and traversal

`init()` and `.{}` create an empty list with both endpoints `null`. `isEmpty()` returns `head == null`.

`front()` and `back()` return borrowed pointers to the endpoint objects, or `null` when empty. `constFront()` and `constBack()` return read-only equivalents. These operations do not mutate the list.

`next(item)` returns the parent object represented by `item`'s selected-node `next` link, or `null` if that link is null. `constNext()` returns the read-only equivalent. `DoublyLinked.previous(item)` and `constPrevious()` provide the corresponding `prev` traversal. The caller MUST use traversal helpers only for an object linked in the expected list or for a detached node with null links. Returned pointers borrow caller-owned parent objects.

### Singly linked insertion and removal

`pushFront(item)` inserts `item` before the old head. `pushBack(item)` inserts `item` after the old tail. Both set both endpoints to `item` when the list was empty. `insertAfter(previous, item)` inserts `item` immediately after `previous`; the caller MUST provide a `previous` object linked in this list. If `previous` was the tail, `item` becomes the tail. These operations run in O(1) time and preserve the relative order of existing objects.

`popFront()` returns `null` without mutation when the list is empty. Otherwise, it removes and returns the head, updates both endpoints when the removed object was the only object, and detaches the removed selected node before return. It runs in O(1) time.

`tryRemove(item)` searches from `head`. If it finds `item`, it unlinks and detaches `item`, updates affected endpoints, preserves the relative order of remaining objects, and returns `true`. If it does not find `item`, it returns `false` and MUST NOT mutate the list or `item`. It runs in O(n) time.

### Doubly linked insertion and removal

`pushFront(item)` inserts `item` before the old head. `pushBack(item)` inserts `item` after the old tail. Both set both endpoints to `item` when the list was empty. `insertBefore(next_item, item)` inserts `item` immediately before `next_item`; the caller MUST provide a `next_item` object linked in this list. `insertAfter(previous_item, item)` inserts `item` immediately after `previous_item`; the caller MUST provide a `previous_item` object linked in this list. These operations update affected neighbors and endpoints, run in O(1) time, and preserve the relative order of existing objects.

`popFront()` and `popBack()` return `null` without mutation when the list is empty. Otherwise, each removes and returns its respective endpoint and detaches the selected node before return. Each runs in O(1) time.

`remove(item)` unlinks `item` in O(1) time. The caller MUST provide an `item` linked in this list. Before return, `remove` MUST set both fields of the removed selected node to `null`. It preserves the relative order and addresses of remaining objects.

### `clear`

`clear()` traverses the list, detaches every selected node, and sets both endpoints to `null`. It does not destroy, free, move, zero, or poison parent objects. It runs in O(n) time. There is no O(1) reset operation, `clearRetainingCapacity`, `clearAndFree`, or `deinit`.

### `assertValid`

`SinglyLinked.assertValid()` verifies endpoint symmetry, tail reachability, a null terminal link, and no reachable cycle. `DoublyLinked.assertValid()` additionally verifies null outer links and forward/backward link symmetry. Each runs in O(n) time, does not mutate the list, and does not prove exclusive node ownership or make wrong-list removal safe.

## Implementation constraints

The implementation MUST NOT maintain a count or embed another `List.SinglyLinked`, `Queue`, or `Stack` value in public `Self`. `clear()` MUST detach every selected node; it MUST NOT only discard endpoints. Removal operations MUST detach every link of their removed node before return. Every operation performs no heap allocation, waiting, hidden global access, atomics, barriers, volatile access, target probing, syscalls, locks, callbacks, or I/O.

## Testing

Tests MUST construct empty, one-item, and multi-item singly and doubly linked lists. Tests MUST verify initialization, null endpoints and removal on empty lists, insertion at endpoints and interior anchors, forward and reverse traversal where applicable, endpoint transitions, order preservation, and the no-mutation result of a failed `tryRemove`. These boundary and model tests prove the public ordering, traversal, and error contracts.

Tests MUST execute every mutating operation and call `assertValid()` after each successful mutation. Tests MUST verify that every pop, successful removal, and clear detaches the selected node and permits reinsertion. These invariant tests prove that list mutations preserve endpoint, terminal-link, and link-symmetry requirements while restoring detached membership.

Tests MUST verify distinct-field multi-membership and stable parent-object addresses. When the test harness supports expected compile failures, it MUST reject an incompatible node field. A corruption test MAY inject reachable cycles, inconsistent endpoints, and broken forward/backward symmetry when the harness supports assertion capture. These mutation and corruption methods verify the invariants each validator claims to check; they do not claim exclusive-ownership detection.
