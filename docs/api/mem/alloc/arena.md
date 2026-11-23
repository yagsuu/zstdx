# `stdx.mem.alloc.Arena`

Fixed-capacity bump allocation. `Arena.*` denotes shared variant operations.

## Variants and storage

| Variant | Construction and ownership |
| --- | --- |
| `Arena.Static(count)` | `Arena.Static(count).init()` or `.{}` starts empty with inline byte storage. `count > 0` is required at compile time. `bound` is the byte capacity. |
| `Arena.Bounded` | `Arena.Bounded.wrap(items)` borrows mutable byte storage and starts empty. Empty storage is valid. |

Keep borrowed storage alive and mutable while the arena or its allocations are
in use. Copying `Bounded` duplicates the cursor over the same storage. Do not
allocate through both copies. Copying `Static` duplicates its bytes and cursor.
Do not move a `Static` value while any pointer or slice into its storage is in
use.

The caller MUST synchronize conflicting access and clean up allocated objects.

## Capacity and byte views

Counts and capacity use bytes. Used bytes include alignment padding.

`Arena.remainingBytes()` returns a read-only view from the cursor to the end of
storage. `Arena.remainingBytesMut()` returns the corresponding mutable view.
Neither view reserves bytes or advances the cursor. Later allocations can reuse
the viewed bytes.

Keep the cursor within capacity. `Arena.isValid()` tests this condition.

## Allocation

| Operation | Result |
| --- | --- |
| `Arena.allocBytes(len)` | An uninitialized byte slice of length `len`, with alignment `1`. |
| `Arena.allocAlignedBytes(len, alignment)` | An uninitialized byte slice of length `len`. Nonempty results start at an absolute address divisible by `alignment`. |
| `Arena.alloc(T)` | Storage for one uninitialized `T`, aligned to `@alignOf(T)`. |
| `Arena.allocSlice(T, len)` | Contiguous storage for `len` uninitialized values, aligned to `@alignOf(T)`. |

Typed allocations reject zero-sized `T` at compile time.
Successful nonempty allocations advance the cursor past any alignment padding
and the returned bytes. Earlier allocations retain their addresses.

`Arena.allocAlignedBytes()` requires a nonzero power-of-two alignment and returns
`error.InvalidAlignment` otherwise. It validates alignment and performs address
rounding before handling a zero-length request. Address rounding or checked
cursor arithmetic overflow returns `error.Overflow`. A typed slice byte-count
overflow also returns `error.Overflow`. A nonempty request whose aligned end
exceeds capacity returns `error.OutOfMemory`.

Zero-length byte requests return an empty slice at the current cursor without
advancing it. The empty byte slice need not have the requested alignment.
`Arena.allocSlice(T, 0)` returns an aligned empty slice without consuming storage.

Every returned allocation error leaves the cursor and storage contents unchanged.
Byte requests check alignment, address rounding, cursor arithmetic, and capacity
in that order. Typed slice requests check byte-count multiplication first.

## Checkpoints and reset

`Arena.mark()` captures the current cursor. Pass only a checkpoint from the same
arena's current allocation history to `Arena.restore(checkpoint)`, with an index
no greater than the current cursor.

`Arena.restore()` sets the cursor to the checkpoint and invalidates allocations
made after it. `Arena.reset()` sets the cursor to zero and invalidates all
allocations. Both operations retain storage and its contents. The caller must
complete object cleanup before invalidation.

## Allocator interface

`Arena.allocator()` returns a `std.mem.Allocator` backed by the same cursor and
storage. Keep the arena at the same address while this interface is in use.
Allocation uses the arena's alignment rules. Allocation errors become allocator
failure (`error.OutOfMemory` through the standard allocation helpers).

Allocator free retains capacity. Resize and remap are unsupported.
Complete uses of affected allocator-backed objects before restore or reset.

## Costs

Operations take O(1) time without backing allocation or waiting.

## References

- [Arenas](../../../../src/mem/alloc/arena.zig)
