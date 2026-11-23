# `stdx.algo.alloc.buddy`

Checked block-size, order, and block-geometry arithmetic for buddy allocators.
The caller supplies the unit domain and manages allocator state.

## Sizes and orders

Starts and lengths use caller-defined `usize` units. `Block` contains
`start: usize` and `order: u8`.
Let `bits = @bitSizeOf(usize)`.

| Operation | Result | Errors |
| --- | --- | --- |
| `buddy.blockSize(order)` | `1 << order` | `error.Overflow` when `order >= bits` |
| `buddy.orderForLen(len)` | Smallest order whose size is at least `len` | `error.InvalidRequest` for zero. `error.Overflow` for `len > 1 << (bits - 1)` |
| `Block.size()` | `buddy.blockSize(block.order)` | Same size bound |

Order zero has size one. The largest representable size is
`1 << (bits - 1)`, at order `bits - 1`.

## Block geometry

Allocator blocks require size-aligned starts and representable half-open ends.
Each method checks the arithmetic specified below.

| Operation | Result and checked arithmetic |
| --- | --- |
| `Block.contains(index)` | Tests membership in `[start, start + size)`. Returns `error.Overflow` if the size or end is unrepresentable, even when `index < start`. |
| `Block.buddy()` | Returns a same-order block at `start ^ size`. Returns `error.Overflow` for an unrepresentable size. Does not check either block end. |
| `Block.parent()` | Returns order `order + 1` at `start & ~(parent_size - 1)`. Returns `error.Overflow` if the order increment, parent size, or parent end is unrepresentable. |
| `Block.split()` | Returns two order-`order - 1` blocks, first at `start`, then at `start + child_size`. Order zero returns `error.InvalidRequest` before size arithmetic. An unrepresentable child size or right-child start returns `error.Overflow`. |
| `Block.canCoalesce(other)` | True exactly when orders match, their size is representable, and `start ^ size == other.start`. Returns false for different orders or an unrepresentable size. |

`Block.split()` checks only the child size and right-child start.
Before coalescing, callers must establish alignment, representable block ends,
and a representable parent separately.

## Cost and effects

Operations take O(1) time and additional space without allocation, waiting,
or input mutation. The caller manages allocator state and synchronization.

## References

- [Buddy block arithmetic](../../../../src/algo/alloc/buddy.zig)
