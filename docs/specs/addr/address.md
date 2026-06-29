# Address

Status: Approved.

`zstdx.addr.Address(Tag, Int)` is a zero-cost strong integer type for
address-like domains. It prevents accidental mixing of values that share the
same integer representation but have different meanings.

## Owned scope

This spec owns:

- `addr.Address(Tag, Int)`;
- built-in `addr.PhysAddr` and `addr.VirtAddr` aliases;
- tag-based type identity;
- unsigned integer type restrictions;
- raw integer conversion;
- checked address arithmetic;
- address alignment helpers;
- required tests.

This spec does not own:

- `DmaAddr`;
- page-aligned address types;
- page sizes, page counts, frames, or page ranges;
- address ranges;
- pointer spans or non-null pointer wrappers;
- pointer provenance or lifetime validation;
- MMIO or volatile access;
- formatting or parsing policy;
- architecture-specific canonical-address validation;
- saturating, wrapping, or unchecked arithmetic variants.

## Public namespace

Address primitives live under `zstdx.addr`:

```zig
zstdx.addr.Address
zstdx.addr.PhysAddr
zstdx.addr.VirtAddr
```

They are not root-promoted:

```zig
zstdx.Address // not exported
zstdx.PhysAddr // not exported
```

Source ownership:

```text
src/addr.zig
src/addr/address.zig
test/addr/address_test.zig
```

`src/addr.zig` re-exports:

```zig
pub const address = @import("addr/address.zig");

pub const Address = address.Address;
pub const PhysAddr = address.PhysAddr;
pub const VirtAddr = address.VirtAddr;
```

## Approved API

```zig
pub fn Address(comptime Tag: type, comptime Int: type) type;
```

`Int` must be an unsigned integer type. Signed integers, floats, bools, enums,
pointers, and comptime integers without an explicit `Int` are compile errors.

Returned type:

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

Built-in aliases:

```zig
pub const PhysTag = opaque {};
pub const VirtTag = opaque {};

pub const PhysAddr = Address(PhysTag, u64);
pub const VirtAddr = Address(VirtTag, usize);
```

`VirtAddr` is pointer-width because it models host virtual address values. Guest
virtual addresses, firmware virtual addresses, and other address domains should
use their own tag and integer width.

## Tag identity

`Tag` gives the returned type its domain identity. It is never stored and has no
runtime cost or behavior.

Recommended tags are zero-sized unique types:

```zig
const GpaTag = opaque {};
const Gpa = zstdx.addr.Address(GpaTag, u64);
```

Small enum or struct tag types are also valid when that matches project style:

```zig
const PioPort = zstdx.addr.Address(enum { pio_port }, u16);
```

Different tags produce different address types, even when `Int` is the same.
Where practical, assigning one tagged address type to another must fail at
compile time.

`TagType` is exposed only for compile-time introspection.

## Conversion

`fromInt(value)` is infallible. Every value representable by `Int` is a valid
address value for this primitive.

`raw()` returns the exact backing integer. It performs no validation and does
not change the address domain.

`zero()` returns address value `0`.

`max()` returns `std.math.maxInt(Int)` in the address domain.

## Equality and ordering

Equality uses Zig's native same-type equality:

```zig
if (address == other_address) {
    // Equal.
}
```

This spec intentionally does not add `eql`, `lessThan`, or `compare` methods.
Ordering is explicit at the call site:

```zig
if (address.raw() < limit.raw()) {
    // Below limit.
}
```

Collection or algorithm callbacks should be defined by the consumer when needed:

```zig
fn lessAddress(_: void, lhs: *const Gpa, rhs: *const Gpa) bool {
    return lhs.raw() < rhs.raw();
}
```

## Arithmetic

`add(self, amount)` returns `self.raw() + amount` in the same address domain.
It returns `error.Overflow` when the addition would overflow `Int`.

`sub(self, amount)` returns `self.raw() - amount` in the same address domain.
It returns `error.Overflow` when the subtraction would underflow `Int`.

`diff(self, base)` returns `self.raw() - base.raw()` as `Int`. It returns
`error.Overflow` when `self.raw() < base.raw()`.

Underflow maps to `error.Overflow`; there is no separate underflow error.

## Alignment

Address alignment follows the same validity rule as `zstdx.mem` alignment:

```zig
alignment != 0 and zstdx.bits.isPowerOfTwo(Int, alignment)
```

All alignment operations return `error.InvalidAlignment` when `alignment` is
zero or not a power of two.

`alignUp(self, alignment)` returns the smallest aligned address greater than or
equal to `self`. It returns `error.Overflow` when rounding up would exceed
`std.math.maxInt(Int)`.

`alignDown(self, alignment)` returns the greatest aligned address less than or
equal to `self`. It cannot overflow after alignment validity has been checked.

`isAligned(self, alignment)` returns true iff `self.raw()` is a multiple of
`alignment`.

`alignment == 1` is valid. It is a no-op for `alignUp` and `alignDown`, and
`isAligned` returns true for every address value.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `fromInt` | never | never | O(1) | none | value type | none |
| `raw` | never | never | O(1) | none | value type | none |
| `zero` | never | never | O(1) | none | value type | none |
| `max` | never | never | O(1) | none | value type | none |
| `add` | never | never | O(1) | none | value type | none |
| `sub` | never | never | O(1) | none | value type | none |
| `diff` | never | never | O(1) | none | value type | none |
| `alignUp` | never | never | O(1) | none | value type | none |
| `alignDown` | never | never | O(1) | none | value type | none |
| `isAligned` | never | never | O(1) | none | value type | none |

These helpers perform no allocation, waiting, hidden global access, atomics, or
barriers.

## Error behavior

- `add` returns `error.Overflow` on addition overflow;
- `sub` returns `error.Overflow` on subtraction underflow;
- `diff` returns `error.Overflow` when `self < base`;
- `alignUp` returns `error.Overflow` when rounding up overflows;
- invalid alignment returns `error.InvalidAlignment`;
- invalid `Int` is a compile error.

`fromInt`, `raw`, `zero`, and `max` do not fail.

`alignDown` and `isAligned` do not return `error.Overflow`.

## Implementation constraints

Implementation must:

- use `enum(Int) { _ }` for the returned type;
- reject non-unsigned-integer `Int` types at compile time;
- never store a `Tag` value;
- avoid unchecked arithmetic overflow and underflow;
- reuse or exactly match `zstdx.mem` alignment semantics;
- avoid loops;
- compile for all unsigned integer widths Zig supports.

## Usage

Custom address domains:

```zig
const Gpa = zstdx.addr.Address(enum { gpa }, u64);
const PioPort = zstdx.addr.Address(enum { pio_port }, u16);

const base = Gpa.fromInt(0x1000);
const next = try base.add(0x100);

const port = PioPort.fromInt(0x3f8);
_ = port;
_ = next;
```

Built-in aliases:

```zig
const pa = zstdx.addr.PhysAddr.fromInt(0x1000);
const va = zstdx.addr.VirtAddr.fromInt(@intFromPtr(ptr));

_ = pa;
_ = va;
```

Alignment:

```zig
const aligned = try pa.alignUp(4096);
if (try aligned.isAligned(4096)) {
    // Page aligned.
}
```

## Required tests

Required for a custom `u64` address type, a custom `u16` address type,
`PhysAddr`, and `VirtAddr`.

### Type identity

- two address types with different tags are not assignment-compatible where
  practical;
- two address types with the same `Tag` and `Int` are the same type;
- `TagType` and `Raw` expose the expected compile-time types;
- invalid `Int` types fail to instantiate where practical.

### Conversion and constants

- `fromInt` and `raw` round trip `0`, a middle value, and max value;
- `zero().raw()` returns `0`;
- `max().raw()` returns `std.math.maxInt(Int)`.

### Equality and ordering

- same-type `==` distinguishes equal and unequal addresses;
- examples use `.raw()` for ordering instead of an address method.

### Arithmetic

- `add` succeeds for in-range additions;
- `add` returns `error.Overflow` at the top of the integer range;
- `sub` succeeds for in-range subtractions;
- `sub` returns `error.Overflow` at the bottom of the integer range;
- `diff` returns the distance when `self >= base`;
- `diff` returns `error.Overflow` when `self < base`.

### Alignment

- alignment `0` returns `error.InvalidAlignment`;
- non-power-of-two alignment returns `error.InvalidAlignment`;
- alignment `1` is accepted;
- `alignUp` returns aligned values unchanged;
- `alignUp` rounds unaligned values up;
- `alignUp` catches overflow;
- `alignDown` returns aligned values unchanged;
- `alignDown` rounds unaligned values down;
- `isAligned` covers aligned and unaligned values.

### Compile-time behavior

Where practical:

```zig
comptime {
    const A = zstdx.addr.Address(enum { a }, u8);

    std.debug.assert(A.fromInt(4).raw() == 4);
    std.debug.assert((try A.fromInt(7).alignUp(4)).raw() == 8);
    std.debug.assert((try A.fromInt(7).alignDown(4)).raw() == 4);
    std.debug.assert(try A.fromInt(8).isAligned(4));
}
```

## Open questions

None.
