# `stdx.mem.alloc.BitmapAllocator`

Allocation of unit indexes and contiguous half-open ranges.
`BitmapAllocator.*` denotes shared variant operations.

## Variants and backing storage

| Variant | Construction and ownership |
| --- | --- |
| `BitmapAllocator.Static(count)` | `BitmapAllocator.Static(count).init()` or `.{}` starts empty with inline bitmap storage. `count > 0` is required at compile time. `bound` is the unit capacity. |
| `BitmapAllocator.Bounded` | `BitmapAllocator.Bounded.wrap(items, count)` borrows a mutable slice of `Bounded.Word` and clears the entire slice on success. |

`Bounded.Word` is the `bits.Word(u64)` wrapper, with 64 bits per word.
The required word count is `count / 64` plus one when `count % 64 != 0`.
`Bounded.wrap()` returns `error.OutOfBounds` if the slice has fewer words,
without changing any word.

Zero-capacity `Bounded` values are valid, including with empty storage.
Keep borrowed storage alive and mutable while the allocator is in use.
Copies of `Bounded` share the same allocation bits. Copies of `Static` have
independent bits. Synchronize access that overlaps mutation, including access
through another value that shares the storage.

Neither variant allocates backing memory. Returned indexes and ranges have no
pointer dependency on the allocator's address.

## Units and queries

Valid unit indexes satisfy `index < BitmapAllocator.capacity()`.
`BitmapAllocator.Range` is `ranges.Range(usize)` and denotes `[start, end)`.
Pass valid ranges, with `start <= end`, to range operations.

Counts and capacity use units. A zero-capacity allocator is both empty and full.

`BitmapAllocator.isAllocated(index)` and `BitmapAllocator.isFree(index)` both
return false outside capacity.

## Allocation, reserve, and free

| Operation | Success | Returned errors |
| --- | --- | --- |
| `BitmapAllocator.allocOne()` | Allocates the lowest free index. | `error.OutOfMemory` when no unit is free. |
| `BitmapAllocator.allocRange(count)` | Allocates the lowest contiguous free range of exactly `count` units. Zero returns `Range.empty(0)`. | `error.OutOfMemory` when `count` exceeds capacity or no sufficient contiguous run exists. |
| `BitmapAllocator.reserveOne(index)` | Marks the selected free unit allocated. | `error.OutOfBounds` for an index outside capacity. Otherwise `error.AlreadyAllocated` if allocated. |
| `BitmapAllocator.reserveRange(range)` | Marks all selected free units allocated. | `error.OutOfBounds` if `range.end` exceeds capacity. Otherwise `error.AlreadyAllocated` if any selected unit is allocated. |
| `BitmapAllocator.freeOne(index)` | Marks the selected allocated unit free. | `error.OutOfBounds` for an index outside capacity. Otherwise `error.NotAllocated` if free. |
| `BitmapAllocator.freeRange(range)` | Marks all selected allocated units free. | `error.OutOfBounds` if `range.end` exceeds capacity. Otherwise `error.NotAllocated` if any selected unit is free. |

Empty reserve and free ranges are successful no-ops when their position is at
most capacity. Empty ranges beyond capacity return `error.OutOfBounds`.
Every returned error preserves all allocation bits, including range requests
that overlap a mixture of allocated and free units. Zero-length allocation
leaves the bits unchanged.

`BitmapAllocator.clearRetainingCapacity()` frees all units and clears all backing
words. Callers clean up external resources before free or clear.

## Validity

The backing storage must represent capacity. Unused high bits in the final
logical word and all words beyond logical capacity must remain zero.
Preserve these conditions when directly modifying the public `bitmap` state.
`BitmapAllocator.isValid()` reports whether these structural conditions hold.

When `core.debug.checksEnabled()` is true, bitmap queries and mutations can
check storage invariants. These checks can increase operation costs.

## Costs

Let `C` be unit capacity, `W` the required logical word count, `S` the number
of supplied words, and `L` the requested range length. The table gives
worst-case costs with debug checks disabled.

| Operation | Time |
| --- | --- |
| Construction and clear | O(S), with `S = W` for `Static` |
| Capacity and single-index queries | O(1) |
| Counts, empty, and full queries | O(W) |
| Single-unit allocation | O(W) |
| Contiguous allocation | O(C) |
| Reserve or free one unit | O(1) |
| Reserve or free a range | O(L) |
| `BitmapAllocator.isValid()` | O(1 + S - W) |

With debug checks enabled, each checked bitmap access can additionally scan
the trailing storage, costing O(1 + S - W). Range operations can perform such
checks for each accessed unit. All operations perform no waiting or hidden
allocation.

## References

- [Bitmap allocation](../../../../src/mem/alloc/bitmap.zig)
