# `stdx.mem.alloc.PageAllocator`

[`PageAllocator`](../../../../src/mem/alloc/page.zig) maps unit-index backend
allocations to typed `Page.Range` values. The allocator stores its backend by
value and owns the allocation state represented by that value. The caller
retains ownership of the addressed memory and any borrowed backend storage.
`PageAllocator.*` denotes shared variant operations.

## Construction and backend

| Variant | Construction | Origin |
| --- | --- | --- |
| `PageAllocator.Static(Backend, Page, origin)` | `PageAllocator.Static(Backend, Page, origin).init()` or `.{}` initializes `Backend.init()` | Compile-time `Page.Base` |
| `PageAllocator.Bounded(Backend, Page)` | `PageAllocator.Bounded(Backend, Page).init(backend, origin)` retains the supplied backend state | Runtime `Page.Base` |

Backend units are pages. The backend supplies the operations and declarations
required by [`PageAllocator`](../../../../src/mem/alloc/page.zig), with
`Block.start` and `Block.order`, and half-open `Range.start` and `Range.end`.
Its named `Error` set must be a subset of `OutOfMemory`, `OutOfBounds`,
`InvalidRequest`, `InvalidOrder`, `AlreadyAllocated`, `NotAllocated`, and
`Overflow`. Missing declarations, fields, or incompatible error sets cause
compile errors. Both [buddy allocator variants](buddy.md) satisfy this contract.
Custom backends must preserve the same unit, block, and reservation semantics.

Construction requires the backend capacity to fit in `Page.Int` and the last
page base to fit in the address domain. For nonzero capacity, the last base is
`origin.add(Page.Count.from(capacity - 1))`. An extent can include the final
page in the address domain. A representable exclusive-end address is not
required. Invalid static extents cause a compile error. `PageAllocator.Bounded.init()` returns
`Overflow` without changing the supplied backend. A zero-capacity backend
requires no last-page calculation.

The origin is page-aligned through `Page.Base`. Block alignment is relative
to the origin. Larger allocations need not have absolute block-sized address
alignment.

## Allocation, release, and reservation

`PageAllocator.alloc(order)` first returns `InvalidOrder` if the order is outside the backend
order count. Otherwise it allocates a backend block and returns an `Allocation`.
`Allocation.range()` exposes the corresponding `Page.Range`: its first page
is the origin plus `block.start` pages, and its count is the block size from
[buddy arithmetic](../../algo/alloc/buddy.md).

The caller MUST retain each live allocation and pass it unchanged to
`PageAllocator.free(allocation)` on the same allocator, once. The allocator, backend storage,
and addressed resources must outlive all allocations. Copies of a
borrowed-storage backend share allocation state and require the same exclusive
access discipline. Copying an allocation does not create another release right.
Release invalidates the allocation and any access rights supplied
through it.

Before calling the backend, `PageAllocator.free()` checks, in order:

1. Valid range and power-of-two count (`InvalidRequest`).
2. First page at or above the origin (`OutOfBounds`).
3. Relative start representable in `usize` (`OutOfBounds`).
4. Relative block alignment (`InvalidRequest`).
5. Representable unit end (`Overflow`).
6. End within capacity (`OutOfBounds`).

It then returns the backend's release result. Buddy-backed release follows the
[buddy free contract](buddy.md#allocation-and-release), including debug traps.

`PageAllocator.reserve(range)` excludes all pages in a valid `Page.Range`, including both
its first and last pages. It checks range validity (`InvalidRequest`), a first
page below the origin (`OutOfBounds`), overflowing relative start plus count
(`Overflow`), and an end beyond backend capacity (`OutOfBounds`), in that order.
It then delegates a half-open unit range to the backend. `Page.Range` represents
nonempty ranges. One page has equal first and last bases.

Conversion failures in `PageAllocator.free()` and `PageAllocator.reserve()` occur before backend mutation.
Backend error and rollback behavior follows the backend contract. In
particular, buddy-backed errors leave the state unchanged. `PageAllocator.alloc()` converts
the block after backend allocation and does not roll back a conversion failure:
such a failure returns `Overflow` with the backend allocation still consumed.
Valid buddy-backed extents and blocks fit the page conversion.

## Queries and resource use

Capacity and allocation counts use `Page.Int`.
`PageAllocator.remainingBytes()` returns the remaining byte count, or
`Overflow` if it does not fit. Reserved pages count as allocated.

`PageAllocator.hasFreeBlock(range)` tests whether the exact block is represented
as free. Invalid ranges return false. `PageAllocator.largestFreeOrder()` returns
the highest represented free order, or `null`. `PageAllocator.isValid()` checks
backend and extent validity.

The wrapper adds constant work to allocation, release, reservation, and
ordinary queries. Count queries and validation include backend work.
`PageAllocator.largestFreeOrder()` checks candidate blocks across backend orders and can
perform O(capacity · orderCount) block queries, in addition to the backend
remaining-count query.

The wrapper allocates no storage and adds no waiting or synchronization.
Callers MUST synchronize shared access when an operation can mutate state.
