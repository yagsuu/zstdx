# `stdx.dma.sgl`

Device-address entries, lists, and builders with uniform entry alignment.

`List.*` and `Builder.*` below denote operations shared by their `Static` and
`Bounded` variants.

## Entries

`Entry.addr` is a `DmaAddr`.
`Entry.len` is a byte count in `Entry.Address.Int` (`u64`).

| Operation | Contract |
| --- | --- |
| `Entry.init(addr, len)` | Accepts zero length or a representable final byte `addr.raw() + len - 1`. Otherwise returns `Overflow`. No alignment requirement. |
| `Entry.range()` | Null for zero length. Otherwise the inclusive device-address range, or `Overflow`. One byte at the maximum address is valid. |
| `Entry.fromBuffer(T, buffer)` | Preserves the buffer's device address and byte length. |
| `Entry.isAligned(alignment)` | True exactly when alignment is a nonzero power of two dividing address and length. |
| `Entry.assertValid()` | Asserts range validity when assertions are enabled. |

Entry operations take O(1) time. Callers MUST preserve range validity when
constructing or mutating entries directly.

## Variants

| Family | Inline storage | Borrowed storage |
| --- | --- | --- |
| List | `List.Static(N).init()` or `.{}`. `N > 0` required at compile time. | `List.Bounded.wrap(storage)`. Capacity is `storage.len`. |
| Builder | `Builder.Static(N, alignment).init()` or `.{}`. Same capacity rule. | `Builder.Bounded(alignment).wrap(storage)`. Same borrowed-storage rule. |

Construction creates empty content without clearing spare storage. Zero-capacity
borrowed storage is valid and is both empty and full. Content is the initialized
prefix `buffer[0..count]`, with `count <= capacity`. Every entry must be valid.
Lists preserve insertion order.

## List operations

| Operation | Contract |
| --- | --- |
| `List.append(entry)` | Appends one valid entry. `Full` leaves the list unchanged. |
| `List.appendAssumeCapacity(entry)` | Same append. Caller supplies spare capacity, checked by assertion. |
| `List.appendBuffer(T, buffer)` | Appends `Entry.fromBuffer(T, buffer)` with the same capacity behavior. |
| `List.slice()` / `List.sliceMut()` | Read-only/mutable views of initialized content. |
| `List.at(index)` / `List.atMut(index)` | Read-only/mutable entry pointer. `OutOfBounds` when `index >= count`. |
| `List.totalByteLen()` | Sums byte lengths in insertion order. `Overflow` if the sum exceeds `Entry.Address.Int`. No mutation. |
| `List.clearRetainingCapacity()` | Empties content without overwriting storage or changing capacity. |
| `List.assertValid()` | Asserts capacity and entry-range invariants when assertions are enabled. |

Counts and capacity use entries. Outside invariant checking,
operations take O(1) time except `List.totalByteLen()`, which takes O(len).
Invariant checking can inspect every content entry.

## Builder operations

Both builder variants require a nonzero power-of-two `alignment` at compile time.
`Builder.alignment` divides each entry's address and length. Alignment 1 accepts
every valid entry.

Builder count, capacity, content-view, and clear operations follow the
[shared list behavior](#list-operations).

| Operation | Contract |
| --- | --- |
| `Builder.append(entry)` | Checks alignment before capacity. `Misaligned` precedes `Full`, including with zero capacity. Both errors leave content unchanged. |
| `Builder.appendBuffer(T, buffer)` | Converts through `Entry.fromBuffer()` and applies the same checks. |
| `Builder.finish()` | Returns a const pointer to the underlying list without consuming the builder. Append, clear, or movement invalidates the finished view. |
| `Builder.assertValid()` | Asserts capacity, entry validity, and uniform alignment when assertions are enabled. |

Builder operations take O(1) time outside invariant checking.

## Lifetime and synchronization

- Appends preserve existing entry indexes and views while storage stays in place.
  Clearing invalidates all initialized-content indexes and views.
- Moving inline values invalidates views into their previous storage. Moving
  borrowed values does not move storage. Callers keep it live throughout use.
  A borrowed value MUST NOT borrow another field of the same containing struct.
- Callers MUST preserve range validity through mutable views, and uniform alignment
  through builder views.
- Entries retain no buffer, mapping, or allocation. Callers MUST keep host memory
  and device-address mappings valid for the entire DMA transaction and manage
  resource lifetimes. Lists do not call destructors.
- Operations do not allocate, wait, dereference device addresses, or emit
  descriptors. Callers MUST serialize conflicting access and supply mapping,
  cache maintenance, and protocol-required [DMA barriers](../barrier.md).

## References

- [Entries, lists, and builders](../../../src/dma/sgl.zig)
- [Contiguous DMA buffers](buffer.md)
- [Address types](../addr/address.md)
