# `stdx.mem.alloc.BuddyAllocator`

[`BuddyAllocator`](../../../../src/mem/alloc/buddy.zig) allocates power-of-two
blocks of abstract units. The caller owns the resources that the unit indexes
identify. Block arithmetic and alignment follow
[the buddy arithmetic contract](../../algo/alloc/buddy.md).
`BuddyAllocator.*` denotes shared variant operations.

## Construction and storage

| Variant | Construction | Storage |
| --- | --- | --- |
| `BuddyAllocator.Static(count, orders)` | `BuddyAllocator.Static(count, orders).init()` or `.{}` | Inline bitmap. `bound` is the compile-time unit capacity |
| `BuddyAllocator.Bounded` | `BuddyAllocator.Bounded.wrap(items, count, orders)` | Borrows a mutable slice of `Word` values |

Both variants require `count > 0`, `1 <= orders <= 32`, and
`count <= maxInt(usize) >> (orders - 1)`. Invalid static parameters cause a
compile error. `BuddyAllocator.Bounded.wrap()` returns `InvalidRequest` for invalid parameters,
insufficient storage, or a bitmap bit capacity that does not fit in `usize`.
An unsuccessful wrap leaves `items` unchanged.

`Word` is the bitmap word type over `u64`. The required word count is

```text
W = sum(k = 0 .. orders - 1, ceil(ceil(count / 2^k) / Word.width))
```

`BuddyAllocator.Bounded.wrap()` requires `items.len >= W`. It clears the entire supplied slice,
including excess words, and initializes the free state. The logical bitmap
capacity is `W * Word.width` bits. The slice must remain alive and exclusively
managed by the allocator until the allocator is discarded.

Initialization makes all units in `[0, count)` available, represented by the
largest aligned blocks that fit within the configured orders. Capacity need
not be a power of two. `BuddyAllocator.clearRetainingCapacity()` restores this state, clears
all borrowed words for `Bounded`, and invalidates previous allocations and
reservations without releasing storage.

## Allocation and release

`BuddyAllocator.alloc(order)` returns a `Block` in unit indexes. It chooses the lowest start
among available blocks at the requested order or a higher order. Equal starts
prefer the lower source order. The returned block has the requested order.
Unused portions of a larger source block remain available.

`BuddyAllocator.free(block)` releases a block and coalesces free buddies through
`BuddyAllocator.maxOrder()`. The caller MUST release each live allocation once,
with its original start and order. Reserved units can be freed as order-0 blocks.

Errors are checked in this order:

| Operation | Checks and errors |
| --- | --- |
| `BuddyAllocator.alloc()` | `InvalidOrder` if `order >= orderCount()`. Then `OutOfMemory` if no suitable block exists |
| `BuddyAllocator.free()` | `InvalidOrder`. Then `InvalidRequest` for an unaligned start, overflowing end, or end beyond capacity. Then `NotAllocated` if the exact block is already represented as free |

When `core.debug.checksEnabled()` is true, an unaligned free or an exact-block
double-free traps instead of returning its error. A returned error leaves the
allocator unchanged.

## Reservation

`BuddyAllocator.reserve(range)` makes every unit in the half-open unit range unavailable.
It first rejects an invalid range with `InvalidRequest`, then an end beyond
capacity with `OutOfBounds`, then any unavailable unit with `AlreadyAllocated`.
The complete range is checked before mutation. Every returned error leaves
the allocator unchanged. An empty range is a no-op when its start is at most
capacity and returns `OutOfBounds` otherwise.

## Queries and costs

Counts and capacity use units. Allocated units include reservations.

`BuddyAllocator.hasFreeBlock(block)` tests whether the exact block is represented
as free. Invalid blocks return false.

`BuddyAllocator.isValid()` checks allocator consistency.
Callers MUST preserve metadata and bitmap words between operations.

Let `O` be the order count, `N` the unit capacity, `W` the required bitmap words,
`B` the borrowed word count, and `R` the reserved range length. Costs include
order-offset calculation:

| Operation | Worst-case work |
| --- | --- |
| Configuration queries | O(1) |
| `BuddyAllocator.remaining()`, `BuddyAllocator.allocated()` | O(W + O²) |
| `BuddyAllocator.hasFreeBlock()` | O(O) |
| `BuddyAllocator.alloc()` | O(W + O²) |
| `BuddyAllocator.free()` | O(O²) |
| `BuddyAllocator.reserve()` | O(R · O²) |
| `BuddyAllocator.clearRetainingCapacity()`, successful `BuddyAllocator.Bounded.wrap()` | O(B + N · O) for borrowed storage. Inline clear copies W words |
| `BuddyAllocator.isValid()` | O(B + N · O + O²) |

Debug checks can add full validation scans to allocation and release.
Operations allocate no heap storage and do not wait. Callers MUST synchronize
concurrent access when any access can mutate allocator state.
