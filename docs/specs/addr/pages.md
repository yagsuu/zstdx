# Address pages

Status: Approved.

`stdx.addr.Page(Addr, page_size)` is a zero-cost family for page-sized address domains. It binds an approved address type and a comptime page size, then exposes page-size metadata, page counts, page-aligned frames, and page-counted ranges. The page family uses `Addr.Raw` as the backing integer width, but public names distinguish byte addresses, page counts, and frame indices.

## Owned scope

This spec owns:

- common exact page-size constants under `stdx.addr.pages`;
- `addr.Page(Addr, page_size)`;
- page-size validation for `Page` instantiations;
- nested `Page.Size` metadata;
- nested `Page.Count` page-count values;
- nested `Page.Frame` page-aligned address values;
- nested `Page.FrameRange` page-counted half-open ranges;
- checked byte/page conversions;
- checked frame arithmetic by page count;
- range containment and overlap semantics;
- required tests.

This spec does not own:

- runtime-selected page-size families;
- architecture page-table formats;
- TLB, cache, or hugepage availability policy;
- UEFI memory types, attributes, descriptors, GCD policy, or map-key behavior;
- guest memory classification such as usable RAM, reserved memory, MMIO, or DMA eligibility;
- DMA/IOMMU mapping policy;
- virtual-to-physical translation;
- address discovery or physical-address dereferencing;
- MMIO or volatile access;
- page allocation algorithms;
- root exports.

## Public namespace

Page primitives live under `stdx.addr` and `stdx.addr.pages`:

```zig
stdx.addr.pages._4kib
stdx.addr.pages._16kib
stdx.addr.pages._64kib
stdx.addr.pages._2mib
stdx.addr.pages._1gib

stdx.addr.Page
```

They are not root-promoted:

```zig
stdx.Page // not exported
stdx.PageFrame // not exported
```

Source ownership:

```text
src/addr.zig
src/addr/pages.zig
test/addr/pages_test.zig
```

`src/addr.zig` re-exports:

```zig
pub const pages = @import("addr/pages.zig");

pub const Page = pages.Page;
```

## Approved API

```zig
pub const _4kib = 4 * 1024;
pub const _16kib = 16 * 1024;
pub const _64kib = 64 * 1024;
pub const _2mib = 2 * 1024 * 1024;
pub const _1gib = 1024 * 1024 * 1024;

pub fn Page(comptime Addr: type, comptime page_size: Addr.Raw) type;
```

`Addr` must be an `addr.Address`-compatible type. It must expose:

```zig
pub const Raw = unsigned_integer_type;
pub fn fromInt(value: Raw) Addr;
pub fn raw(self: Addr) Raw;
```

`page_size` must be non-zero and a power of two representable by `Addr.Raw`. Invalid `Addr` or invalid `page_size` is a compile error.

Returned namespace:

```zig
pub const Self = struct {
    pub const Address = Addr;
    pub const AddressInt = Addr.Raw;

    pub const Error = error{
        Misaligned,
        Overflow,
        OutOfBounds,
    };

    pub const Size = struct {
        pub const bytes: AddressInt = page_size;
        pub const mask: AddressInt = page_size - 1;
        pub const shift: comptime_int = @ctz(page_size);
    };

    pub const Count = enum(AddressInt) {
        _,

        const This = @This();

        pub fn fromPages(value: AddressInt) This;
        pub fn pages(self: This) AddressInt;

        pub fn zero() This;
        pub fn max() This;

        pub fn fromBytesExact(bytes: AddressInt) Error!This;
        pub fn fromBytesRoundUp(bytes: AddressInt) Error!This;
        pub fn toBytes(self: This) Error!AddressInt;
    };

    pub const Frame = enum(AddressInt) {
        _,

        const This = @This();

        pub fn fromAddress(address: Addr) Error!This;
        pub fn fromAddressInt(value: AddressInt) Error!This;

        pub fn address(self: This) Addr;
        pub fn addressInt(self: This) AddressInt;
        pub fn index(self: This) AddressInt;

        pub fn isValid(self: This) bool;
        pub fn assertValid(self: This) void;
        pub fn isAlignedAddress(address: Addr) bool;
        pub fn containingAddress(address: Addr) Error!This;
        pub fn nextAlignedAddress(address: Addr) Error!This;

        pub fn add(self: This, count: Count) Error!This;
        pub fn sub(self: This, count: Count) Error!This;
    };

    pub const FrameRange = struct {
        base: Frame,
        count: Count,

        const This = @This();

        pub fn fromBaseCount(base: Frame, count: Count) Error!This;
        pub fn fromAddressBytes(base: Addr, bytes: AddressInt) Error!This;
        pub fn fromAddressByteSpan(start: Addr, byte_len: AddressInt) Error!This;
        pub fn empty(at: Frame) This;

        pub fn isValid(self: This) bool;
        pub fn assertValid(self: This) void;

        pub fn isEmpty(self: This) bool;
        pub fn byteLen(self: This) AddressInt;
        pub fn end(self: This) Frame;

        pub fn containsFrame(self: This, frame: Frame) bool;
        pub fn containsAddress(self: This, address: Addr) bool;
        pub fn containsFrameRange(self: This, other: This) bool;
        pub fn overlaps(self: This, other: This) bool;
        pub fn isAdjacent(self: This, other: This) bool;

        pub fn intersection(self: This, other: This) ?This;
        pub fn span(self: This, other: This) This;
        pub fn splitAt(self: This, at: Frame) Error!struct { left: This, right: This };
    };
};
```

`Self` above describes the returned namespace. Implementations do not need to declare a public symbol named `Self`.

## Page-size constants

The constants under `addr.pages` are exact byte counts:

| Constant | Value | Intended use |
| --- | ---: | --- |
| `_4kib` | `4096` | UEFI pages, common base pages |
| `_16kib` | `16384` | common configurable base pages |
| `_64kib` | `65536` | common configurable base pages |
| `_2mib` | `2097152` | common large pages |
| `_1gib` | `1073741824` | common large pages |

The constants do not imply architecture support, page-table support, hugepage availability, TLB behavior, allocation policy, or default page size. Consumers choose the exact constant their domain requires.

## Page family identity

`Page(Addr, page_size)` binds three facts into one namespace:

- address domain: `Addr`;
- address integer type: `Addr.Raw`, exposed in the page family as `AddressInt`;
- page size in bytes: `page_size`.

Different address domains produce different frame and range types even when `page_size` matches:

```zig
const Phys4K = stdx.addr.Page(stdx.addr.PhysAddr, stdx.addr.pages._4kib);
const Virt4K = stdx.addr.Page(stdx.addr.VirtAddr, stdx.addr.pages._4kib);

// Phys4K.Frame and Virt4K.Frame are distinct types.
```

Different page sizes produce different frame and range types even when `Addr` matches:

```zig
const Phys4K = stdx.addr.Page(stdx.addr.PhysAddr, stdx.addr.pages._4kib);
const Phys2M = stdx.addr.Page(stdx.addr.PhysAddr, stdx.addr.pages._2mib);

// Phys4K.Frame and Phys2M.Frame are distinct types.
```

## `Size` semantics

`Size.bytes` is the exact comptime page size.

`Size.mask` is `Size.bytes - 1` and may be used for alignment checks.

`Size.shift` is `log2(Size.bytes)` and may be used for shifts where the implementation has already validated that `Size.bytes` is a power of two.

`Size` performs no runtime work. It is metadata for the `Page` instantiation.

## `Count` semantics

`Count` is a page count backed by `AddressInt` (`Addr.Raw`). Every `AddressInt` value is a valid count, including zero.

`fromPages(value)` wraps a page count without allocation or validation.

`pages()` returns the exact backing page count.

`zero()` returns count `0`.

`max()` returns `std.math.maxInt(AddressInt)` in the count domain.

`fromBytesExact(bytes)` converts a byte count to pages. It returns `error.Misaligned` when `bytes` is not an exact multiple of `Size.bytes`.

Required behavior:

```zig
(try Count.fromBytesExact(0)).pages() == 0
(try Count.fromBytesExact(Size.bytes)).pages() == 1
(try Count.fromBytesExact(Size.bytes * 2)).pages() == 2
Count.fromBytesExact(Size.bytes + 1) == error.Misaligned
```

`fromBytesRoundUp(bytes)` returns the smallest page count whose byte capacity is greater than or equal to `bytes`. It returns `error.Overflow` when rounding up would overflow `AddressInt`.

Required behavior:

```zig
(try Count.fromBytesRoundUp(0)).pages() == 0
(try Count.fromBytesRoundUp(1)).pages() == 1
(try Count.fromBytesRoundUp(Size.bytes)).pages() == 1
(try Count.fromBytesRoundUp(Size.bytes + 1)).pages() == 2
```

`toBytes()` returns `pages() * Size.bytes`. It returns `error.Overflow` when multiplication overflows `AddressInt`.

## `Frame` semantics

`Frame` is a validated page-aligned address base represented as `enum(AddressInt)`. It is not a PFN-only or page-index value. `addressInt()` returns the aligned address integer; `index()` returns the page index.

`fromAddress(address)` returns `error.Misaligned` when `address.raw()` is not a multiple of `Size.bytes`.

`fromAddressInt(value)` is equivalent to:

```zig
Frame.fromAddress(Addr.fromInt(value))
```

`address()` returns the address-domain value for the frame base.

`addressInt()` returns the aligned address integer.

`index()` returns the page index:

```zig
addressInt() >> Size.shift
```

Because `Frame` stores an address base, `address()` and `addressInt()` are infallible for valid frames.

`isValid()` returns true when the stored address integer is aligned to `Size.bytes`.

`assertValid()` asserts `isValid()`. It is for programmer errors and internal invariant checks, not external input validation.

`isAlignedAddress(address)` returns true iff `address.raw()` is aligned to `Size.bytes`.

`add(count)` adds `count` pages to the frame. It returns `error.Overflow` when `count.toBytes()` overflows or adding the byte count to the frame address overflows.

`sub(count)` subtracts `count` pages from the frame. It returns `error.Overflow` when `count.toBytes()` overflows or subtracting the byte count from the frame address underflows.

`containingAddress(address)` returns the frame whose page contains `address`, rounding down to the previous `Size.bytes` boundary. Returns `error.Overflow` only when `Addr.alignDown` is fallible for the target address type (does not happen for built-in addresses).

`nextAlignedAddress(address)` returns the frame at or after `address`, rounding up to the next `Size.bytes` boundary. Returns `error.Overflow` when `Addr.alignUp` overflows.

## `FrameRange` semantics

`FrameRange` is a half-open page range:

```text
[base, base + count)
```

`base` is the first frame in the range. `count` is the number of frames. A range is valid when `base.add(count)` succeeds.

`fromBaseCount(base, count)` returns a valid range or `error.Overflow` when the exclusive end frame is not representable.

`fromAddressBytes(base, bytes)` is equivalent to:

```zig
const frame = try Frame.fromAddress(base);
const count = try Count.fromBytesExact(bytes);
return FrameRange.fromBaseCount(frame, count);
```

`fromAddressByteSpan(start, byte_len)` covers `[start, start + byte_len)` in whole pages. It rounds `start` down to the previous page boundary and `start + byte_len` up to the next, then returns the resulting frame range. Returns `error.Overflow` when alignment rounding overflows.

`empty(at)` returns a valid empty range at `at`.

`isValid()` returns true when `base.add(count)` succeeds and `base` is valid.

`assertValid()` asserts `isValid()`. It is for programmer errors and internal invariant checks, not external input validation.

`isEmpty()` returns true when `count.pages() == 0`.

`byteLen()` returns `count.toBytes()` unwrapped; valid ranges are guaranteed by the invariant to fit in `AddressInt`. Calling `byteLen()` on an invalid range is a programmer error.

`end()` returns the exclusive end frame. Calling `end()` on an invalid range is a programmer error.

`containsFrame(frame)` returns true when `frame` is in `[base, end)`.

`containsAddress(address)` returns true when `address` is in the byte interval covered by the range:

```zig
base.addressInt() <= address.raw() and address.raw() < end().addressInt()
```

It does not require `address` to be page-aligned.

`containsFrameRange(other)` returns true when every frame in `other` lies in `self`. Empty ranges are contained if their boundary lies inside the containing range or on either boundary.

`overlaps(other)` returns true only for a non-empty frame intersection. Empty ranges never overlap.

`isAdjacent(other)` returns true when the exclusive end of one range equals the base of the other range. Empty ranges may be adjacent by the same boundary rule.

`intersection(other)` returns the non-empty intersection of `self` and `other`, or `null` when they do not overlap.

`span(other)` returns the smallest range covering both inputs, including any gap. Never overflows because the resulting bounds already exist in `self` or `other`.

`splitAt(at)` splits the range at frame `at`. Returns `{ left, right }` where `left = [base, at)` and `right = [at, end)`. Returns `error.OutOfBounds` when `at` lies outside `[base, end]`.

Methods other than `isValid` and `assertValid` require a valid receiver. Implementations may call `assertValid` when automatic checks are enabled.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| constants | none | none | comptime | none | value-only | none |
| `Page` instantiation | none | none | comptime | none | type-only | none |
| `Size` metadata | none | none | comptime | none | value-only | none |
| `Count.fromPages` | never | never | O(1) | none | value type | none |
| `Count.pages` | never | never | O(1) | none | value type | none |
| `Count.zero` | never | never | O(1) | none | value type | none |
| `Count.max` | never | never | O(1) | none | value type | none |
| `Count.fromBytesExact` | never | never | O(1) | none | value type | none |
| `Count.fromBytesRoundUp` | never | never | O(1) | none | value type | none |
| `Count.toBytes` | never | never | O(1) | none | value type | none |
| `Frame.fromAddress` | never | never | O(1) | none | value type | none |
| `Frame.fromAddressInt` | never | never | O(1) | none | value type | none |
| `Frame.address` | never | never | O(1) | none | value type | none |
| `Frame.addressInt` | never | never | O(1) | none | value type | none |
| `Frame.index` | never | never | O(1) | none | value type | none |
| `Frame.isValid` | never | never | O(1) | none | value type | none |
| `Frame.assertValid` | never | never | O(1) | none | value type | none |
| `Frame.isAlignedAddress` | never | never | O(1) | none | value type | none |
| `Frame.add` | never | never | O(1) | none | value type | none |
| `Frame.sub` | never | never | O(1) | none | value type | none |
| `FrameRange.fromBaseCount` | never | never | O(1) | none | value type | none |
| `FrameRange.fromAddressBytes` | never | never | O(1) | none | value type | none |
| `FrameRange.empty` | never | never | O(1) | none | value type | none |
| `FrameRange.isValid` | never | never | O(1) | none | value type | none |
| `FrameRange.assertValid` | never | never | O(1) | none | value type | none |
| `FrameRange.isEmpty` | never | never | O(1) | none | value type | none |
| `FrameRange.byteLen` | never | never | O(1) | none | value type | none |
| `FrameRange.end` | never | never | O(1) | none | value type | none |
| `FrameRange.containsFrame` | never | never | O(1) | none | value type | none |
| `FrameRange.containsAddress` | never | never | O(1) | none | value type | none |
| `FrameRange.containsFrameRange` | never | never | O(1) | none | value type | none |
| `FrameRange.overlaps` | never | never | O(1) | none | value type | none |
| `FrameRange.isAdjacent` | never | never | O(1) | none | value type | none |
| `Frame.containingAddress` | never | never | O(1) | none | value type | none |
| `Frame.nextAlignedAddress` | never | never | O(1) | none | value type | none |
| `FrameRange.fromAddressByteSpan` | never | never | O(1) | none | value type | none |
| `FrameRange.intersection` | never | never | O(1) | none | value type | none |
| `FrameRange.span` | never | never | O(1) | none | value type | none |
| `FrameRange.splitAt` | never | never | O(1) | none | value type | none |

These helpers perform no allocation, waiting, sleeping, spinning, hidden global access, atomics, barriers, syscalls, target probing, or architecture probing.

## Error behavior

- invalid `Addr` is a compile error;
- invalid `page_size` is a compile error;
- byte counts not exactly divisible by `Size.bytes` return `error.Misaligned` from exact conversions;
- address integers or address values not aligned to `Size.bytes` return `error.Misaligned` from frame constructors;
- arithmetic overflow or underflow returns `error.Overflow`;
- `splitAt` boundaries outside `[base, end]` return `error.OutOfBounds`;
- methods that require a valid receiver may assert on invalid `Frame` or `FrameRange` values.

## Debug assertion behavior

`Frame.assertValid()` checks frame alignment.

`FrameRange.assertValid()` checks:

- `base.isValid()`;
- `base.add(count)` succeeds.

Explicit `assertValid()` calls always perform the check.

Automatic invariant checks inside operations, if implemented, must be gated through `stdx.core.debug.checksEnabled` when the operation exposes a `SafetyMode` option. This spec does not require `Page` operations to expose a `SafetyMode` option.

Assertions document programmer errors. Malformed external inputs must use the error-returning constructors and conversion APIs.

## Implementation constraints

Implementation must:

- validate `Addr.Raw` is an unsigned integer type at compile time;
- validate `page_size` is non-zero and a power of two at compile time;
- avoid storing a page-size runtime field;
- use `enum(AddressInt) { _ }` for `Count`;
- use `enum(AddressInt) { _ }` for `Frame`;
- do not expose a page-family alias named `Raw`; use `AddressInt` for the `Addr.Raw` integer when the page namespace needs a public integer alias;
- avoid unchecked arithmetic overflow and underflow;
- avoid loops;
- avoid target or architecture probing;
- keep all page constants policy-free exact byte counts;
- keep `Page` under `addr`, not root.

Implementation may reuse `stdx.bits.isPowerOfTwo` and `stdx.addr.Address` arithmetic when behavior exactly matches this spec.

## Usage

Physical page family:

```zig
const Phys4K = stdx.addr.Page(stdx.addr.PhysAddr, stdx.addr.pages._4kib);

const base = try Phys4K.Frame.fromAddressInt(0x1000);
const count = Phys4K.Count.fromPages(16);
const range = try Phys4K.FrameRange.fromBaseCount(base, count);

_ = range;
```

Custom guest-physical page family:

```zig
const GpaTag = opaque {};
const Gpa = stdx.addr.Address(GpaTag, u64);
const Gpa4K = stdx.addr.Page(Gpa, stdx.addr.pages._4kib);

const base = try Gpa4K.Frame.fromAddress(Gpa.fromInt(0x0010_0000));
const pages = try Gpa4K.Count.fromBytesExact(2 * stdx.addr.pages._4kib);
const range = try Gpa4K.FrameRange.fromBaseCount(base, pages);

_ = range;
```

Rounded byte capacity:

```zig
const Phys4K = stdx.addr.Page(stdx.addr.PhysAddr, stdx.addr.pages._4kib);

const pages = try Phys4K.Count.fromBytesRoundUp(blob_len);
const backing_bytes = try pages.toBytes();

_ = backing_bytes;
```

Sub-page and unaligned wire addresses stay outside `Page`:

```zig
const hpet_register = stdx.addr.PhysAddr.fromInt(0xFED0_00F0);
_ = hpet_register;
```

Callers must not force arbitrary MMIO windows, PIO windows, ACPI table addresses, or packed wire addresses into `Page.Frame` unless the owning domain has a real page-alignment contract.

## Required tests

Required for at least:

- `Page(addr.PhysAddr, pages._4kib)`;
- `Page(addr.VirtAddr, pages._4kib)` where practical;
- one custom `Address(Tag, u64)` type;
- one small custom `Address(Tag, u8)` or similar small unsigned width with a small page size such as `4`.

### Constants

- constants equal their exact byte counts;
- constants are usable as comptime `page_size` arguments;
- constants do not require architecture-specific imports.

### Page instantiation

Where practical:

- invalid page size `0` fails to instantiate;
- non-power-of-two page size fails to instantiate;
- invalid `Addr` type fails to instantiate;
- `Size.bytes`, `Size.mask`, and `Size.shift` match the page size.

### Count

- `fromPages` and `pages` round trip `0`, `1`, and a non-trivial value;
- `zero().pages()` returns `0`;
- `max().pages()` returns `std.math.maxInt(AddressInt)`;
- `fromBytesExact(0)` returns `0` pages;
- exact multiples convert to the expected count;
- non-exact byte counts return `error.Misaligned`;
- `fromBytesRoundUp(0)` returns `0` pages;
- values smaller than one page round up to one page;
- non-exact multiples round up;
- round-up overflow returns `error.Overflow`;
- `toBytes` returns expected byte counts;
- `toBytes` overflow returns `error.Overflow`.

### Frame

- `fromAddressInt` accepts aligned address integers;
- `fromAddressInt` rejects misaligned address integers;
- `fromAddress` accepts aligned addresses;
- `fromAddress` rejects misaligned addresses;
- `addressInt` and `address` return the aligned base;
- `index` returns `addressInt / Size.bytes`;
- `isValid` distinguishes aligned and misaligned enum values where practical;
- `assertValid` succeeds for a frame constructed through `fromAddressInt`;
- `isAlignedAddress` covers aligned and unaligned addresses;
- `add` advances by pages;
- `add` catches overflow;
- `sub` moves backward by pages;
- `sub` catches underflow.

### FrameRange

- `fromBaseCount` accepts zero count and non-zero count;
- `fromBaseCount` catches end overflow;
- `fromAddressBytes` accepts aligned base and exact byte length;
- `fromAddressBytes` rejects misaligned base;
- `fromAddressBytes` rejects non-exact byte length;
- `empty` creates a valid empty range;
- `isValid` and `assertValid` cover valid ranges;
- `isEmpty` covers empty and non-empty ranges;
- `byteLen` covers zero and non-zero counts;
- `end` returns the exclusive end frame;
- `containsFrame` includes the base and excludes the end;
- `containsAddress` includes byte addresses inside the range and excludes the end address;
- `containsAddress` does not require the queried address to be page-aligned;
- `containsFrameRange` handles empty ranges at start and end;
- `overlaps` rejects adjacent ranges and empty intersections;
- `isAdjacent` detects boundary contact;
- `fromAddressByteSpan` rounds unaligned start down and end up;
- `fromAddressByteSpan` catches rounding overflow;
- `intersection` returns null for disjoint or adjacent ranges and returns the shared non-empty range;
- `span` covers both ranges including gaps;
- `splitAt` splits at start, middle, and end;
- `splitAt` rejects frames outside `[base, end]` with `error.OutOfBounds`.

### Type identity

- same `Addr` and same `page_size` produce the same `Frame` and `FrameRange` types;
- different `Addr` with the same `page_size` produces different `Frame` and `FrameRange` types;
- same `Addr` with different `page_size` produces different `Frame` and `FrameRange` types;
- `Phys4K.Frame` is not assignment-compatible with `Virt4K.Frame` where practical;
- `Phys4K.FrameRange` is not assignment-compatible with `Phys2M.FrameRange` where practical.

### Compile-time behavior

Where practical:

```zig
comptime {
    const A = stdx.addr.Address(enum { a }, u8);
    const A4 = stdx.addr.Page(A, 4);

    std.debug.assert(A4.Size.bytes == 4);
    std.debug.assert(A4.Size.mask == 3);
    std.debug.assert(A4.Size.shift == 2);

    const frame = try A4.Frame.fromAddressInt(8);
    std.debug.assert(frame.index() == 2);

    const count = try A4.Count.fromBytesRoundUp(7);
    std.debug.assert(count.pages() == 2);
}
```

## Open questions

None.
