# Collections bounded list

Status: Approved.

`stdx.collections.List.Bounded(T)` is a caller-storage-backed sequence with
runtime capacity. It preserves insertion order by default and never allocates.

## Owned scope

This spec owns:

- `collections.List.Bounded(T)`;
- borrowed `[]T` backing storage and initialized-prefix tracking;
- append, insert, pop, ordered removal, and swap removal;
- slice exposure for the initialized prefix;
- capacity, invalidation, ordering, and full-capacity behavior;
- required tests.

This spec does not own:

- inline `[N]T` storage; use `List.Static(T, N)` for that;
- managed or unmanaged heap allocation;
- arena allocation used to obtain the caller-owned backing slice;
- self-referential structs whose list field points at another field;
- ring, queue, stack, deque, set, map, or slot-map semantics;
- overwrite-on-full or drop-on-full behavior;
- sorting, uniqueness, coalescing, or duplicate checks;
- string, sentinel, UTF, truncation, or text policy;
- stable handles, generation counters, or tombstones;
- ABI, wire, or packed layout guarantees for the list value.

## Public namespace

`List` lives under `stdx.collections`:

```zig
stdx.collections.List
```

Source ownership:

```text
src/collections.zig
src/collections/list.zig
test/collections/list_test.zig
```

`src/collections.zig` re-exports:

```zig
pub const list = @import("collections/list.zig");

pub const List = list.List;
```

`src/stdx.zig` re-exports:

```zig
pub const collections = @import("collections.zig");

pub const List = collections.List;
```

## API

```zig
pub const List = struct {
    pub fn Bounded(comptime T: type) type;
};
```

Returned type:

```zig
pub const Self = struct {
    buffer: []T,
    count: usize = 0,

    pub const Error = error{Full, OutOfBounds};

    pub fn wrap(buffer: []T) Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn asSlice(self: *Self) []T;
    pub fn asConstSlice(self: *const Self) []const T;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn append(self: *Self, item: T) error{Full}!void;
    pub fn appendAssumeCapacity(self: *Self, item: T) void;
    pub fn appendSlice(self: *Self, items: []const T) error{Full}!void;

    pub fn insert(self: *Self, index: usize, item: T) Error!void;
    pub fn orderedRemove(self: *Self, index: usize) error{OutOfBounds}!T;
    pub fn swapRemove(self: *Self, index: usize) error{OutOfBounds}!T;
    pub fn pop(self: *Self) ?T;

    pub fn at(self: *Self, index: usize) error{OutOfBounds}!*T;
    pub fn constAt(self: *const Self, index: usize) error{OutOfBounds}!*const T;

    pub fn assertValid(self: *const Self) void;
};
```

There is no plain `remove` alias. Callers must choose `orderedRemove` when
relative order matters and `swapRemove` when `O(1)` removal is more important.

There is no `deinit` or `clearAndFree`; a bounded list does not own or release
its backing storage.

## Type and capacity contract

`T` MUST be a runtime value type with `@sizeOf(T) > 0`; a zero-sized element
type is a compile error.

`wrap(buffer)` returns an empty list backed by `buffer`. `buffer.len` is the
runtime item capacity. A zero-length buffer is valid; the list is both empty and
full.

A valid list satisfies:

```zig
list.count <= list.buffer.len
```

Only `buffer[0..count]` is initialized list content. `buffer[count..]` is spare
storage and may contain undefined bytes.

Direct field mutation must preserve the invariant and initialized-prefix rule.

## Ownership and lifetime

A bounded list borrows its backing storage. The caller owns the memory and must
keep it alive for the lifetime of the list and any slices or pointers returned
from it.

The list owns the initialized prefix contract while it is active. The caller must
not mutate `buffer[0..count]` through another alias unless the mutation preserves
all list invariants.

Copying a bounded list copies the slice pointer and `count`; it does not copy the
backing storage. Divergent mutable copies over the same buffer are outside this
primitive's contract. Use one authoritative mutable list value for each backing
buffer.

Do not store a `List.Bounded` field that points at another field in the same
outer struct. Moving the outer struct can leave the slice pointer referring to
the old address. Use `List.Static(T, N)` for embedded storage.

## Construction and clearing

`wrap(buffer)` is equivalent to:

```zig
.{ .buffer = buffer, .count = 0 }
```

`clearRetainingCapacity()` sets `count` to zero. It does not zero memory, call
destructors, release resources, or change the backing buffer.

## Capacity operations

`len()` returns `count`.

`capacity()` returns `buffer.len`.

`remaining()` returns `buffer.len - count`.

`isEmpty()` returns `count == 0`.

`isFull()` returns `count == buffer.len`.

These operations do not inspect spare storage.

## Slice and pointer access

`asSlice()` returns `buffer[0..count]`.

`asConstSlice()` returns `buffer[0..count]` as read-only storage.

`at(index)` returns a mutable pointer to `buffer[index]` or `error.OutOfBounds`
when `index >= count`.

`constAt(index)` returns a const pointer to `buffer[index]` or
`error.OutOfBounds` when `index >= count`.

Slices and pointers borrow from the caller-owned backing storage. Moving the
bounded list value does not move that storage, but mutations can still invalidate
indexes, pointers, and slices as documented below.

## Append and insert semantics

`append(item)` writes `item` to `buffer[count]` and increments `count`. It
returns `error.Full` and leaves the list unchanged when `isFull()`.

`appendAssumeCapacity(item)` performs the same mutation and asserts that the list
is not full.

`appendSlice(items)` appends all items in order. If `items.len > remaining()`, it
returns `error.Full` and leaves the list unchanged. Appending an empty slice
always succeeds.

`insert(index, item)` accepts `index <= count`. It shifts `buffer[index..count]`
one slot to the right, stores `item` at `index`, and increments `count`.

`insert` checks `index` before capacity:

- `index > count` returns `error.OutOfBounds` and leaves the list unchanged;
- `index <= count` on a full list returns `error.Full` and leaves the list
  unchanged.

## Removal semantics

`pop()` removes and returns the last item, or returns `null` when empty. The old
last slot becomes spare storage.

`orderedRemove(index)` removes and returns `buffer[index]`. It shifts following
items left by one slot and preserves relative order. It returns
`error.OutOfBounds` and leaves the list unchanged when `index >= count`.

`swapRemove(index)` removes and returns `buffer[index]`. It fills the vacated
slot with the old last item, decrements `count`, and does not preserve order. It
returns `error.OutOfBounds` and leaves the list unchanged when `index >= count`.
When `index` is the last valid index, `swapRemove` is equivalent to `pop().?`.

Vacated spare slots become undefined. The list never calls destructors; callers
own element resource lifetimes.

## Invalidation and ordering

Appending preserves existing element indexes, pointers, and slices into the
previous initialized prefix. Existing slices keep their original length and do
not include newly appended items.

`insert(index, item)` invalidates indexes, pointers, and slices at and after
`index`.

`orderedRemove(index)` invalidates indexes, pointers, and slices at and after
`index`.

`swapRemove(index)` invalidates the removed index and the old last index. If
`index` is not the old last index, the item formerly at the last index moves to
`index`. Other indexes and pointers remain valid.

`clearRetainingCapacity()` invalidates all indexes and all initialized-element
pointers and slices previously returned by the list.

Iteration order is the order of `asConstSlice()`. Only `orderedRemove` preserves
relative order across removal.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `Bounded` | never | never | comptime | none | type factory | none |
| `wrap` | never | never | O(1) | none | caller-owned buffer | empty |
| capacity helpers | never | never | O(1) | none | caller-owned buffer | none |
| `asSlice` | never | never | O(1) | none | caller-owned buffer | current order |
| `asConstSlice` | never | never | O(1) | none | caller-owned buffer | current order |
| `clearRetainingCapacity` | never | never | O(1) | all elements | caller-owned buffer | empty |
| `append` | never | never | O(1) | none | caller-owned buffer | appends last |
| `appendAssumeCapacity` | never | never | O(1) | none | caller-owned buffer | appends last |
| `appendSlice` | never | never | O(items.len) | none | caller-owned buffer | appends in order |
| `insert` | never | never | O(len) | at/after index | caller-owned buffer | preserves order |
| `orderedRemove` | never | never | O(len) | at/after index | caller-owned buffer | preserves order |
| `swapRemove` | never | never | O(1) | index and old last | caller-owned buffer | unordered |
| `pop` | never | never | O(1) | old last | caller-owned buffer | removes last |
| `at` | never | never | O(1) | none | caller-owned buffer | none |
| `constAt` | never | never | O(1) | none | caller-owned buffer | none |
| `assertValid` | never | never | O(1) | none | caller-owned buffer | none |

These operations perform no heap allocation, waiting, hidden global access,
atomics, barriers, volatile access, target probing, syscalls, locks, or I/O.

## Error behavior

- full-capacity append, append-slice, and insert return `error.Full`;
- out-of-bounds insert, remove, and pointer access return `error.OutOfBounds`;
- `pop()` uses `null` for empty instead of an error;
- `appendAssumeCapacity` reports full capacity as a programmer error;
- a zero-sized `T` is a compile error;
- a corrupted `count` violates the caller contract; `assertValid` asserts the
  capacity invariant.

All error returns leave the list unchanged.

## Debug assertion behavior

`assertValid()` asserts `count <= buffer.len`.

## Implementation constraints

Implementation must:

- store only the caller buffer slice and initialized item count in `Self`;
- never store an allocator, vtable, policy flag, or owned backing pointer;
- never allocate, reserve, grow, shrink, or free backing storage;
- update `count` only after bounds and capacity checks succeed;
- leave the list unchanged on error;
- use overlap-safe moves for insert and ordered removal;
- never read or expose spare storage as initialized elements;
- avoid self-referential owner layouts that would stale the backing slice;
- avoid hidden globals, atomics, fences, volatile operations, target probes, and I/O.

## Testing

Tests MUST wrap empty, partial, full, and zero-length backing slices to verify
that runtime capacity equals `buffer.len`. They MUST verify the capacity helpers
and `error.Full`; compile-fail coverage for zero-sized `T` proves the element
type boundary.

Mutation tests MUST append individual items and slices, insert at the first,
middle, and terminal valid indexes, and remove from each applicable index.
They MUST compare the initialized prefix in the caller buffer after each
operation. These tests prove insertion order, ordered removal, swap removal,
and no mutation after each reported `error.Full` or `error.OutOfBounds`.

Access and ownership tests MUST compare `asSlice`, `asConstSlice`, `at`, and
`constAt` with the initialized prefix, verify out-of-bounds errors, and show
that mutable access changes the caller buffer. They MUST retain views and
pointers across append, insert, each removal form, and clear. Invalidation
checks MUST verify the documented stable and invalidated ranges without
dereferencing an invalid view. Copy and move checks MUST establish that the
backing buffer does not move and that divergent mutable copies are excluded.

Invariant tests MUST call `assertValid` after mutation sequences, including
sequences that fill, drain, and refill the list. Where assertions can be
observed, a deliberately invalid `count` MUST make `assertValid` fail. These
tests prove the initialized-prefix and capacity invariants.
