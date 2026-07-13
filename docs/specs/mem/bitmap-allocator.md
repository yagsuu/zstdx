# Memory bitmap allocator

Status: Approved.

`stdx.mem.BitmapAllocator` is a fixed-unit resource allocator backed by a
bitmap. It tracks abstract unit indexes and contiguous unit ranges; it does not
own the resources those indexes name.

The allocator is for frame indexes, descriptor slots, table entries, command
slots, and similar fixed-size resource domains where allocation state is a bit
per unit. It never allocates backing memory and never performs resource-specific
policy.

## Owned scope

This spec owns:

- `mem.BitmapAllocator.Static(unit_capacity)`;
- `mem.BitmapAllocator.Bounded`;
- bitmap-backed fixed-unit allocation state;
- single-unit and contiguous-range allocation;
- explicit reserve and free of caller-selected ranges;
- exhaustion, bounds, double-reserve, and double-free behavior;
- no-mutation-on-error behavior;
- unused-bit invariants;
- required tests.

This spec does not own:

- BestFit, WorstFit, FirstFit as a reusable policy family, or Buddy algorithms;
- byte allocation, typed allocation, object construction, or destructors;
- physical memory map ownership;
- virtual memory policy;
- DMA or IOMMU mapping policy;
- page-size semantics;
- dynamic heap-owned bitmaps;
- atomic or concurrent bitmap allocation;
- poisoning, statistics, tracing, or leak detection;
- managed or unmanaged allocator handles.

## Public namespace

`BitmapAllocator` lives under `stdx.mem`:

```zig
stdx.mem.BitmapAllocator
stdx.mem.BitmapAllocator.Static
stdx.mem.BitmapAllocator.Bounded
```

It is not root-promoted:

```zig
stdx.BitmapAllocator // not exported
```

Source ownership:

```text
src/mem.zig
src/mem/bitmap.zig
test/mem/bitmap_test.zig
```

`src/mem.zig` re-exports:

```zig
pub const bitmap = @import("mem/bitmap.zig");

pub const BitmapAllocator = bitmap.BitmapAllocator;
```

## Approved API

```zig
pub const BitmapAllocator = struct {
    pub fn Static(comptime capacity_units: usize) type;

    pub const Bounded = struct {
        words: []Word,
        unit_capacity: usize,

        pub const Word = u64;
        pub const word_bits = @bitSizeOf(Word);
        pub const Range = stdx.core.Range(usize);
        pub const WrapError = error{OutOfBounds};
        pub const AllocError = error{OutOfMemory};
        pub const ReserveError = error{ OutOfBounds, AlreadyAllocated };
        pub const FreeError = error{ OutOfBounds, NotAllocated };
        pub const Error = WrapError || AllocError || ReserveError || FreeError;

        pub fn wrap(words: []Word, unit_capacity: usize) WrapError!Bounded;
        pub fn clearRetainingCapacity(self: *Bounded) void;

        pub fn capacity(self: Bounded) usize;
        pub fn allocated(self: Bounded) usize;
        pub fn remaining(self: Bounded) usize;
        pub fn isEmpty(self: Bounded) bool;
        pub fn isFull(self: Bounded) bool;

        pub fn isAllocated(self: Bounded, index: usize) bool;
        pub fn isFree(self: Bounded, index: usize) bool;

        pub fn allocOne(self: *Bounded) AllocError!usize;
        pub fn allocRange(self: *Bounded, count: usize) AllocError!Range;
        pub fn reserveOne(self: *Bounded, index: usize) ReserveError!void;
        pub fn reserveRange(self: *Bounded, range: Range) ReserveError!void;
        pub fn freeOne(self: *Bounded, index: usize) FreeError!void;
        pub fn freeRange(self: *Bounded, range: Range) FreeError!void;

        pub fn isValid(self: Bounded) bool;
        pub fn assertValid(self: Bounded) void;
    };
};
```

`Static(unit_capacity)` returns a type with inline word storage and the same
query, allocation, reserve, free, validation, and clear operations as `Bounded`.
It uses `init()` as its constructor instead of `wrap(...)`:

```zig
pub const Self = struct {
    words: [word_count]Word = [_]Word{0} ** word_count,

    pub const Word = u64;
    pub const word_bits = @bitSizeOf(Word);
    pub const unit_capacity = capacity_units;
    pub const word_count = capacity_units / word_bits +
        @intFromBool(capacity_units % word_bits != 0);
    pub const Range = stdx.core.Range(usize);
    pub const Error = BitmapAllocator.Bounded.Error;

    pub fn init() Self;

    // Same non-construction methods as BitmapAllocator.Bounded.
};
```

## Unit model

A unit is an abstract resource slot identified by an index.

Valid unit indexes are:

```text
0 <= index < capacity()
```

A contiguous allocation returns a half-open `Range(usize)`:

```text
[start, end)
```

The bitmap allocator does not know what a unit represents. A unit may name a
frame number, descriptor slot, table entry, command tag, object index, or any
other fixed-size resource chosen by the caller.

## Storage model

`Static(unit_capacity)` owns inline bitmap words. A default struct literal and
`init()` both produce an empty allocator.

`Bounded.wrap(words, unit_capacity)` borrows `words`, clears every borrowed word,
and returns an empty allocator over the first `unit_capacity` units. It returns
`error.OutOfBounds` when `unit_capacity > words.len * word_bits`.

For both variants, direct mutation of `words` must preserve the unused-bit
invariant and allocation-state invariants.

## Capacity and counts

`capacity()` returns the fixed unit capacity.

`allocated()` returns the number of allocated units.

`remaining()` returns the number of free units.

The following invariant must hold for every valid allocator:

```zig
allocated() + remaining() == capacity()
```

`isEmpty()` returns `allocated() == 0`.

`isFull()` returns `remaining() == 0`.

For zero-capacity allocators, both `isEmpty()` and `isFull()` return `true`.

`clearRetainingCapacity()` clears every allocated unit. Capacity and backing
storage identity do not change.

## Unused-bit invariant

When `capacity()` is not a multiple of `word_bits`, the final logical word has
unused high bits. Those bits must always be zero after every public operation.

Words beyond the logical capacity in a `Bounded` allocator are borrowed storage,
but their bits are not allocatable units. `wrap` clears them. Public operations
must not expose them as allocated or free units.

`assertValid()` asserts that unused high bits are zero and that
`unit_capacity <= words.len * word_bits` for `Bounded`.

`isValid()` returns whether those structural invariants hold.

## Query semantics

`isAllocated(index)` returns true only when `index < capacity()` and the unit is
allocated. It returns false for out-of-bounds indexes.

`isFree(index)` returns true only when `index < capacity()` and the unit is free.
It returns false for out-of-bounds indexes.

## Allocation semantics

`allocOne()` allocates and returns the lowest-index free unit.

If no free unit exists, it returns `error.OutOfMemory` and does not mutate the
allocator.

`allocRange(count)` allocates a contiguous range of `count` units. It returns the
lowest-index free range of exactly that length.

`allocRange(0)` returns `Range.empty(0)` and does not mutate the allocator.

If `count > 0` and no contiguous free run of `count` units exists, `allocRange`
returns `error.OutOfMemory` and does not mutate the allocator. This includes the
case where enough units are free in total but fragmentation prevents one
contiguous range.

The placement policy is deterministic lowest-index first-fit. This spec does not
approve BestFit, WorstFit, Buddy, random, rotating, or hint-based placement.
Those algorithms are owned by later allocation-algorithm specs.

## Reserve semantics

`reserveOne(index)` marks a caller-selected unit allocated.

It returns:

- `error.OutOfBounds` when `index >= capacity()`;
- `error.AlreadyAllocated` when the unit is already allocated.

On error, it does not mutate the allocator.

`reserveRange(range)` marks every unit in `range` allocated.

`range` must be a valid `Range(usize)`. Passing an invalid range value is a
programmer error.

An empty range is a no-op when `range.start <= capacity()`.

A non-empty or empty range with `range.end > capacity()` returns
`error.OutOfBounds` and does not mutate the allocator.

If any unit in `range` is already allocated, `reserveRange` returns
`error.AlreadyAllocated` and does not mutate the allocator. Implementations must
validate the whole range before setting any bit.

## Free semantics

`freeOne(index)` marks a caller-selected unit free.

It returns:

- `error.OutOfBounds` when `index >= capacity()`;
- `error.NotAllocated` when the unit is already free.

On error, it does not mutate the allocator.

`freeRange(range)` marks every unit in `range` free.

`range` must be a valid `Range(usize)`. Passing an invalid range value is a
programmer error.

An empty range is a no-op when `range.start <= capacity()`.

A non-empty or empty range with `range.end > capacity()` returns
`error.OutOfBounds` and does not mutate the allocator.

If any unit in `range` is already free, `freeRange` returns
`error.NotAllocated` and does not mutate the allocator. Implementations must
validate the whole range before clearing any bit.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| construction | never | never | O(word_count) | none | caller-owned value/storage | none |
| count/query | never | never | O(word_count) for counts, O(1) for single-index predicates | none | caller-owned value/storage | none |
| `allocOne` | never | never | O(word_count) | none | caller-owned value/storage | lowest free index |
| `allocRange` | never | never | O(capacity) | none | caller-owned value/storage | lowest first-fit range |
| reserve/free one | never | never | O(1) | target unit only | caller-owned value/storage | explicit index |
| reserve/free range | never | never | O(range.len()) | target range only | caller-owned value/storage | explicit range |
| clear | never | never | O(word_count) | every allocated unit | caller-owned value/storage | empty |
| validation | never | never | O(word_count) | none | caller-owned value/storage | none |

The bitmap allocator performs no hidden allocation, waiting, sleeping, spinning,
blocking, syscalls, target probing, atomics, barriers, volatile access, or hidden
global access.

Concurrent mutation is outside the contract. Callers must externally synchronize
shared allocators. Immutable queries over immutable allocator values require no
synchronization beyond ordinary Zig aliasing rules.

Returned unit indexes and ranges are logical resource IDs. Allocating or freeing
other units does not move allocated units and does not invalidate unrelated unit
indexes or ranges. Freeing a unit or range invalidates the caller's claim to that
resource.

## Error behavior

`Error` is:

```zig
error{
    OutOfMemory,
    OutOfBounds,
    AlreadyAllocated,
    NotAllocated,
}
```

`OutOfMemory` means an allocation request cannot be satisfied from the current
free bitmap state.

`OutOfBounds` means a caller-selected index or range is outside the allocator's
capacity, or `Bounded.wrap` received a capacity larger than the borrowed word
storage can represent.

`AlreadyAllocated` means reserve would overlap an allocated unit.

`NotAllocated` means free would overlap a free unit.

Every error-returning operation must leave the allocator unchanged on error.

Malformed receiver state is a programmer error. Operations may call
`assertValid()` when `stdx.core.debug.checksEnabled` or an equivalent module
safety option requires runtime invariant checks.

## Implementation constraints

Implementations must:

- use `u64` words;
- support zero-capacity allocators;
- compute word counts and `words.len * word_bits` without unchecked overflow;
- keep unused high bits clear after every public operation;
- preflight reserve/free ranges before mutating any bit;
- avoid public bit-scan wrappers around Zig builtins;
- avoid target-specific branches;
- avoid hidden allocation and hidden global state.

Implementations may share private helper code with `stdx.bits.BitSet.Static`, but
`BitmapAllocator` owns its public semantics.

## Consumer requirements

A caller that maps units to external resources owns the resource mapping and the
lifetime of those resources. The bitmap allocator only records allocation state.

Resource cleanup is the caller's responsibility. `freeOne`, `freeRange`, and
`clearRetainingCapacity` do not call destructors, release handles, unmap memory,
flush caches, notify devices, or zero resource contents.

Physical frame allocation, virtual address management, DMA mapping, descriptor
construction, and scheduler policy belong to downstream packages or later
approved specs.

## Required tests

Required capacities:

- `Static(0)`;
- `Static(1)`;
- `Static(64)`;
- `Static(65)`;
- a non-word multiple such as `Static(129)`;
- `Bounded` with zero-capacity storage;
- `Bounded` with a runtime capacity smaller than `words.len * word_bits`.

### Construction and capacity

- `Static.init()` is empty;
- a default `Static` struct literal is empty;
- `Bounded.wrap` clears borrowed words;
- `Bounded.wrap` rejects `unit_capacity > words.len * word_bits` with
  `error.OutOfBounds`;
- rejected `Bounded.wrap` leaves borrowed words unchanged;
- zero-capacity allocators are both empty and full;
- `allocated() + remaining() == capacity()` after construction.

### Single-unit allocation

- `allocOne` returns the lowest free index;
- repeated `allocOne` returns ascending indexes from an empty allocator;
- `allocOne` returns `error.OutOfMemory` without mutation when full;
- `reserveOne` succeeds for a free index;
- `reserveOne` rejects out-of-bounds indexes with `error.OutOfBounds`;
- `reserveOne` rejects an allocated index with `error.AlreadyAllocated` without
  mutation;
- `freeOne` succeeds for an allocated index;
- `freeOne` rejects out-of-bounds indexes with `error.OutOfBounds`;
- `freeOne` rejects a free index with `error.NotAllocated` without mutation;
- `isAllocated` and `isFree` return false for out-of-bounds indexes.

### Range allocation

- `allocRange(0)` returns an empty range and does not mutate;
- `allocRange(1)` is consistent with `allocOne`;
- `allocRange` returns the lowest contiguous first-fit range;
- `allocRange` can allocate a range ending at `capacity()`;
- `allocRange` returns `error.OutOfMemory` without mutation when capacity is
  exhausted;
- fragmented free space with enough total free units but no sufficient
  contiguous run returns `error.OutOfMemory` without mutation.

### Explicit reserve and free ranges

- `reserveRange` succeeds for an in-bounds free non-empty range;
- `reserveRange` accepts an in-bounds empty range as a no-op;
- `reserveRange` rejects out-of-bounds ranges with `error.OutOfBounds` without
  mutation;
- `reserveRange` rejects any overlap with allocated units using
  `error.AlreadyAllocated` without mutation;
- `freeRange` succeeds for an allocated non-empty range;
- `freeRange` accepts an in-bounds empty range as a no-op;
- `freeRange` rejects out-of-bounds ranges with `error.OutOfBounds` without
  mutation;
- `freeRange` rejects any overlap with free units using `error.NotAllocated`
  without mutation.

### Counts, clearing, and invariants

- `allocated`, `remaining`, `isEmpty`, and `isFull` cover empty, partial, full,
  and zero-capacity states;
- `clearRetainingCapacity` clears all units and preserves capacity;
- `assertValid` succeeds after every public mutation;
- unused high bits remain clear after allocation, reserve, free, and clear;
- corrupted unused high bits are detected by `assertValid` where practical.

### Model tests

A model test compares `Static` and `Bounded` behavior against a simple bool-array
allocator over randomized sequences of:

- `allocOne`;
- `allocRange`;
- `reserveOne`;
- `reserveRange`;
- `freeOne`;
- `freeRange`;
- `clearRetainingCapacity`.

The model must assert identical success/error results, allocated unit sets,
counts, and no-mutation-on-error behavior.

## Open questions

None.
