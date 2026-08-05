# Allocation placement algorithms

Status: Approved.

`stdx.algo.allocation` owns pure allocation-placement algorithms over abstract
unit ranges. These algorithms select where an allocation would fit; they do not
own allocator storage and do not mutate caller state.

The algorithms are for allocator implementations that already maintain their own
free-range, bitmap, buddy, or extent state and need deterministic placement
rules with explicit tie-breaks.

## Owned scope

This spec owns:

- `algo.allocation.FirstFit`;
- `algo.allocation.BestFit`;
- `algo.allocation.WorstFit`;
- `algo.allocation.Buddy`;
- shared `Request` and `Selection` value shapes;
- selection semantics over caller-provided free ranges;
- buddy block/order arithmetic;
- alignment, overflow, no-fit, and tie-break behavior;
- no-allocation, no-waiting, and no-mutation behavior;
- required tests.

This spec does not own:

- allocators that own free lists, bitmaps, arenas, pages, or memory maps;
- `mem.alloc.BuddyAllocator` storage and free-list management;
- physical or virtual memory policy;
- DMA or IOMMU policy;
- page-size policy;
- object construction or destruction;
- managed or unmanaged heap allocation;
- randomized, rotating, next-fit, hint-based, slab, TLSF, segregated-list, or
  weighted policies;
- concurrency, atomics, locks, barriers, or wait behavior.

## Public namespace

Allocation placement algorithms live under `stdx.algo.allocation`:

```zig
stdx.algo.allocation
stdx.algo.allocation.FirstFit
stdx.algo.allocation.BestFit
stdx.algo.allocation.WorstFit
stdx.algo.allocation.Buddy
```

They are not exported from `stdx.mem` because they are not allocators. They are
not root-promoted:

```zig
stdx.FirstFit // not exported
stdx.mem.FirstFit // not exported
```

Source ownership:

```text
src/algo.zig
src/algo/allocation.zig
test/algo/allocation_test.zig
```

`src/algo.zig` re-exports:

```zig
pub const allocation = @import("algo/allocation.zig");
```

## Approved API

```zig
pub const allocation = struct {
    pub const Range = stdx.core.Range(usize);

    pub const Error = error{
        InvalidRequest,
        InvalidAlignment,
        Overflow,
    };

    pub const Request = struct {
        len: usize,
        alignment: usize = 1,
    };

    pub const Selection = struct {
        /// Index of the source free range in the `free_ranges` input slice.
        index: usize,
        range: Range,
        prefix: Range,
        suffix: Range,
    };

    pub const FirstFit = struct {
        pub fn select(free_ranges: []const Range, request: Request) Error!?Selection;
    };

    pub const BestFit = struct {
        pub fn select(free_ranges: []const Range, request: Request) Error!?Selection;
    };

    pub const WorstFit = struct {
        pub fn select(free_ranges: []const Range, request: Request) Error!?Selection;
    };

    pub const Buddy = struct {
        pub const Block = struct {
            start: usize,
            order: u8,
        };

        pub fn blockSize(order: u8) Error!usize;
        pub fn orderForLen(len: usize) Error!u8;
        pub fn contains(block: Block, index: usize) Error!bool;
        pub fn buddyOf(block: Block) Error!Block;
        pub fn parentOf(block: Block) Error!Block;
        pub fn split(block: Block) Error![2]Block;
        pub fn canCoalesce(left: Block, right: Block) bool;
    };
};
```

## Unit and range model

All sizes, starts, and alignments are measured in caller-defined units.

A unit may represent a byte, frame, page, slot, descriptor, table entry, or any
other fixed-size resource chosen by the caller. This spec does not know the unit
size and does not convert units to bytes.

Free extents are `stdx.core.Range(usize)` values with half-open semantics:

```text
[start, end)
```

Selection algorithms accept a slice of free ranges:

```zig
[]const Range
```

The free-range slice must satisfy all of these caller contracts:

- each range is valid;
- each range is non-empty;
- ranges are sorted by ascending `start`;
- ranges do not overlap;
- ranges are expressed in the same unit domain as the request.

Invalid free-range slices are programmer errors. These algorithms are not free
list validators.

## Request semantics

`Request.len` is the number of contiguous units requested.

`Request.len == 0` returns `error.InvalidRequest`.

`Request.alignment` is the required alignment in units. It must be non-zero and a
power of two. Invalid alignment returns `error.InvalidAlignment`.

For each source range, the candidate start is:

```zig
alignUp(source.start, request.alignment)
```

The candidate end is:

```zig
candidate_start + request.len
```

Both computations must be checked. Arithmetic overflow returns `error.Overflow`.

A candidate fits a source range when:

```zig
candidate_end <= source.end
```

If no candidate fits, `select` returns `null`. No-fit is not an error because
these algorithms do not allocate; owning allocators may map `null` to their own
exhaustion error.

## Selection shape

`Selection.index` is the index of the source free range inside the `free_ranges`
input slice.

`Selection.range` is the chosen allocation range.

`Selection.prefix` is the free part before `range` in the source range:

```text
[source.start, selection.range.start)
```

`Selection.suffix` is the free part after `range` in the source range:

```text
[selection.range.end, source.end)
```

`prefix`, `range`, and `suffix` exactly partition the source range. `prefix` and
`suffix` may be empty.

Selection algorithms never mutate `free_ranges`. Callers own any free-list,
bitmap, tree, or allocator mutation based on the returned `Selection`.

## `FirstFit` semantics

`FirstFit.select(free_ranges, request)` scans `free_ranges` in slice order and
returns the first fitting candidate.

Because the free-range caller contract requires ascending `start` order,
`FirstFit` chooses the lowest source-range index that can satisfy the request.

Within a source range, placement is the lowest aligned start that fits.

## `BestFit` semantics

`BestFit.select(free_ranges, request)` chooses the fitting candidate with the
smallest total leftover units.

For a candidate, leftover units are:

```zig
selection.prefix.len() + selection.suffix.len()
```

Tie-breaks are, in order:

1. lowest `selection.range.start`;
2. lowest `selection.index`.

Within a source range, placement is the lowest aligned start that fits.

## `WorstFit` semantics

`WorstFit.select(free_ranges, request)` chooses the fitting candidate with the
largest total leftover units.

For a candidate, leftover units are:

```zig
selection.prefix.len() + selection.suffix.len()
```

Tie-breaks are, in order:

1. lowest `selection.range.start`;
2. lowest `selection.index`.

Within a source range, placement is the lowest aligned start that fits.

## Buddy block model

`Buddy` owns block/order arithmetic for buddy-style allocators. It does not own a
free-list structure and does not allocate or free blocks.

A buddy block is:

```zig
Buddy.Block{ .start = start, .order = order }
```

`order` names a block size in units:

```zig
blockSize(order) == 1 << order
```

A valid block satisfies:

- `blockSize(order)` is representable in `usize`;
- `start` is aligned to `blockSize(order)`;
- `start + blockSize(order)` is representable in `usize`.

Passing an invalid block to operations that require a valid block is a programmer
error. Implementations may assert validity in checked modes.

## Buddy operation semantics

`blockSize(order)` returns `1 << order`. It returns `error.Overflow` when the
shift is not representable in `usize`.

`orderForLen(len)` returns the smallest order whose block size can contain
`len` units. It returns:

- `error.InvalidRequest` when `len == 0`;
- `error.Overflow` when no representable order can contain `len`.

`contains(block, index)` returns whether `index` is inside the half-open block
range:

```text
[block.start, block.start + blockSize(block.order))
```

`buddyOf(block)` returns the adjacent same-order block that shares a parent with
`block`. Its start is:

```zig
block.start ^ blockSize(block.order)
```

`parentOf(block)` returns the containing block of order `block.order + 1`. It
returns `error.Overflow` if the parent order or size is not representable.

`split(block)` returns the two child blocks of order `block.order - 1`:

```text
left.start  == block.start
right.start == block.start + blockSize(block.order - 1)
```

It returns `error.InvalidRequest` when `block.order == 0`.

`canCoalesce(left, right)` returns true when both blocks:

- have the same order;
- are valid buddy blocks;
- have the same parent.

Invalid or unrepresentable blocks passed to `canCoalesce` are programmer errors.
Implementations may assert validity in checked modes.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Mutation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `FirstFit.select` | never | never | O(free_ranges.len) | never | immutable inputs | deterministic first fit |
| `BestFit.select` | never | never | O(free_ranges.len) | never | immutable inputs | deterministic best fit |
| `WorstFit.select` | never | never | O(free_ranges.len) | never | immutable inputs | deterministic worst fit |
| Buddy math | never | never | O(1) | never | value-only | deterministic |

The allocation algorithms perform no hidden allocation, waiting, sleeping,
spinning, blocking, syscalls, target probing, atomics, barriers, volatile access,
or hidden global access.

The selection algorithms read only immutable input slices. They are safe to call
concurrently when callers keep those inputs immutable for the duration of each
call.

## Error behavior

`Error` is:

```zig
error{
    InvalidRequest,
    InvalidAlignment,
    Overflow,
}
```

`InvalidRequest` means a request or operation has no meaningful allocation-block
semantics, such as `Request.len == 0`, `Buddy.orderForLen(0)`, or splitting an
order-0 block.

`InvalidAlignment` means `Request.alignment` is zero or not a power of two.

`Overflow` means checked arithmetic or shift operations cannot represent the
candidate, block size, block end, or parent order.

No-fit selection returns `null`, not an error.

Invalid free-range slices and invalid buddy blocks are programmer errors rather
than public error results.

## Implementation constraints

Implementations must:

- use checked arithmetic for alignment, candidate end, block size, and block end;
- never mutate input free ranges;
- preserve the exact tie-break rules;
- avoid allocation and hidden global state;
- avoid target-specific branches;
- avoid wrappers around allocator-owned data structures.

Implementations may use `stdx.mem.alignUp` or equivalent checked alignment logic
for candidate starts.

## Required tests

### Request validation

- `Request.len == 0` returns `error.InvalidRequest`;
- `Request.alignment == 0` returns `error.InvalidAlignment`;
- non-power-of-two alignment returns `error.InvalidAlignment`;
- candidate start alignment covers already-aligned and misaligned range starts;
- candidate end overflow returns `error.Overflow`.

### Selection behavior

- empty `free_ranges` returns `null`;
- no fitting range returns `null`;
- `FirstFit` chooses the first fitting source range;
- `FirstFit` respects alignment inside a source range;
- `BestFit` chooses the smallest leftover;
- `BestFit` tie-breaks by lowest allocation start, then lowest index;
- `WorstFit` chooses the largest leftover;
- `WorstFit` tie-breaks by lowest allocation start, then lowest index;
- `Selection.index` identifies the source free-range slice index;
- `Selection.prefix`, `Selection.range`, and `Selection.suffix` exactly partition
  the source range;
- selection does not mutate the input free-range slice.

### Buddy behavior

- `blockSize(0) == 1`;
- `blockSize` returns powers of two for ordinary orders;
- `blockSize` reports overflow for unrepresentable orders;
- `orderForLen(1) == 0`;
- `orderForLen` returns exact orders for powers of two;
- `orderForLen` rounds non-powers of two up;
- `orderForLen(0)` returns `error.InvalidRequest`;
- `contains` includes the block start and excludes the block end;
- `buddyOf` returns the adjacent same-order block;
- `parentOf` returns the containing next-order block;
- `split` returns left and right child blocks with exact starts and order;
- `split` of order 0 returns `error.InvalidRequest`;
- `canCoalesce` returns true for buddy siblings and false for same-order non-buddies.

### Model tests

Model tests over small free-range lists compare `FirstFit`, `BestFit`, and
`WorstFit` against straightforward reference scans. The model must cover:

- multiple free ranges;
- alignment-induced prefixes;
- empty prefix and suffix cases;
- fragmented no-fit cases;
- all documented tie-breaks.

## Open questions

None.
