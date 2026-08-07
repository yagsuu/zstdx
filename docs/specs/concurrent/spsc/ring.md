# Concurrent SPSC ring

Status: Approved.

`stdx.concurrent.spsc.Ring` is a bounded single-producer/single-consumer FIFO ring. It transfers items between exactly one producer context and exactly one consumer context without allocation or compare-and-swap operations.

The ring owns item movement and publication. It does not own wake, scheduler, interrupt, or waiting policy.

## What this spec is

This spec owns:

- `concurrent.spsc.Ring.Static(T, N)` and `concurrent.spsc.Ring.Bounded(T)`;
- caller-provided `Bounded(T).Slot` storage;
- one-attempt producer enqueue and one-attempt consumer dequeue of published front items;
- cache-line isolation of `head` and `tail` via `mem.CachePad`;
- fixed-capacity, full-capacity, no-mutation-on-error, and pointer-stability contracts;
- atomic slot-publication and slot-release ordering; and
- required unit, model, ordering, and stress tests.

## What this spec is not

This spec does not define MPSC, MPMC, work-stealing, intrusive queues, heap allocation, growth, reserve operations, blocking or retrying operations, wait integration, overwrite policy, bulk operations, iterators, live-element pointers, arbitrary removal, cancellation, handles, signal or scheduler policy, multi-producer or multi-consumer safety, or ABI, wire, or packed-layout guarantees.

Two producer contexts or two consumer contexts on the same ring are outside this contract.

## Public namespace and source ownership

The SPSC family lives under `stdx.concurrent.spsc`:

```zig
stdx.concurrent.spsc
stdx.concurrent.spsc.Ring
stdx.concurrent.spsc.Ring.Static
stdx.concurrent.spsc.Ring.Bounded
```

Source ownership:

```text
src/concurrent.zig            -- domain facade
src/concurrent/spsc.zig       -- sub-namespace facade
src/concurrent/spsc/ring.zig  -- Ring implementation
test/concurrent/spsc/ring_test.zig
```

`src/concurrent.zig` re-exports:

```zig
pub const spsc = @import("concurrent/spsc.zig");
```

Only the sub-namespace is exported. There is no `pub const Ring = spsc.Ring;`
alias; callers reach `Ring` through `stdx.concurrent.spsc.Ring` and alias
locally when call sites are dense:

```zig
const spsc = stdx.concurrent.spsc;
```

`src/concurrent.zig` is a thin facade. It contains no logic beyond
re-exporting.

## API

```zig
pub const Ring = struct {
    pub fn Static(comptime T: type, comptime capacity_items: usize) type;
    pub fn Bounded(comptime T: type) type;
};
```

### `Static(T, capacity_items)` returned type

```zig
pub const Self = struct {
    slots: [item_capacity]Slot = undefined,
    head: stdx.mem.CachePad(std.atomic.Value(usize)) =
        .{ .value = std.atomic.Value(usize).init(0) },
    tail: stdx.mem.CachePad(std.atomic.Value(usize)) =
        .{ .value = std.atomic.Value(usize).init(0) },

    pub const Slot = struct {
        item: T = undefined,
    };
    pub const Error = error{Full};
    pub const item_capacity = capacity_items;

    pub fn init(self: *Self) void;

    pub fn capacity(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;

    pub fn tryPushBack(self: *Self, item: T) Error!void;
    pub fn popFront(self: *Self) ?T;

    pub fn assertValid(self: *const Self) void;
};
```

### `Bounded(T)` returned type

```zig
pub const Self = struct {
    slots: []Slot,
    head: stdx.mem.CachePad(std.atomic.Value(usize)) =
        .{ .value = std.atomic.Value(usize).init(0) },
    tail: stdx.mem.CachePad(std.atomic.Value(usize)) =
        .{ .value = std.atomic.Value(usize).init(0) },

    pub const Slot = struct {
        item: T = undefined,
    };
    pub const Error = error{Full};

    pub fn init(self: *Self, slots: []Slot) void;

    pub fn capacity(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;

    pub fn tryPushBack(self: *Self, item: T) Error!void;
    pub fn popFront(self: *Self) ?T;

    pub fn assertValid(self: *const Self) void;
};
```

There is no `pushBack`, `enqueue`, `dequeue`, `pushBackAssumeCapacity`,
`pushBackOverwriteOldest`, `front`, `back`, `len`, `remaining`, `isFull`,
`clearRetainingCapacity`, or iterator API.

The absence of `pushBack` is intentional: the producer uses the one-attempt
`tryPushBack` API so full-capacity behavior is visible to callers.

### Slot type

`Slot` has exactly one field, `item: T`. SPSC does not require a per-slot
publication sequence because there is exactly one producer and exactly one
consumer; head and tail alone synchronize slot ownership.

### Index type

`head` and `tail` are `stdx.mem.CachePad(std.atomic.Value(usize))`. Cache-line
isolation is unconditional; there is no opt-out. Callers reach the atomic
through the wrapper's `value` field:

```zig
self.head.value.load(.acquire)
self.tail.value.store(new_tail, .release)
```

## Type and capacity contract

`T` MUST be a runtime value type with `@sizeOf(T) > 0`. A zero-sized element type MUST produce a compile error.

Capacity MUST be non-zero and a power of two.

`Static(T, 0)` and `Static(T, N)` where `N` is not a power of two MUST produce compile errors.

`Bounded(T).init(slots)` MUST treat `slots.len == 0` and non-power-of-two `slots.len` as programmer errors and MUST assert these preconditions when build-mode checks are enabled. The API does not return a capacity-shape error.

`capacity()` returns `item_capacity` for `Static` and `slots.len` for
`Bounded`.

`Bounded(T).Slot` is the caller-provided storage unit. Callers allocate it
but must not inspect or mutate its fields except by passing the slice to
`init` and preserving its lifetime.

## Ownership and lifetime

`Static` owns inline slot storage. `Bounded` borrows `[]Slot` storage.

`init` resets head and tail to zero. It does not initialize user payload
values as live items.

Both variants must be initialized in place:

```zig
var ring: WorkRing = undefined;
ring.init(); // Static; Bounded passes a slot slice.
```

After initialization, copying the ring value is outside the primitive's
contract. After any pointer to the ring is shared with another execution
context, moving the ring value is outside the primitive's contract.

For `Bounded`, the borrowed slot slice must remain alive, at the same
address, and exclusively owned by this ring for the ring lifetime and for
every concurrent operation. Reusing a slot slice for another ring before all
concurrent operations finish is outside the contract.

The ring never calls destructors. Callers own resource lifetimes for values
successfully pushed and later returned by `popFront`. A failed `tryPushBack`
leaves the ring unchanged and does not store the item.

## Producer access contract

Exactly one producer context may call `tryPushBack` on a ring. Calling
`tryPushBack` concurrently from two contexts is outside the contract. The
producer contract is a documented invariant; the ring performs no runtime
detection of concurrent producers.

The producer may call `tryPushBack` concurrently with the single consumer's
`popFront`.

`tryPushBack` performs one bounded enqueue attempt. It does not loop. It may
return:

- `error.Full` when no capacity is available;
- success after writing and release-publishing `item`.

`error.Full` leaves the ring unchanged and does not store the item.

There is no `Contended` error because there is no producer contention: a
single producer cannot race itself.

Producer retry, backoff, dropping, accounting, logging, and signaling
policies belong to the caller.

## Consumer access contract

Exactly one consumer context may call `popFront` on a ring. Calling
`popFront` concurrently from two contexts is outside the contract. The
consumer contract is a documented invariant; the ring performs no runtime
detection of concurrent consumers.

The consumer may call `popFront` concurrently with the single producer's
`tryPushBack`.

`popFront` returns the next published item in FIFO order. It returns `null`
when the ring holds no published item. A `null` result proves only that the
consumer cannot currently read a published front item; it does not prove the
producer has not observed a `Full` condition or is not about to publish.

This distinction matters for notification protocols. Consumers that are
about to park must clear their signal and then recheck the ring with
`popFront` before waiting.

## FIFO and publication semantics

Successful `tryPushBack` calls are ordered by tail advance. The consumer
observes items in that order.

A slot's item is not visible to the consumer until the producer
release-publishes the new tail. After `popFront` returns an item, the
consumer release-publishes the new head; the producer will not overwrite the
slot before observing the head advance.

`popFront` removes at most one item.

## Capacity and query operations

`capacity()` is stable after `init`.

`isEmpty()` is an acquire snapshot for the single consumer. It returns true
when `tail == head`. The producer must not consult `isEmpty()` to decide
whether to publish or signal; the producer is authoritative about full via
`tryPushBack`'s return value.

There is no `len` or `isFull`. `popFront` exposes FIFO availability, and `tryPushBack` is authoritative for full-capacity behavior.

## Ordering contract

Producer procedure:

- load own `tail` `.monotonic` (single writer);
- load `head` `.acquire`;
- return `error.Full` when `tail - head >= capacity`;
- write `slot.item = item`;
- store `tail + 1` to `tail` `.release`.

Consumer procedure:

- load own `head` `.monotonic` (single writer);
- load `tail` `.acquire`;
- return `null` when `tail == head`;
- read `slot.item`;
- store `head + 1` to `head` `.release`.

Head and tail wrap by unsigned overflow of `usize`. Capacity is a power of
two so `& (capacity - 1)` produces the slot index without modulo.

A signal call after successful push is a doorbell only:

```zig
try ring.tryPushBack(item);
signal.set();
```

The ring's release/acquire operations own item visibility. `signal.set()`
does not make the item visible by itself.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `Static` | never | never | comptime | none | type factory | none |
| `Bounded` | never | never | comptime | none | type factory | none |
| `init` | never | never | O(capacity) | all old state | exclusive access | initializes indices |
| `capacity` | never | never | O(1) | none | any caller | none |
| `isEmpty` | never | never | O(1) | none | consumer snapshot | acquire tail |
| `tryPushBack` success | never | never | O(1) | none | single producer + concurrent consumer | acquire head, release-publishes tail |
| `tryPushBack` error | never | never | O(1) | none | single producer | acquire head, no mutation |
| `popFront` item | never | never | O(1) | removed item | single consumer + concurrent producer | acquire tail, release-frees head |
| `popFront` null | never | never | O(1) | none | single consumer | acquire tail |
| `assertValid` | never | never | O(1) | none | exclusive or quiescent access | none |

The ring performs no heap allocation, sleeping, blocking, hidden scheduler
calls, I/O, volatile access, MMIO access, target probing, or hidden global
access.

`tryPushBack` and `popFront` are wait-free single-shot operations.

## Error behavior

- `error.Full` means the fixed-capacity ring has no producer slot available;
- `error.Full` leaves the ring unchanged and does not publish the item;
- `popFront` uses `null` for no published item;
- invalid capacity and invalid `T` are programmer errors or compile errors
  as described above.

## Debug assertion behavior

`assertValid()` checks cheap structural invariants that are meaningful
without racing the peer:

- power-of-two capacity;
- `tail - head <= capacity` (unsigned modular subtraction).

`assertValid()` is intended for exclusive or quiescent access. It does not
walk unbounded external state and does not claim to prove absence of
concurrent races.

Public operations may use internal assertions for capacity shape, initialized
indices, and impossible state transitions when project safety options enable
checks.

The ring does not attempt runtime detection of concurrent producers or
concurrent consumers. Violating the sole-producer or sole-consumer contract
is undefined behavior under this spec.

## Implementation constraints

Implementation must:

- keep producer and consumer paths wait-free with a single bounded attempt;
- use plain atomic loads and stores; no CAS on head or tail;
- use `.acquire` for the load of the peer's index and `.release` for the
  store of the own index;
- use `.monotonic` for the single-writer load of the own index;
- keep `head` and `tail` in `stdx.mem.CachePad(std.atomic.Value(usize))`;
- avoid modulo in hot paths by requiring power-of-two capacity;
- leave ring state unchanged on `error.Full`;
- avoid copying `T` more than required to store and return items;
- store no allocator, policy object, signal pointer, waiter, or callback in
  the ring;
- reject zero-sized `T` and non-power-of-two `Static` capacity at compile time.

## Testing

Tests MUST verify the observable FIFO, capacity, lifetime, and ordering contracts rather than implementation-only details.

### Construction, boundaries, and errors

Compile-time tests MUST reject zero-sized `T`, `Static(T, 0)`, and non-power-of-two static capacities. They MUST verify that `Bounded(T).Slot` is available for caller storage and that `head` and `tail` are separated by at least `std.atomic.cache_line` in both variants. Runtime tests MUST verify initialization, capacity, empty dequeue, full-capacity `error.Full` with no state change, caller-provided bounded storage without allocation, and drain/refill across the wrap boundary. These tests prove the representation and fixed-capacity boundary contract.

### Deterministic model and ordering

A deterministic single-producer/single-consumer model MUST compare every successful enqueue and dequeue with a reference FIFO. It MUST include empty dequeues, full capacity, wraparound, and reuse after the consumer advances `head`. The model MUST verify that a producer cannot overwrite a consumed slot until it acquire-observes the consumer's release-published `head`, and that the consumer reads an item only after it acquire-observes the producer's release-published `tail`. This proves FIFO order and both slot-ownership happens-before edges.

### Concurrent stress

Stress tests MUST run one producer and one consumer with a capacity of one and with a capacity that forces repeated wraparound. The producer MUST account for and retry every `error.Full`; the consumer MUST verify that every successful item occurs exactly once and in producer order. This exercises the specified roles and publication protocol under concurrent scheduling; it does not replace the deterministic ordering model.

## Examples

Static ring:

```zig
const spsc = stdx.concurrent.spsc;
const WorkRing = spsc.Ring.Static(WorkItem, 64);

var ring: WorkRing = undefined;
ring.init();

try ring.tryPushBack(.{ .id = 1 });
const item = ring.popFront() orelse unreachable;
_ = item;
```

Bounded ring:

```zig
const spsc = stdx.concurrent.spsc;
const WorkRing = spsc.Ring.Bounded(WorkItem);

var slots: [64]WorkRing.Slot = undefined;
var ring: WorkRing = undefined;
ring.init(slots[0..]);
```

Ring plus signal:

```zig
try ring.tryPushBack(item);
ready.set();
```

Consumer recheck before wait:

```zig
while (ring.popFront()) |item| {
    handle(item);
}

ready.clear();

if (ring.popFront()) |item| {
    handle(item);
    continue;
}

try ready.wait();
```
