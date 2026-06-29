# Collections static ring

Status: Approved.

`stdx.collections.Ring.Static(T, N)` is an inline fixed-capacity FIFO. It owns
its storage, preserves enqueue order, and never allocates.

The root facade may expose the same family as `stdx.Ring.Static(T, N)`.

## Owned scope

This spec owns:

- `collections.Ring.Static(T, N)`;
- inline `[N]T` storage with head index and live-element count;
- `pushBack`, `pushBackAssumeCapacity`, `pushBackOverwriteOldest`, `popFront`;
- pointer access to the front and back live elements;
- branch-wrap index advancement for arbitrary capacity;
- capacity, invalidation, ordering, and full-capacity behavior;
- required tests.

This spec does not own:

- caller-provided storage or runtime capacity; use `Ring.Bounded` for that;
- managed or unmanaged heap allocation;
- list, stack, deque, double-ended, set, map, or slot-map semantics;
- `pushFront` or `popBack`; use `Deque.Static` when both ends are needed;
- contiguous slice exposure; wrap-aware iteration is left to callers;
- bulk `pushBackSlice` or `drainFront` helpers;
- sorting, uniqueness, coalescing, or duplicate checks;
- string, sentinel, UTF, truncation, or text policy;
- stable handles, generation counters, or tombstones;
- on-drop callbacks or overwrite policy enums;
- single- or multi-producer atomic ring semantics; see
  `docs/specs/concurrent/spsc-ring.md` for the planned concurrent variant;
- ABI, wire, or packed layout guarantees for the ring value.

## Public namespace

`Ring` lives under `stdx.collections`:

```zig
stdx.collections.Ring
```

It is root-promoted by the first-slice root facade:

```zig
stdx.Ring
```

Source ownership:

```text
src/collections.zig
src/collections/ring.zig
test/collections/ring_test.zig
```

`src/collections.zig` re-exports:

```zig
pub const ring = @import("collections/ring.zig");

pub const Ring = ring.Ring;
```

`src/stdx.zig` re-exports:

```zig
pub const collections = @import("collections.zig");

pub const Ring = collections.Ring;
```

## Approved API

```zig
pub const Ring = struct {
    pub fn Static(comptime T: type, comptime capacity_items: usize) type;
};
```

Returned type:

```zig
pub const Self = struct {
    buffer: [capacity_items]T = undefined,
    head: usize = 0,
    count: usize = 0,

    pub const Error = error{Full};
    pub const item_capacity = capacity_items;

    pub fn init() Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn pushBack(self: *Self, item: T) Error!void;
    pub fn pushBackAssumeCapacity(self: *Self, item: T) void;
    pub fn pushBackOverwriteOldest(self: *Self, item: T) ?T;

    pub fn popFront(self: *Self) ?T;

    pub fn front(self: *Self) ?*T;
    pub fn constFront(self: *const Self) ?*const T;
    pub fn back(self: *Self) ?*T;
    pub fn constBack(self: *const Self) ?*const T;

    pub fn assertValid(self: *const Self) void;
};
```

There is no `peek` alias, no `enqueue`/`dequeue` alias, and no `asSlice`. Callers
who need a value-typed read of the front element write `(ring.constFront() orelse
return null).*`.

## Type and capacity contract

`T` must be a runtime value type with `@sizeOf(T) > 0`. Zero-sized element types
are compile errors where practical.

`capacity_items` is a comptime item count. `Static(T, 0)` is valid; it is both
empty and full. On a zero-capacity ring, every `pushBack` returns `error.Full`,
`pushBackOverwriteOldest` returns the input item unchanged, and every pointer
accessor returns `null`.

A valid ring satisfies:

```zig
ring.count <= item_capacity
ring.head < item_capacity  // when item_capacity > 0
```

The live elements are the `count` slots starting at `head` and advancing forward
with wrap at `item_capacity`. Other slots are spare storage and may contain
undefined bytes.

Direct field mutation must preserve both invariants and the live-prefix rule.

## Construction and clearing

`init()` is equivalent to `.{}`. Both create an empty ring with uninitialized
storage, `head = 0`, and `count = 0`.

`clearRetainingCapacity()` sets `count` to zero. It does not zero memory, reset
`head`, call destructors, release resources, or change `item_capacity`. After
clearing, the next `pushBack` enqueues at the current `head` slot.

There is no `clearAndFree`; a static ring has no heap allocation to release.

## Capacity operations

`len()` returns `count`.

`capacity()` returns `item_capacity`.

`remaining()` returns `item_capacity - count`.

`isEmpty()` returns `count == 0`.

`isFull()` returns `count == item_capacity`.

These operations do not inspect spare storage.

## Pointer access

`front()` returns `&buffer[head]` when the ring is non-empty, otherwise `null`.

`constFront()` returns the read-only equivalent.

`back()` returns a pointer to the most recently enqueued live element when the
ring is non-empty, otherwise `null`. The back slot is the unique index `b` such
that the live elements are `buffer[head], buffer[head + 1 mod item_capacity], …,
buffer[b]`.

`constBack()` returns the read-only equivalent.

Pointers borrow from the ring value. Moving or copying the ring value
invalidates pointers and slices into the old value.

## Enqueue semantics

`pushBack(item)` writes `item` to `buffer[(head + count) % item_capacity]` and
increments `count`. It returns `error.Full` and leaves the ring unchanged when
`isFull()`.

`pushBackAssumeCapacity(item)` performs the same mutation and asserts that the
ring is not full.

`pushBackOverwriteOldest(item)` always writes `item` to the back slot. If the
ring was not full, it increments `count` and returns `null`. If the ring was
full, it overwrites the front slot, advances `head`, leaves `count` at
`item_capacity`, and returns the evicted front element. On `Static(T, 0)` it
performs no mutation and returns `item` unchanged so callers can release
ownership uniformly.

Implementations advance indices with branch wrap, not modulo:

```zig
index += 1;
if (index == item_capacity) index = 0;
```

Capacity is not constrained to a power of two.

## Dequeue semantics

`popFront()` removes and returns `buffer[head]`, advances `head` with branch
wrap, and decrements `count`. It returns `null` when empty. The vacated slot
becomes spare storage.

The ring never calls destructors; callers own element resource lifetimes,
including the values returned by `popFront` and the values returned from
`pushBackOverwriteOldest`.

## Invalidation and ordering

`pushBack` and `pushBackAssumeCapacity` do not invalidate the current front
pointer. They do invalidate any previously held `back`/`constBack` pointer
because the back slot has moved; the prior slot still holds a live interior
element and is reachable through iteration, but the prior pointer is no longer
the back.

`popFront` invalidates the prior `front`/`constFront` pointer. It does not
invalidate the back pointer.

`pushBackOverwriteOldest` on a non-full ring behaves like `pushBack`. On a full
ring it invalidates both the prior front and the prior back pointer.

`clearRetainingCapacity` invalidates all front and back pointers previously
returned by the ring.

Iteration order is `popFront` order: the element at `head`, then successive
slots with wrap, for `count` elements total. Pushes append at the back; pops
remove from the front. There is no reordering.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `Static` | never | never | comptime | none | type factory | none |
| `init` | never | never | O(1) | none | caller-owned value | empty |
| capacity helpers | never | never | O(1) | none | caller-owned value | none |
| `clearRetainingCapacity` | never | never | O(1) | all front and back pointers | caller-owned value | empty |
| `pushBack` | never | never | O(1) | back pointer | caller-owned value | appends to tail |
| `pushBackAssumeCapacity` | never | never | O(1) | back pointer | caller-owned value | appends to tail |
| `pushBackOverwriteOldest` | never | never | O(1) | back pointer; front pointer when full | caller-owned value | appends to tail, evicts front when full |
| `popFront` | never | never | O(1) | old front pointer | caller-owned value | removes from head |
| `front` / `constFront` | never | never | O(1) | none | caller-owned value | none |
| `back` / `constBack` | never | never | O(1) | none | caller-owned value | none |
| `assertValid` | never | never | O(1) | none | caller-owned value | none |

These operations perform no heap allocation, waiting, hidden global access,
atomics, barriers, volatile access, target probing, syscalls, locks, or I/O.

## Error behavior

- full-capacity `pushBack` returns `error.Full`;
- `pushBackAssumeCapacity` reports full capacity as a programmer error;
- `popFront` uses `null` for empty instead of an error;
- `pushBackOverwriteOldest` cannot fail; the optional return reports eviction;
- `front`, `back`, `constFront`, and `constBack` use `null` for empty;
- invalid `T` categories are compile errors where practical;
- corrupted `count` or `head` is a programmer error caught by `assertValid`
  where practical.

All error returns leave the ring unchanged.

## Debug assertion behavior

`assertValid()` asserts `count <= item_capacity` and, when `item_capacity > 0`,
`head < item_capacity`.

Public mutating operations may call `assertValid()` before and after mutation
when `core.checksEnabled(opts.safety)` or an equivalent module safety option
requires runtime invariant checks.

## Implementation constraints

Implementation must:

- store only inline element storage, the head index, and the live-element count
  in `Self`;
- never store an allocator, vtable, policy flag, capacity field, or external
  backing pointer;
- never allocate, reserve, grow, shrink, or free backing storage;
- advance head and back indices with branch wrap, never modulo, where
  `item_capacity` is not a comptime power of two;
- update `head` and `count` only after capacity checks succeed;
- leave the ring unchanged on `error.Full`;
- set vacated slots to `undefined` where practical after `popFront` and after
  the eviction step of `pushBackOverwriteOldest`;
- never read or expose spare slots as live elements;
- avoid hidden globals, atomics, fences, volatile operations, target probes,
  and I/O.

## Planned consumers

`zvm` has 16550A UART RX and TX FIFOs of fixed depth 16. The RX FIFO must
surface overrun in `LSR.OE` rather than silently overwrite; it uses `pushBack`
and observes `error.Full`. The TX FIFO is drained by `popFront`.

`zfw` has a fixed-capacity pending-notification queue on
`HandleDatabase.NotifyEntry` whose current behavior overwrites the oldest entry
when full. It uses `pushBackOverwriteOldest` and releases the evicted
`NotifyEntry` through the returned optional.

`zacpi` does not currently have a FIFO consumer. A future diagnostic trace
buffer (see `docs/specs/diag/trace-ring.md`) is a candidate when that spec
lands.

## Examples

UART RX FIFO with overrun reporting:

```zig
const stdx = @import("stdx");

const RxFifo = stdx.Ring.Static(u8, 16);

var rx = RxFifo.init();

fn onHostByte(byte: u8) void {
    rx.pushBack(byte) catch {
        lsr.overrun_error = true;
    };
}

fn guestRead(out: *u8) bool {
    out.* = rx.popFront() orelse return false;
    return true;
}
```

Pending-notification queue with drop-oldest and ownership transfer:

```zig
const Pending = stdx.Ring.Static(NotifyEntry, 8);

var pending = Pending.init();

if (pending.pushBackOverwriteOldest(entry)) |dropped| {
    dropped.handle.release();
}
```

Pointer access for large `T`:

```zig
const Events = stdx.Ring.Static(Event, 32);

var events = Events.init();

if (events.constFront()) |e| {
    dispatch(e.*);
    _ = events.popFront();
}
```

Capacity-checked enqueue without an error path:

```zig
while (queue.remaining() != 0 and produce(&item)) {
    queue.pushBackAssumeCapacity(item);
}
```

## Required tests

### Construction and capacity

- default struct literal is empty with `head = 0` and `count = 0`;
- `init()` is empty;
- `Static(T, 0)` is both empty and full;
- `len`, `capacity`, `remaining`, `isEmpty`, and `isFull` cover empty, partial,
  full, and zero-capacity rings;
- zero-sized `T` fails to compile where the compile-fail harness supports it.

### Enqueue

- `pushBack` succeeds into empty and non-full rings;
- `pushBack` returns `error.Full` without mutation when full;
- `pushBackAssumeCapacity` enqueues after a caller capacity check;
- `pushBackOverwriteOldest` returns `null` when not full and increments `count`;
- `pushBackOverwriteOldest` returns the evicted front and advances `head` when
  full;
- `pushBackOverwriteOldest` on `Static(T, 0)` returns the input item without
  mutating the ring;
- enqueue across the wrap boundary is correct for at least one full revolution.

### Dequeue

- `popFront` returns `null` when empty;
- `popFront` returns items in FIFO order;
- dequeue across the wrap boundary is correct for at least one full revolution;
- alternating `pushBack` and `popFront` across the wrap boundary preserve order
  for at least one full revolution.

### Pointer access

- `front`, `constFront`, `back`, and `constBack` return `null` when empty;
- `front` and `back` reference the current head and back slots and allow element
  mutation through `*T`;
- after `pushBack`, the new `back()` points at the just-enqueued slot;
- after `popFront`, the prior `front()` pointer is treated as invalid by the
  contract, and the new `front()` points at the next live slot.

### Invalidation

- `pushBack` and `pushBackAssumeCapacity` do not invalidate the prior front
  pointer;
- `popFront` invalidates the prior front pointer;
- `pushBackOverwriteOldest` when full invalidates both the prior front and the
  prior back pointer;
- `clearRetainingCapacity` invalidates all prior front and back pointers and
  leaves the ring empty.

### Invariants

- `assertValid` succeeds after every public mutation sequence;
- `assertValid` catches a manually corrupted `count > item_capacity` where
  practical;
- `assertValid` catches a manually corrupted `head >= item_capacity` for
  `item_capacity > 0` where practical;
- iteration via repeated `popFront` produces the enqueue order for at least one
  full wrap.

## Open questions

None.
