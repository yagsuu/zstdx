# Collections bounded list

Status: Approved.

`stdx.collections.List.Bounded(T)` is a caller-storage-backed sequence with
runtime capacity. It preserves insertion order by default and never allocates.

The root facade may expose the same family as `stdx.List.Bounded(T)`.

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

`T` must be a runtime value type with `@sizeOf(T) > 0`. Zero-sized element types
are compile errors where practical.

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
- invalid `T` categories are compile errors where practical;
- corrupted `count` is a programmer error caught by `assertValid` where practical.

All error returns leave the list unchanged.

## Debug assertion behavior

`assertValid()` asserts `count <= buffer.len`.

Public mutating operations may call `assertValid()` before and after mutation
when `core.checksEnabled(opts.safety)` or an equivalent module safety option
requires runtime invariant checks.

## Implementation constraints

Implementation must:

- store only the caller buffer slice and initialized item count in `Self`;
- never store an allocator, vtable, policy flag, or owned backing pointer;
- never allocate, reserve, grow, shrink, or free backing storage;
- update `count` only after bounds and capacity checks succeed;
- leave the list unchanged on error;
- use overlap-safe moves for insert and ordered removal;
- never read or expose spare storage as initialized elements;
- set vacated spare slots to `undefined` where practical;
- avoid self-referential owner layouts that would stale the backing slice;
- avoid hidden globals, atomics, fences, volatile operations, target probes, and I/O.

## Planned consumers

`zacpi` root table validation can materialize `Sdt.Table` references into a
caller-owned scratch slice and return the initialized prefix as a borrowed view.

`zfw` has GCD and memory-manager tables with the same initialized-prefix
operations. Inline compile-time-capacity cases map to `List.Static`; any
caller-provided scratch variant maps to `List.Bounded`.

`zvm` has memory maps and temporary duplicate-detection lists with the same
capacity-first mutation pattern. Inline fixed arrays map to `List.Static`; caller
scratch lists can use `List.Bounded` when capacity is supplied by the caller.

## Examples

```zig
const stdx = @import("stdx");

const TableList = stdx.List.Bounded(Table);

var scratch: [16]Table = undefined;
var tables = TableList.wrap(scratch[0..]);

try tables.append(table0);
try tables.append(table1);

const indexed = tables.asConstSlice();
_ = indexed;
```

```zig
const EntryList = stdx.List.Bounded(Entry);

const storage = try arena.allocSlice(Entry, entry_count);
var entries = EntryList.wrap(storage);

try entries.appendSlice(initial_entries);
const removed = try entries.orderedRemove(0);
_ = removed;
```

## Required tests

### Construction and capacity

- `wrap(buffer)` starts empty;
- `capacity()` equals `buffer.len`;
- zero-length buffers are both empty and full;
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
- append preserves earlier element addresses in the same backing buffer;
- moving the bounded list value does not move the backing buffer;
- copying the bounded list value is safe for read-only access but divergent
  mutable copies are outside the contract;
- insert and ordered removal invalidate at and after the mutation point;
- swap removal preserves unrelated element addresses where practical;
- `clearRetainingCapacity` invalidates all prior initialized-element views;
- `assertValid` succeeds after every public mutation sequence;
- `assertValid` catches a manually corrupted `count` where practical.

## Open questions

None.
