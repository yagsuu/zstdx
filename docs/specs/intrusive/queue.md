# Intrusive queue

Status: Approved.

`stdx.intrusive.Queue(T, field)` is a caller-node-backed FIFO queue. It stores queue membership in a `stdx.intrusive.List.SinglyLinkedNode` field embedded in each caller-owned object.

## What this spec is

This specification defines `intrusive.Queue(T, field)`, its FIFO endpoint and mutation operations, its node-membership rules, and the required verification.

## What this spec is not

This specification does not define `intrusive.List`, `intrusive.Stack`, `intrusive.Deque`, or `intrusive.FreeList`; a `QueueNode` type; removal from the queue interior; capacity or full-queue policy; allocation policy for parent objects; synchronization; or ABI, wire, or packed-layout guarantees for parent objects.

## Terminology

- **selected node**: The `List.SinglyLinkedNode` field named by `field`.
- **detached**: A selected node whose `next` field is `null`.
- **queued**: A parent object reachable from `head` through selected-node `next` links.

## Public namespace and source ownership

The public path is `stdx.intrusive.Queue`. `src/intrusive.zig` re-exports `Queue` from `src/intrusive/queue.zig`. Required tests are in `test/intrusive/queue_test.zig`.

## Cross-spec relationships

`Queue` depends on `intrusive.List.SinglyLinkedNode` for its selected node. The queue does not own list operations or another intrusive primitive's membership chain. A parent object MAY participate in independent intrusive chains only when each chain uses a distinct embedded node field.

## Data structures and representation

The returned value has `head` and `tail` endpoint pointers. `head` identifies the oldest queued object and `tail` identifies the newest queued object. The queue stores no count, backing storage, or parent object.

## Global invariants

- A valid queue satisfies `head == null` if and only if `tail == null`.
- In a non-empty valid queue, `tail` is reachable from `head` through selected-node `next` links, and `tail`'s selected-node `next` field is `null`.
- No cycle is reachable from `head` in a valid queue.
- Every queued object has exactly one predecessor relationship in this queue, except `head`, which has none.
- The queue owns only endpoint pointers and topology. The caller owns every parent object and MUST keep a queued object alive until the object is detached and until all borrowed pointers to it are no longer used.
- The queue MUST NOT allocate, free, move, copy, destroy, zero, poison, or otherwise manage parent objects.
- The caller MUST NOT move a queued parent object. The caller MUST NOT mutate a selected node while it is queued except through this queue.
- The caller MUST use one authoritative mutable `Queue` value for each membership chain. Copying a queue copies endpoint pointers, not membership; divergent mutable copies are outside this contract.
- All public operations are non-thread-safe. Concurrent access requires caller-owned external synchronization.

## API

```zig
pub fn Queue(comptime T: type, comptime node_field: []const u8) type;

pub const Self = struct {
    head: ?*T = null,
    tail: ?*T = null,

    pub fn init() Self;
    pub fn isEmpty(self: *const Self) bool;

    pub fn front(self: *Self) ?*T;
    pub fn constFront(self: *const Self) ?*const T;
    pub fn back(self: *Self) ?*T;
    pub fn constBack(self: *const Self) ?*const T;

    pub fn pushBack(self: *Self, item: *T) void;
    pub fn popFront(self: *Self) ?*T;
    pub fn clear(self: *Self) void;
    pub fn assertValid(self: *const Self) void;
};
```

There is no `len`, `capacity`, `remaining`, `isFull`, `pushFront`, `popBack`, `peek`, `enqueue`, `dequeue`, `remove`, iterator, or backing-storage API.

## Type and node-field contract

`Queue(T, field)` requires `field` to name an addressable `List.SinglyLinkedNode` field in `T`. Invalid field names, wrong node types, non-addressable fields, and incompatible packed layouts MUST produce compile errors.

Before its first insertion, the caller MUST initialize the selected node to `.{}`. Before `pushBack(item)`, the caller MUST ensure that `item`'s selected node is detached. The caller MUST NOT insert a selected node that is queued by this or another intrusive object. A violation is a programmer error; the implementation MAY assert it and does not provide runtime owner tracking.

## Operations

### Construction and access

`init()` and `.{}` create an empty queue with `head = null` and `tail = null`. `isEmpty()` returns `head == null`.

`front()` returns a borrowed pointer to the oldest queued object, or `null` when the queue is empty. `back()` returns a borrowed pointer to the newest queued object, or `null` when the queue is empty. `constFront()` and `constBack()` return read-only equivalents. Access operations do not mutate the queue. Returned pointers borrow caller-owned parent objects and remain subject to the caller's lifetime obligations.

### `pushBack`

The caller MUST provide a detached selected node. `pushBack(item)` appends `item` after the current tail. For an empty queue, it sets both endpoints to `item`. For a non-empty queue, it changes the old tail's successor to `item` and sets `tail` to `item`. The operation preserves FIFO order and runs in O(1) time.

### `popFront`

`popFront()` returns `null` without mutation when the queue is empty. Otherwise, it removes and returns the oldest queued object, advances `head`, and sets `tail` to `null` when the removed object was the sole object. Before return, it MUST detach the removed object's selected node. Remaining objects retain their addresses and FIFO order. The operation runs in O(1) time.

### `clear`

`clear()` traverses the queue in FIFO order, detaches every selected node, and sets both endpoints to `null`. It does not destroy, free, move, zero, or poison parent objects. `clear()` runs in O(n) time for `n` queued objects. There is no O(1) reset operation, `clearRetainingCapacity`, `clearAndFree`, or `deinit`.

### `assertValid`

`assertValid()` verifies topology reachable from this queue's endpoints: endpoint symmetry, tail reachability, a null terminal link, and absence of a reachable cycle. It runs in O(n) time and does not mutate the queue. It does not prove exclusive node ownership, detect every double insertion, or make wrong-queue use safe.

## Implementation constraints

The implementation MAY reuse internal list helpers, but the public type MUST NOT expose an inner `List.SinglyLinked` value. The implementation MUST NOT maintain a count. Every operation performs no heap allocation, waiting, hidden global access, atomics, barriers, volatile access, target probing, syscalls, locks, callbacks, or I/O.

## Testing

Tests MUST construct empty, one-item, and multi-item queues and verify `init()` equivalence, null results for empty access and removal, FIFO endpoint observations, FIFO removal order, and the transition from one item to empty. These tests prove the observable endpoint and ordering contract at its empty and singleton boundaries.

Tests MUST execute each mutating operation (`pushBack`, `popFront`, and `clear`) and call `assertValid()` after each successful mutation. Tests MUST verify that `popFront` and `clear` detach selected nodes and that detached nodes can be inserted again. These invariant tests prove that mutations preserve endpoint symmetry, reachability, terminal-link, and acyclic-topology requirements while restoring detached membership.

Tests MUST verify independent membership through distinct embedded node fields and stable parent-object addresses. When the test harness supports expected compile failures, it MUST reject an incompatible node field. A corruption test MAY inject reachable cycles and inconsistent endpoints when the harness supports assertion capture. These mutation and corruption methods verify the invariants the checker claims to detect; they do not claim exclusive-ownership detection.
