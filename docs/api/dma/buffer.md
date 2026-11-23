# `stdx.dma.Buffer`

`Buffer(T)` pairs a borrowed contiguous host slice with the device-visible address
of its first byte.

## Construction and ownership

`T` must have nonzero size. Copies and sub-buffers alias the same host memory
without extending its lifetime.

The caller MUST pair the slice with the same contiguous device-visible region
and keep both host storage and its mapping valid throughout use. The caller
owns allocation, pinning, mapping, cache maintenance, and synchronization.

`Buffer.init(memory, address)` validates address alignment to `@alignOf(T)`.
`Buffer.initAligned(memory, address, alignment)` additionally requires a nonzero
power-of-two alignment dividing the address.

Both constructors return `error.Misaligned` before range validation if alignment
is invalid or unsatisfied. They return `error.Overflow` if the element count,
byte count, or exclusive end address cannot be represented in `Address.Int`
(`u64`): `address.raw() + memory.len * @sizeOf(T)`.
Empty buffers are valid at any element-aligned address.

Construction errors leave caller storage unchanged. Callers who construct or
modify fields directly MUST preserve the same element-alignment and range
invariants. Extra alignment supplied to `Buffer.initAligned()` is not retained
as a buffer invariant.

## Views and device addresses

Lengths use elements. Byte lengths and device addresses use `DmaAddr.Int` (`u64`).

| Operation | Result |
| --- | --- |
| `Buffer.slice()` / `Buffer.sliceMut()` | Const/mutable typed aliases of `memory`. |
| `Buffer.bytes()` / `Buffer.bytesMut()` | Const/mutable byte aliases of the same host range. |
| `Buffer.dmaAddrAt(offset_items)` | Address advanced by `offset_items * @sizeOf(T)`. `OutOfBounds` when the offset exceeds the element count. |

`Buffer.dmaAddrAt(Buffer.len())` is valid and returns the exclusive end address.
Byte-view interpretation must respect the element type's representation.
Buffer operations preserve other copies and views.

## Sub-buffers

`Buffer.sub(.{ .offset = start, .count = count })` uses element counts and returns
the host sub-slice paired with the correspondingly advanced device address.
Addition overflow in `start + count` returns `error.Overflow` before bounds
validation. An end beyond `Buffer.len()` returns `error.OutOfBounds`.
Both errors leave the buffer and host storage unchanged.

Zero count is valid at `start <= Buffer.len()`, including the end cursor.
Sub-buffers inherit the parent's mapping and lifetime requirements.

## Execution and synchronization

Operations take O(1) time without allocation or waiting.
`Buffer.assertValid()` checks alignment and range invariants.
Callers MUST synchronize conflicting access and supply cache maintenance and
[DMA barriers](../barrier.md) at ownership transfers.

## References

- [Buffer declarations](../../../src/dma/buffer.zig)
- [Scatter-gather entries and lists](sgl.md)
- [Device address types](../addr/address.md)
