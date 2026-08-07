# Collections static ring

Status: Approved.

`stdx.collections.Ring.Static(T, N)` is an inline fixed-capacity FIFO. It owns
its storage, preserves enqueue order, and never allocates.

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
- ABI, wire, or packed layout guarantees for the ring value.

## Public namespace

`Ring` lives under `stdx.collections`:

```zig
stdx.collections.Ring
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

## API

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

`T` MUST be a runtime value type with `@sizeOf(T) > 0`; a zero-sized element
type is a compile error. `capacity_items` is a comptime item count greater than
zero. `Static(T, 0)` is a compile error.

A valid ring satisfies:

```zig
ring.count <= item_capacity
ring.head < item_capacity
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
`item_capacity`, and returns the evicted front element.
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
- a zero-sized `T` is a compile error;
- corrupted `count` or `head` violates the caller contract; `assertValid`
  asserts the capacity and head-range invariants.

All error returns leave the ring unchanged.

## Debug assertion behavior

`assertValid()` asserts `count <= item_capacity` and, when `item_capacity > 0`,
`head < item_capacity`.

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
- never read or expose spare slots as live elements;
- avoid hidden globals, atomics, fences, volatile operations, target probes,
  and I/O.

## Testing

Tests MUST construct empty, partial, and full rings to verify the comptime
capacity boundary, including compile-fail coverage for zero capacity and
zero-sized `T`. They MUST verify capacity helpers, empty optional returns, and
`error.Full`. These tests prove that the ring distinguishes all capacity states.

Mutation tests MUST enqueue, dequeue, and overwrite entries across at least one
wrap boundary. They MUST compare each dequeued value with enqueue order and
check the returned eviction value. These tests prove FIFO order, branch-wrap
behavior, overwrite semantics, and no mutation after `error.Full`.

Pointer tests MUST verify empty optional results and that `front` and `back`
refer to the current live endpoints. Invalidation tests MUST retain endpoint
pointers across pushes, pops, overwrite in both capacity states, clear, and
movement of the ring value. They MUST verify the documented stable and
invalidated pointers without dereferencing an invalid pointer.

Invariant tests MUST call `assertValid` after mutation sequences that fill,
drain, refill, and wrap the ring. Where assertions can be observed, deliberately
invalid `count` and `head` values MUST make `assertValid` fail. These tests prove
the capacity, head-range, and live-element invariants.
