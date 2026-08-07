# Address

Status: Approved.

`stdx.addr.Address(Tag, Int)` defines a zero-cost, strongly typed unsigned-integer address domain. A tag prevents implicit mixing of address values from different domains.

## What this spec is

This spec defines `addr.Address`, the built-in physical, virtual, and DMA address aliases, checked arithmetic, alignment operations, representation, and their required verification.

## What this spec is not

This spec does not define page-aligned addresses, page sizes, page counts, frames, or ranges; see `docs/specs/addr/pages.md`. It does not define address ranges, pointer provenance or lifetime validation, MMIO or volatile access, parsing, formatting, canonical-address validation, IOMMU mapping, or saturating, wrapping, or unchecked arithmetic.

## Terminology

- **address domain**: The set of `Address` values with one `Tag` and one `Int`.
- **raw integer**: The `Int` value that represents an address value.
- **aligned**: A raw integer that is an exact multiple of a specified alignment.

## Public namespace and source ownership

The public namespace is `stdx.addr`:

```zig
stdx.addr.Address
stdx.addr.PhysAddr
stdx.addr.VirtAddr
stdx.addr.DMAAddr
```

Source ownership is:

```text
src/addr.zig
src/addr/address.zig
test/addr/address_test.zig
```

`src/addr.zig` re-exports the `address` module and its `Address`, `PhysAddr`, `VirtAddr`, and `DMAAddr` declarations.

## Cross-spec relationships

`docs/specs/addr/pages.md` composes `Address` domains into page families. This specification does not own that page behavior.

## Data structures and representation

`Address(Tag, Int)` returns `enum(Int) { _ }`. The raw representation is exactly `Int`; the tag is not stored. `TagType` exists only for compile-time introspection. The type has no additional runtime state.

Two instantiations with different tags are distinct Zig types, even when their raw integer types match. Two instantiations with the same `Tag` and `Int` are the same type.

## Global invariants

- `Int` is an unsigned integer type accepted by Zig. An invalid `Int` causes a compile error when `Address` instantiates.
- Every value representable by `Int` is a valid address value in its address domain.
- Address operations preserve the receiver's address domain.
- The helpers allocate no memory, wait, access hidden globals, perform atomics, or issue memory barriers.
- Each operation has constant time and does not invalidate values.

## API

```zig
pub const PhysTag = opaque {};
pub const VirtTag = opaque {};
pub const DMATag = opaque {};

pub const PhysAddr = Address(PhysTag, u64);
pub const VirtAddr = Address(VirtTag, usize);
pub const DMAAddr = Address(DMATag, u64);

pub fn Address(comptime Tag: type, comptime Int: type) type;
```

`Address` returns this public type:

```zig
pub const Self = enum(Int) {
    _,

    pub const TagType = Tag;
    pub const Raw = Int;
    pub const OverflowError = error{Overflow};
    pub const AlignError = error{InvalidAlignment};
    pub const Error = OverflowError || AlignError;

    pub fn fromInt(value: Int) Self;
    pub fn raw(self: Self) Int;
    pub fn zero() Self;
    pub fn max() Self;

    pub fn add(self: Self, amount: Int) OverflowError!Self;
    pub fn sub(self: Self, amount: Int) OverflowError!Self;
    pub fn diff(self: Self, base: Self) OverflowError!Int;

    pub fn alignUp(self: Self, alignment: Int) Error!Self;
    pub fn alignDown(self: Self, alignment: Int) AlignError!Self;
    pub fn isAligned(self: Self, alignment: Int) bool;
};
```

`PhysAddr` represents a physical-address value. `VirtAddr` uses `usize` and represents a host virtual-address value. `DMAAddr` represents the address value provided to a device descriptor. A caller selects the mapping policy that produces a `DMAAddr`; this API does not convert physical addresses to DMA addresses.

## Conversion and comparison

`fromInt` returns the address-domain value represented by `value`. `raw` returns the exact raw integer. Neither operation validates address meaning outside this primitive.

`zero` returns raw value `0`. `max` returns `std.math.maxInt(Int)` in the address domain.

The API does not provide equality or ordering methods. Callers use Zig same-type equality and compare raw integers when ordering is required. A caller MUST explicitly convert through `raw` and `fromInt` to cross address domains.

## Arithmetic

`add` returns `self.raw() + amount` in the same address domain. It returns `error.Overflow` if the addition is not representable by `Int`.

`sub` returns `self.raw() - amount` in the same address domain. It returns `error.Overflow` if the subtraction underflows `Int`.

`diff` returns `self.raw() - base.raw()`. It returns `error.Overflow` when `self.raw() < base.raw()`. Underflow has no distinct error.

## Alignment

A valid alignment is nonzero and a power of two in `Int`:

```zig
alignment != 0 and stdx.bits.isPowerOfTwo(Int, alignment)
```

`alignUp` returns the smallest valid-alignment multiple greater than or equal to `self`. It returns `error.InvalidAlignment` for an invalid alignment and `error.Overflow` when rounding up is not representable by `Int`.

`alignDown` returns the greatest valid-alignment multiple less than or equal to `self`. It returns `error.InvalidAlignment` for an invalid alignment and cannot overflow after validation.

`isAligned` returns whether `self.raw()` is a multiple of `alignment`. The caller MUST provide a valid alignment. An invalid alignment violates the caller contract and triggers debug assertions; `isAligned` does not return `error.InvalidAlignment`.

Alignment `1` is valid. It leaves `alignUp` and `alignDown` unchanged, and `isAligned` returns `true` for every address value.

## Errors and fault behavior

- `add`, `sub`, and `diff` return `error.Overflow` for unrepresentable arithmetic.
- `alignUp` returns `error.Overflow` for unrepresentable upward rounding.
- `alignUp` and `alignDown` return `error.InvalidAlignment` for zero or non-power-of-two alignment.
- An invalid `Int` causes a compile error.
- `fromInt`, `raw`, `zero`, and `max` do not fail.

## Implementation constraints

The implementation MUST use `enum(Int) { _ }` for each address type, reject a non-unsigned `Int` at compile time, and not store a `Tag` value. It MUST use checked arithmetic where arithmetic can overflow or underflow. It MUST implement alignment validity as nonzero power-of-two validation. It MUST not use loops and MUST support every unsigned integer width Zig supports.

## Testing

Tests MUST instantiate custom small and wide address domains and the built-in address aliases. Compile-time checks MUST demonstrate tag-based type identity, same-instantiation identity, `TagType` and `Raw` metadata, and rejection of invalid raw integer types where Zig permits the check.

Runtime tests MUST round-trip zero, an interior value, and the maximum raw value through conversion; verify `zero` and `max`; and distinguish same-domain equal and unequal values. These checks prove representation preservation and strong-type boundaries.

Arithmetic tests MUST exercise successful addition, subtraction, and difference plus each representability boundary that returns `error.Overflow`. Alignment tests MUST cover zero, non-power-of-two, and unit alignment; unchanged aligned values; upward and downward rounding; and upward-rounding overflow. These boundary checks prove that the API neither wraps nor accepts invalid fallible-alignment inputs. Tests for `isAligned` MUST pass only valid alignments and distinguish aligned from unaligned raw values.
