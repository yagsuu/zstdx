# Collections static list

Status: Approved.

`stdx.collections.List.Static(T, N)` is an inline fixed-capacity sequence.
It owns its storage, preserves insertion order by default, and never allocates.

The root facade may expose the same family as `stdx.List.Static(T, N)`.

## Owned scope

This spec owns:

- `collections.List.Static(T, N)`;
- inline `[N]T` storage and initialized-prefix tracking;
- append, insert, pop, ordered removal, and swap removal;
- slice exposure for the initialized prefix;
- capacity, invalidation, ordering, and full-capacity behavior;
- required tests.

This spec does not own:

- caller-provided storage or runtime capacity; use `List.Bounded` for that;
- managed or unmanaged heap allocation;
- ring, queue, stack, deque, set, map, or slot-map semantics;
- overwrite-on-full or drop-on-full behavior;
- sorting, uniqueness, coalescing, or duplicate checks;
- string, sentinel, UTF, or text policy;
- stable handles, generation counters, or tombstones;
- ABI, wire, or packed layout guarantees for the list value.

## Public namespace

`List` lives under `stdx.collections`:

```zig
stdx.collections.List
```

It is root-promoted by the first-slice root facade:

```zig
stdx.List
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

## Approved API

```zig
pub const List = struct {
    pub fn Static(comptime T: type, comptime capacity_items: usize) type;
};
```

Returned type:

```zig
pub const Self = struct {
    buffer: [capacity_items]T = undefined,
    count: usize = 0,

    pub const Error = error{Full, OutOfBounds};
    pub const item_capacity = capacity_items;

    pub fn init() Self;

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

## Type and capacity contract

`T` must be a runtime value type with `@sizeOf(T) > 0`. Zero-sized element types
are compile errors where practical.

`capacity_items` is a comptime item count. `Static(T, 0)` is valid; it is both
empty and full.

A valid list satisfies:

```zig
list.count <= item_capacity
```

Only `buffer[0..count]` is initialized list content. `buffer[count..]` is spare
storage and may contain undefined bytes.

Direct field mutation must preserve the invariant and initialized-prefix rule.

## Construction and clearing

`init()` is equivalent to `.{}`. Both create an empty list with uninitialized
spare storage.

`clearRetainingCapacity()` sets `count` to zero. It does not zero memory, call
destructors, release resources, or change `item_capacity`.

There is no `clearAndFree`; a static list has no heap allocation to release.

## Capacity operations

`len()` returns `count`.

`capacity()` returns `item_capacity`.

`remaining()` returns `item_capacity - count`.

`isEmpty()` returns `count == 0`.

`isFull()` returns `count == item_capacity`.

These operations do not inspect spare storage.

## Slice and pointer access

`asSlice()` returns `buffer[0..count]`.

`asConstSlice()` returns `buffer[0..count]` as read-only storage.

`at(index)` returns a mutable pointer to `buffer[index]` or `error.OutOfBounds`
when `index >= count`.

`constAt(index)` returns a const pointer to `buffer[index]` or
`error.OutOfBounds` when `index >= count`.

Slices and pointers borrow from the list value. Moving or copying the list value
invalidates pointers and slices into the old value.

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

Appending preserves existing element indexes, pointers, and slices while the list
value stays at the same address.

`insert(index, item)` invalidates indexes, pointers, and slices at and after
`index`.

`orderedRemove(index)` invalidates indexes, pointers, and slices at and after
`index`.

`swapRemove(index)` invalidates the removed index and the old last index. If
`index` is not the old last index, the item formerly at the last index moves to
`index`. Other indexes and pointers remain valid while the list value stays at
the same address.

`clearRetainingCapacity()` invalidates all indexes and all initialized-element
pointers and slices previously returned by the list.

Iteration order is the order of `asConstSlice()`. Only `orderedRemove` preserves
relative order across removal.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `Static` | never | never | comptime | none | type factory | none |
| `init` | never | never | O(1) | none | caller-owned value | empty |
| capacity helpers | never | never | O(1) | none | caller-owned value | none |
| `asSlice` | never | never | O(1) | none | caller-owned value | current order |
| `asConstSlice` | never | never | O(1) | none | caller-owned value | current order |
| `clearRetainingCapacity` | never | never | O(1) | all elements | caller-owned value | empty |
| `append` | never | never | O(1) | none | caller-owned value | appends last |
| `appendAssumeCapacity` | never | never | O(1) | none | caller-owned value | appends last |
| `appendSlice` | never | never | O(items.len) | none | caller-owned value | appends in order |
| `insert` | never | never | O(len) | at/after index | caller-owned value | preserves order |
| `orderedRemove` | never | never | O(len) | at/after index | caller-owned value | preserves order |
| `swapRemove` | never | never | O(1) | index and old last | caller-owned value | unordered |
| `pop` | never | never | O(1) | old last | caller-owned value | removes last |
| `at` | never | never | O(1) | none | caller-owned value | none |
| `constAt` | never | never | O(1) | none | caller-owned value | none |
| `assertValid` | never | never | O(1) | none | caller-owned value | none |

These operations perform no heap allocation, waiting, hidden global access,
atomics, barriers, volatile access, target probing, syscalls, locks, or I/O.

## Error behavior

- full-capacity append, append-slice, and insert return `error.Full`;
- out-of-bounds insert, remove, and pointer access return `error.OutOfBounds`;
- `pop()` uses `null` for empty instead of an error;
- `appendAssumeCapacity` reports full capacity as a programmer error;
- invalid `T` categories are compile errors where practical;
- corrupted `count` is a programmer error caught by `assertValid` where practical.

All error returns leave the list unchanged.

## Debug assertion behavior

`assertValid()` asserts `count <= item_capacity`.

Public mutating operations may call `assertValid()` before and after mutation
when `core.checksEnabled(opts.safety)` or an equivalent module safety option
requires runtime invariant checks.

## Implementation constraints

Implementation must:

- store only inline element storage and the initialized item count in `Self`;
- never store an allocator, vtable, policy flag, or external backing pointer;
- never allocate, reserve, grow, shrink, or free backing storage;
- update `count` only after bounds and capacity checks succeed;
- leave the list unchanged on error;
- use overlap-safe moves for insert and ordered removal;
- never read or expose spare storage as initialized elements;
- set vacated spare slots to `undefined` where practical;
- avoid hidden globals, atomics, fences, volatile operations, target probes, and I/O.

## Planned use

Fixed-capacity handle, protocol, event, relocation, memory-map, and variable
tables shaped as `[max_entries]Entry` plus an initialized-item count. Small
fixed diagnostic buffers and parser scratch reuse the same
initialized-prefix model when text-specific behavior is not required.

## Examples

```zig
const stdx = @import("stdx");

const EventList = stdx.List.Static(Event, 64);

var events = EventList.init();
try events.append(.{ .id = 1 });
try events.insert(0, .{ .id = 0 });

const removed_ordered = try events.orderedRemove(0);
_ = removed_ordered;

const removed_unordered = try events.swapRemove(0);
_ = removed_unordered;
```

```zig
const FreeList = stdx.List.Static(u16, 32);

var free = FreeList.init();
free.appendAssumeCapacity(7);
free.appendAssumeCapacity(9);

const slot = free.pop() orelse unreachable;
_ = slot;
```

## Required tests

### Construction and capacity

- default struct literal is empty;
- `init()` is empty;
- `Static(T, 0)` is both empty and full;
- `len`, `capacity`, `remaining`, `isEmpty`, and `isFull` cover empty, partial,
  full, and zero-capacity lists;
- zero-sized `T` fails to compile where the compile-fail harness supports it.

### Append and insert

- `append` succeeds into empty and non-empty lists;
- `append` returns `error.Full` without mutation when full;
- `appendAssumeCapacity` appends after a caller capacity check;
- `appendSlice` succeeds for empty, partial, exact-fill, and empty-source cases;
- `appendSlice` returns `error.Full` without mutation when the whole slice does
  not fit;
- `insert` covers front, middle, and end insertion;
- `insert` returns `error.OutOfBounds` for `index > len` without mutation;
- `insert` returns `error.Full` for valid indexes in a full list without mutation.

### Removal

- `pop` returns `null` when empty;
- `pop` returns items from the end;
- `orderedRemove` covers front, middle, and last indexes;
- `orderedRemove` preserves relative order;
- `swapRemove` covers middle and last indexes;
- `swapRemove` moves the old last item into the removed slot when needed;
- both remove methods return `error.OutOfBounds` without mutation for invalid
  indexes.

### Access, invalidation, and invariants

- `asSlice` exposes initialized items and allows element mutation;
- `asConstSlice` exposes initialized items read-only;
- `at` and `constAt` cover valid and out-of-bounds indexes;
- append preserves earlier element addresses while the list value is not moved;
- insert and ordered removal invalidate at and after the mutation point;
- swap removal preserves unrelated element addresses where practical;
- `assertValid` succeeds after every public mutation sequence;
- `assertValid` catches a manually corrupted `count` where practical.

## Open questions

None.
