# Intrusive queue

Status: Approved.

`zstdx.intrusive.Queue(T, field)` is a caller-node-backed FIFO queue. It never
allocates, never moves parent objects, and stores membership in an embedded
`zstdx.intrusive.List.SinglyLinkedNode` field owned by the caller's object.

## Owned scope

This spec owns:

- `intrusive.Queue(T, field)`;
- FIFO endpoint semantics over caller-owned objects;
- queue use of `intrusive.List.SinglyLinkedNode` as the embedded node type;
- endpoint access, enqueue, dequeue, clearing, and topology validation;
- allocation, waiting, invalidation, concurrency, and ordering behavior;
- required tests.

This spec does not own:

- `intrusive.List`, `intrusive.Stack`, `intrusive.Deque`, or
  `intrusive.FreeList`;
- a distinct `QueueNode` type;
- arbitrary removal or cancellation from the middle of a queue;
- bounded capacity, full-state behavior, overwrite-on-full behavior, or
  drop-oldest policy;
- scalar-value queues, fixed rings, guest rings, or descriptor rings;
- priority queues, sorted insertion, key extraction, or uniqueness checks;
- managed or unmanaged heap allocation;
- worker wakeups, eventfds, locks, atomics, SPSC, MPSC, MPMC, or externally
  locked behavior;
- ABI, wire, or packed layout guarantees for parent objects.

## Public namespace

`Queue` lives under `zstdx.intrusive`:

```zig
zstdx.intrusive.Queue
```

It is not root-promoted. Callers use the intrusive namespace explicitly.

Source ownership:

```text
src/intrusive.zig
src/intrusive/queue.zig
test/intrusive/queue_test.zig
```

`src/intrusive.zig` re-exports:

```zig
pub const queue = @import("intrusive/queue.zig");

pub const Queue = queue.Queue;
```

`src/zstdx.zig` re-exports the namespace only:

```zig
pub const intrusive = @import("intrusive.zig");
```

There is no `zstdx.Queue`, `zstdx.QueueNode`, or
`zstdx.intrusive.QueueNode` alias.

## Approved API

```zig
pub fn Queue(comptime T: type, comptime node_field: []const u8) type;
```

Returned type:

```zig
pub const Self = struct {
    head: ?*T = null;
    tail: ?*T = null;

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

There is no `len`, `capacity`, `remaining`, `isFull`, `pushFront`, `popBack`,
`peek`, `enqueue`, `dequeue`, `remove`, `pushBackAssumeCapacity`,
`pushBackOverwriteOldest`, `asSlice`, or iterator API.

## Type and node-field contract

`Queue(T, field)` requires `field` to name an addressable field of type
`List.SinglyLinkedNode` within `T`.

Invalid field names, wrong node types, non-addressable fields, and incompatible
packed layouts are compile errors where practical.

The selected node field stores queue membership. Each independent intrusive
membership requires a distinct embedded node field.

Example:

```zig
const Task = struct {
    id: u32,
    ready_node: zstdx.intrusive.List.SinglyLinkedNode = .{},
    free_node: zstdx.intrusive.List.SinglyLinkedNode = .{},
};

const ReadyQueue = zstdx.intrusive.Queue(Task, "ready_node");
const FreeQueue = zstdx.intrusive.Queue(Task, "free_node");

var ready = ReadyQueue.init();
var free = FreeQueue.init();
var task: Task = .{ .id = 1 };

ready.pushBack(&task);
free.pushBack(&task);
```

A node must be initialized to `.{}` before its first insertion. `pushBack(item)`
requires the selected node to be detached. `popFront()` and `clear()` detach
nodes before returning.

## Ownership and lifetime

The queue value owns only endpoint pointers and structural invariants. It does
not own, allocate, free, move, copy, or destroy parent objects.

The caller owns each parent object and must keep it alive while it is queued and
while any pointer returned by the queue is used.

Moving a queue value does not move parent objects. Moving a parent object while
it is queued is outside the contract because embedded node pointers in other
objects may still point at the old address.

Copying a queue value copies endpoint pointers, not membership. Divergent
mutable copies over the same nodes are outside this primitive's contract. Use one
authoritative mutable queue value for each intrusive membership chain.

External mutation of node fields while queued is outside the contract unless the
mutation preserves every invariant owned by the queue.

## Construction

`init()` is equivalent to `.{}`. Both create an empty queue with
`head = null` and `tail = null`.

`isEmpty()` returns `head == null`. A valid queue satisfies `head == null` iff
`tail == null`.

There is no capacity. The queue can link only caller-owned objects that already
exist, so exhaustion policy belongs to the owner domain.

## Endpoint access

`front()` returns the oldest queued object, or `null` when empty.

`constFront()` returns the read-only equivalent.

`back()` returns the newest queued object, or `null` when empty.

`constBack()` returns the read-only equivalent.

Pointers borrow from the caller-owned parent objects, not from queue storage. The
queue does not move those objects.

## Enqueue semantics

`pushBack(item)` links `item` after the current tail in O(1).

When the queue is empty, `pushBack(item)` sets both `head` and `tail` to `item`.

When the queue is not empty, `pushBack(item)` links the old tail to `item` and
sets `tail = item`.

`pushBack(item)` requires `item`'s selected node to be detached before the call.
There is no full state, so `pushBack(item)` has no error return.

## Dequeue semantics

`popFront()` removes and returns the oldest queued object. It returns `null` when
empty.

When the removed object was the only queued object, the queue becomes empty.
When more objects remain, `head` advances to the next queued object.

The removed object's selected node is detached before return.

## Clearing

`clear()` walks the queue in FIFO order, detaches every queued node, and then
sets `head = null` and `tail = null`.

`clear()` does not destroy, zero, free, poison, or move parent objects.

There is no `clearRetainingCapacity` because intrusive queues have no capacity
and own no backing storage. There is no `clearAndFree` or `deinit` because
intrusive queues own no resources.

## Invalidation and ordering

Intrusive queues do not invalidate parent-object pointers by moving objects. They
only change queue membership and link-neighbor relationships.

`pushBack(item)` changes the old tail's successor relationship when the queue is
not empty. It changes endpoint pointers when the queue was empty or when the back
endpoint moves to `item`.

`popFront()` invalidates the removed object's queue membership and its former
neighbor relationship. Remaining objects stay at the same addresses.

`clear()` invalidates every membership in the queue and detaches every node.

FIFO order is the order of successful `pushBack(item)` calls not yet removed.
`popFront()` returns objects in FIFO order. There is no reordering.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `Queue` | never | never | comptime | none | type factory | none |
| `init` | never | never | O(1) | none | caller-owned value | empty |
| `isEmpty` | never | never | O(1) | none | caller-owned value | none |
| endpoint access | never | never | O(1) | none | caller-owned value | FIFO endpoints |
| `pushBack` | never | never | O(1) | old tail endpoint | caller-owned value | appends newest |
| `popFront` | never | never | O(1) | removed head | caller-owned value | removes oldest |
| `clear` | never | never | O(n) | all memberships | caller-owned value | empty |
| `assertValid` | never | never | O(n) | none | caller-owned value | verifies topology |

These operations perform no heap allocation, waiting, hidden global access,
atomics, barriers, volatile access, target probing, syscalls, locks, or I/O.

## Error behavior

The public API has no error set.

- empty endpoint access returns `null`;
- empty pops return `null`;
- invalid type and field combinations are compile errors where practical;
- double insert is a programmer error;
- using the same node field in another intrusive object while queued is a
  programmer error;
- externally corrupted links are a programmer error.

Operations with programmer-error preconditions may assert those preconditions
when practical, but the spec does not require runtime owner tracking.

## Debug assertion behavior

`assertValid()` checks local topology reachable from this queue's endpoints. It
does not prove node ownership, detect all double inserts, or make wrong-queue use
safe.

`assertValid()` checks where practical:

- `head == null` iff `tail == null`;
- if non-empty, `tail` is reachable from `head`;
- if non-empty, `tail.next == null`;
- no cycle is reachable from `head`.

Mutating operations may call `assertValid()` before and after mutation when
`core.checksEnabled(opts.safety)` or an equivalent module safety option requires
runtime invariant checks.

## Implementation constraints

Queue may reuse internal intrusive-list helper code, but the returned public type
must not expose an inner `List.SinglyLinked` value. The public value exposes only
queue endpoints and queue operations.

Implementations should not maintain a count. A count would add a store to every
enqueue and dequeue while providing no primitive-level capacity or exhaustion
behavior.

## Examples

Run queue:

```zig
const Thread = struct {
    id: u32,
    runq_node: zstdx.intrusive.List.SinglyLinkedNode = .{},
};

const RunQueue = zstdx.intrusive.Queue(Thread, "runq_node");

var runq = RunQueue.init();
var thread_a: Thread = .{ .id = 1 };
var thread_b: Thread = .{ .id = 2 };

runq.pushBack(&thread_a);
runq.pushBack(&thread_b);

while (runq.popFront()) |thread| {
    run(thread);
}
```

Free list queue discipline:

```zig
const Buffer = struct {
    bytes: [4096]u8,
    free_node: zstdx.intrusive.List.SinglyLinkedNode = .{},
};

const FreeBuffers = zstdx.intrusive.Queue(Buffer, "free_node");

var free = FreeBuffers.init();
var buffer: Buffer = .{ .bytes = undefined };

free.pushBack(&buffer);
const next = free.popFront() orelse return error.OutOfBuffers;
```

## Required tests

Construction tests:

- empty queue;
- `init()` equals default initialization;
- endpoint access on an empty queue returns `null`;
- `popFront()` on an empty queue returns `null`.

FIFO tests:

- push one item;
- push two items;
- `front()` remains the oldest item after pushes;
- `back()` tracks the newest item after pushes;
- `popFront()` returns items in push order;
- `popFront()` from a one-item queue clears both endpoints;
- `popFront()` from a multi-item queue preserves remaining order.

Clearing tests:

- clear an empty queue;
- clear a one-item queue;
- clear a multi-item queue;
- cleared nodes are detached;
- reinsertion after clear succeeds.

Cross-cutting tests:

- queue uses `List.SinglyLinkedNode` fields;
- wrong field type fails to compile where practical;
- multi-membership through distinct embedded node fields;
- parent object addresses stay stable across queue operations;
- removed and cleared nodes are detached;
- `assertValid()` succeeds after every public mutation;
- structural corruption tests where practical for broken endpoints and cycles.

## Open questions

None.
