# `stdx.addr.Address`

`Address(DomainT, IntT)` defines a strongly typed unsigned byte address.
It distinguishes address domains without storing a domain tag.

## Domains and representation

`IntT` must be an unsigned integer type, including `u0`. Other types are compile
errors. `DomainT` can be any type. The result is a non-exhaustive `enum(IntT)`:
every backing integer is valid, with no canonical-address or mapping check.
The same domain and integer types produce the same address type. Changing
either produces a distinct type.

`Address.from(value)` and `Address.raw()` preserve the exact backing integer.
Use same-type Zig equality and raw integers for ordering.

The built-in domains are `PhysAddr = Address(PhysTag, u64)`,
`VirtAddr = Address(VirtTag, usize)`, and `DmaAddr = Address(DmaTag, u64)`.
The opaque tags belong to `stdx.addr.address`. These names describe caller
intent. They do not perform physical, virtual, or DMA address translation.

## Checked arithmetic and alignment

Here, `Address` denotes any instantiated address type. Arithmetic returns the
same address type and reports `error.Overflow` rather than wrapping.

| Operation | Result and failure |
| --- | --- |
| `Address.add(amount)` | Adds an unsigned `Int` byte count. Fails if the sum exceeds `Int` |
| `Address.sub(amount)` | Subtracts an unsigned `Int` byte count. Fails on underflow |
| `Address.offset(bytes)` | Applies a signed byte offset whose width matches `Int`. Negative values subtract, including the minimum signed value |
| `Address.diff(base)` | Returns the unsigned `Int` byte distance `self.raw() - base.raw()`. Fails when `self` is below `base` |
| `Address.alignUp(alignment)` | Rounds up to an alignment multiple. Returns `error.Overflow` if upward rounding is unrepresentable |
| `Address.alignDown(alignment)` | Rounds down to an alignment multiple |
| `Address.isAligned(alignment)` | Tests whether the address is an alignment multiple |

Alignment MUST be a nonzero power of two representable in `Int`.

## Explicit casts and pointer safety

`stdx.addr.cast(T, value)` supports address-to-address, non-slice-pointer-to-address,
and address-to-non-slice-pointer conversions. Other combinations are compile
errors. Cross-domain casts preserve the numeric address. Narrowed values MUST
fit the target integer type. Pointer conversions also require the address to fit `usize`.

Slices are not accepted directly. A pointer to a slice is accepted and addresses
the slice descriptor, not its payload. Use the slice's `.ptr` for the payload.

`stdx.addr.castAligned(Pointer, address)` accepts only an address-to-non-slice-pointer
conversion. It first casts the address to `usize`, then checks the pointer's
explicit alignment or its child's natural alignment. Misalignment returns
`error.Misaligned`. Integer narrowing can fail before that check.

Neither cast validates pointer provenance, accessible storage, object lifetime,
permissions, or address-space meaning. The caller must satisfy the destination
pointer's requirements, including alignment for `stdx.addr.cast()` and validity
when the pointer is used. Casting does not extend the pointee's lifetime.

Address operations take O(1) time without allocation and do not mutate their inputs.

## References

- [Address types, arithmetic, and casts](../../../src/addr/address.zig)
- [Address ranges](../core/range.md) and [page families](pages.md)
- [Integer alignment](../layout/alignment.md)
