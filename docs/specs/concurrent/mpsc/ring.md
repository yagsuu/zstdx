# Concurrent MPSC ring

Status: Approved.

`stdx.concurrent.mpsc.Ring` is a bounded multi-producer/single-consumer FIFO ring. It transfers items from any number of producer contexts to exactly one consumer context without allocation.

The ring owns item movement and publication. It does not own wake, scheduler, interrupt, or waiting policy.

## What this spec is

This spec owns:

- `concurrent.mpsc.Ring.Static(T, N)` and `concurrent.mpsc.Ring.Bounded(T)`;
- caller-provided `Bounded(T).Slot` storage;
- one-attempt producer enqueue with explicit contention reporting;
- single-consumer dequeue of published front items;
- fixed-capacity, full-capacity, no-mutation-on-error, and pointer-stability contracts;
- atomic slot-publication and slot-release ordering; and
- required unit, model, ordering, and stress tests.

## What this spec is not

This spec does not define SPSC, MPMC, work-stealing, intrusive or linked queues, heap allocation, growth, reserve operations, blocking or retrying operations, wait integration, overwrite policy, bulk operations, iterators, live-element pointers, arbitrary removal, cancellation, handles, signal or scheduler policy, or ABI, wire, or packed-layout guarantees.

## Public namespace and source ownership

The MPSC family lives under `stdx.concurrent.mpsc`:

```zig
stdx.concurrent.mpsc
stdx.concurrent.mpsc.Ring
stdx.concurrent.mpsc.Ring.Static
stdx.concurrent.mpsc.Ring.Bounded
```

Source ownership:

```text
src/concurrent.zig            -- domain facade
src/concurrent/mpsc.zig       -- sub-namespace facade
src/concurrent/mpsc/ring.zig  -- Ring implementation
test/concurrent/mpsc/ring_test.zig
```

`src/concurrent.zig` re-exports:

```zig
pub const mpsc = @import("concurrent/mpsc.zig");
```

Only the sub-namespace is exported. There is no `pub const Ring = mpsc.Ring;`
alias; callers reach `Ring` through `stdx.concurrent.mpsc.Ring` and alias
locally when call sites are dense:

```zig
const mpsc = stdx.concurrent.mpsc;
```

`src/concurrent.zig` is a thin facade. It contains no logic beyond re-exporting.

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
        sequence: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        item: T = undefined,
    };
    pub const Error = error{ Full, Contended };
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
        sequence: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        item: T = undefined,
    };
    pub const Error = error{ Full, Contended };

    pub fn init(self: *Self, slots: []Slot) void;

    pub fn capacity(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;

    pub fn tryPushBack(self: *Self, item: T) Error!void;
    pub fn popFront(self: *Self) ?T;

    pub fn assertValid(self: *const Self) void;
};
```

There is no `pushBack`, `enqueue`, `dequeue`, `pushBackAssumeCapacity`, `pushBackOverwriteOldest`, `front`, `back`, `len`, `remaining`, `isFull`, `clearRetainingCapacity`, or iterator API. `tryPushBack` exposes the one-attempt result, including producer contention.

## Type and capacity contract

`T` MUST be a runtime value type with `@sizeOf(T) > 0`. A zero-sized element type MUST produce a compile error.

Capacity MUST be non-zero and a power of two.

`Static(T, 0)` and `Static(T, N)` where `N` is not a power of two MUST produce compile errors.

`Bounded(T).init(slots)` MUST treat `slots.len == 0` and non-power-of-two `slots.len` as programmer errors and MUST assert these preconditions when build-mode checks are enabled. The API does not return a capacity-shape error.

`capacity()` returns `item_capacity` for `Static` and `slots.len` for `Bounded`.

`Bounded(T).Slot` is the caller-provided storage unit. It contains item storage
and metadata required by the algorithm. Callers allocate it but must not inspect
or mutate its fields except by passing the slice to `init` and preserving its
lifetime.

The implementation may require each slot to carry a sequence number or equivalent
publication state. That state is part of the ring contract, not user payload.

## Ownership and lifetime

`Static` owns inline slot storage. `Bounded` borrows `[]Slot` storage.

`init` initializes all slot metadata and resets head and tail. It does not
initialize user payload values as live items.

Both variants must be initialized in place:

```zig
var ring: WorkRing = undefined;
ring.init(); // Static; Bounded passes a slot slice.
```

After initialization, copying the ring value is outside the primitive's contract.
After any pointer to the ring is shared with another execution context, moving
the ring value is outside the primitive's contract.

For `Bounded`, the borrowed slot slice must remain alive, at the same address,
and exclusively owned by this ring for the ring lifetime and for every concurrent
operation. Reusing a slot slice for another ring before all concurrent operations
finish is outside the contract.

The ring never calls destructors. Callers own resource lifetimes for values
successfully pushed and later returned by `popFront`. A failed `tryPushBack`
leaves the ring unchanged and does not store the item.

## Producer access contract

Any number of producer contexts may call `tryPushBack` concurrently on the same
ring.

A producer that successfully reserves a slot must run the operation to
publication. Abandoning a reserved slot by panic, trap, cancellation, or forced
termination can prevent the single consumer from making progress. Implementations
must not call user callbacks or yield between reservation and publication.

### Execution context and NMI

`tryPushBack` requires reservation-to-publication atomicity with respect to
other producers on the same CPU. Any execution context that can preempt an
in-flight producer on the same CPU and then call `tryPushBack` on the same
ring — non-maskable interrupt (NMI), machine-check exception (MCE), a nested
interrupt handler that shares the ring with the outer producer — is outside
the primitive's contract. A preempted producer may leave a slot reserved-
but-unpublished, permanently stalling the consumer at that FIFO position.

The consumer path (`popFront`) is safe from any execution context including
NMI: `popFront` is a single owner, does not participate in the producer CAS,
and does not require reservation atomicity.

A caller that needs producer operations safe against preemption by another producer on the same CPU MUST provide external serialization or use a primitive with that contract. This ring has a reserved-but-unpublished window.

`tryPushBack` performs one bounded enqueue attempt. It does not loop until
success. Its only two error variants are:

- `error.Full` — the producer observed `tail - head >= capacity()` before it attempted the tail reservation CAS. Every slot was published or reserved at that observation. The operation leaves the ring unchanged.
- `error.Contended` — the tail reservation CAS observed a tail value different from the producer's expected value. Another producer changed the reservation state during this attempt. The operation leaves the ring unchanged.

Both error returns leave the ring unchanged: no head or tail advance, no slot
payload write, no publication.

On success the producer has advanced the reservation counter, written `item`
into the reserved slot, and release-published the slot for the consumer.

Producer retry, backoff, dropping, accounting, logging, and signaling policies
belong to the caller.

## Consumer access contract

Exactly one consumer context may call `popFront` on a ring. Calling `popFront`
concurrently from two contexts is outside the contract.

The consumer may call `popFront` concurrently with any number of producers.

`popFront` returns the next published item in FIFO order. It returns `null` when
no front item is currently published. A `null` result does not prove no producer
has reserved a slot; it proves only that the consumer cannot currently read a
published front item.

This distinction matters for notification protocols. Consumers that are about to
park must clear their signal and then recheck the ring with `popFront` before
waiting.

## FIFO and publication semantics

Successful `tryPushBack` calls are ordered by successful reservation order. The
consumer observes items in that order.

A producer's reservation is not visible as a readable item until the producer
release-publishes the slot. A later producer may publish its reserved slot before
an earlier producer publishes, but the consumer must not skip the earlier FIFO
position. The later item remains unavailable until every prior item is published
and popped.

`popFront` removes at most one item. After removal, the consumer release-publishes
the slot as free for future producers.

## Progress and liveness contract

The ring does not guarantee starvation freedom for a particular producer. Under adversarial scheduling, one producer can repeatedly lose the reservation CAS to other producers. `error.Contended` identifies a failed bounded attempt; caller-owned retry and backoff determine fairness.

If a producer reserves a slot and never publishes it, the consumer can stall permanently at that FIFO position. The ring provides no recovery for an abandoned reservation.

## Capacity and query operations

`capacity()` is stable after `init`.

`isEmpty()` is an acquire snapshot for the single consumer. It returns true when
no front item is currently published. It may return true while a producer has a
reserved but unpublished slot.

Producers MUST NOT use `isEmpty()` to decide whether signaling is required. A producer MUST signal after every successful push unless the caller owns a stronger notification protocol.

There is no `len` or `isFull`. `tryPushBack` is authoritative for full-capacity behavior.

## Ordering contract

The implementation must publish payload data with release/acquire ordering:

- producer observes a free slot before writing payload;
- producer writes `item` into the reserved slot;
- producer release-publishes the slot as containing an item;
- consumer acquire-observes the published slot before reading payload;
- consumer reads and removes the item;
- consumer release-publishes the slot as free before another producer reuses it.

Reservation state such as head and tail positions may use `.monotonic` when it
only orders atomic position claims. Slot publication and slot free operations
must use release/acquire ordering as described above.

A signal call after successful push is a doorbell only:

```zig
try ring.tryPushBack(item);
signal.set();
```

The ring's release/acquire operations own item visibility. `signal.set()` does
not make the item visible by itself.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `Static` | never | never | comptime | none | type factory | none |
| `Bounded` | never | never | comptime | none | type factory | none |
| `init` | never | never | O(capacity) | all old state | exclusive access | initializes metadata |
| `capacity` | never | never | O(1) | none | any caller | none |
| `isEmpty` | never | never | O(1) | none | consumer snapshot | acquire front publication |
| `tryPushBack` success | never | never | O(1) bounded attempt | none | MPSC producers | release-publishes item |
| `tryPushBack` error | never | never | O(1) bounded attempt | none | MPSC producers | no mutation |
| `popFront` item | never | never | O(1) | removed item | single consumer | acquire item, release-frees slot |
| `popFront` null | never | never | O(1) | none | single consumer | acquire front publication |
| `assertValid` | never | never | O(1) | none | exclusive or quiescent access | none |

`tryPushBack` is not safe from NMI or nested-producer contexts on the same
CPU; see the execution-context section under Producer access contract.
`popFront` is safe from any execution context including NMI.

The ring performs no heap allocation, sleeping, blocking, hidden scheduler calls,
I/O, volatile access, MMIO access, target probing, or hidden global access.

`tryPushBack` does not spin on producer contention. It performs a bounded attempt
and reports `error.Contended` when the reservation race is lost.

## Error behavior

- `error.Full` means the fixed-capacity ring has no producer slot available.
- `error.Contended` means another producer changed reservation state during this
  attempt.
- Both errors leave the ring unchanged and do not publish the item.
- `popFront` uses `null` for no published item.
- Invalid capacity and invalid `T` are programmer errors or compile errors as
  described above.

## Debug assertion behavior

`assertValid()` checks cheap structural invariants that are meaningful without
racing active producers. It is intended for exclusive or quiescent access.

Public operations may use internal assertions for capacity shape, initialized
metadata, and impossible state transitions when project safety options enable
checks.

`assertValid()` must not walk unbounded external state and must not claim to
prove absence of concurrent races.

## Implementation constraints

Implementation must:

- keep producer success as one bounded attempt;
- avoid hidden retry loops in `tryPushBack`;
- use per-slot publication state or an equivalent protocol that distinguishes
  reserved from published slots;
- never let the consumer read a reserved but unpublished item;
- preserve FIFO order even when later producers publish before earlier reserved
  slots;
- store no allocator, policy object, signal pointer, waiter, or callback in the
  ring;
- avoid modulo in hot paths by requiring power-of-two capacity;
- use release/acquire ordering for slot publication and slot free;
- place the consumer-owned head counter and the producer-shared tail counter
  on distinct cache lines via `stdx.mem.CachePad`, so that a producer's write
  to the tail counter does not invalidate the consumer's head cache line and
  vice versa;
- keep per-slot sequence counters unpadded — per-slot cache-line padding would
  bloat the ring beyond its intended footprint and slot contention is
  addressed by the reservation stripe, not by padding;
- leave ring state unchanged on `error.Full` and `error.Contended`;
- avoid copying `T` more than required to store and return items.

## Testing

Tests MUST verify the observable FIFO, capacity, contention, lifetime, and ordering contracts rather than implementation-only details.

### Construction, boundaries, and errors

Compile-time tests MUST reject zero-sized `T`, `Static(T, 0)`, and non-power-of-two static capacities. They MUST verify that `Bounded(T).Slot` is available for caller storage and that `head` and `tail` are separated by at least `std.atomic.cache_line`. Runtime tests MUST verify initialization, capacity, empty dequeue, full-capacity `error.Full` with no state change, bounded caller storage without allocation, and wraparound. A deterministic forced-CAS-failure test or model MUST verify that `error.Contended` makes no payload, publication, head, or tail mutation. These tests prove the boundary and no-mutation-on-error contracts.

### Deterministic model and ordering

A deterministic model MUST represent producer reservation, publication, consumer dequeue, and slot reuse separately. It MUST compare published items with a reference FIFO through empty, full, wraparound, retry-after-contention, and reserved-but-unpublished states. The model MUST verify that the consumer cannot skip an unpublished earlier reservation, that a consumer reads an item only after acquire-observing its release-published sequence, and that a producer reuses a slot only after acquire-observing the consumer's release-published `head`. This proves reservation-order FIFO behavior and the publication and reclamation happens-before edges.

### Concurrent stress

Stress tests MUST run multiple producers with disjoint item ranges and one consumer at a capacity of one and at a capacity that forces repeated wraparound. The harness MUST account for each `error.Full` and `error.Contended` result and retry or intentionally drop the corresponding item. The consumer MUST observe every successfully published item exactly once; it MUST preserve each producer's reservation order when that order is recorded. This exercises contention reporting, producer/consumer roles, and publication under concurrent scheduling; it does not replace the deterministic model.

## Examples

Static ring:

```zig
const mpsc = stdx.concurrent.mpsc;
const WorkRing = mpsc.Ring.Static(WorkItem, 64);

var ring: WorkRing = undefined;
ring.init();

try ring.tryPushBack(.{ .id = 1 });
const item = ring.popFront() orelse unreachable;
_ = item;
```

Bounded ring:

```zig
const mpsc = stdx.concurrent.mpsc;
const WorkRing = mpsc.Ring.Bounded(WorkItem);

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
