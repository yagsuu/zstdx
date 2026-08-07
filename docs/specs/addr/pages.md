# Address pages

Status: Approved.

`stdx.addr.Page(Addr, page_size)` defines a zero-cost page family for one address domain and one compile-time page size. The family distinguishes byte addresses, page counts, aligned frames, and half-open frame ranges.

## What this spec is

This spec defines exact page-size constants, `addr.Page`, page-size validation, `Size` metadata, `Count`, `Frame`, `FrameRange`, checked byte/page conversion, checked frame arithmetic, and range operations.

## What this spec is not

This spec does not define runtime-selected page sizes, page-table formats, TLB or cache behavior, allocation, address discovery, physical dereferencing, virtual-to-physical translation, DMA/IOMMU policy, MMIO access, or root exports. It does not classify guest memory or define UEFI memory policy.

## Terminology

- **page family**: The namespace returned by `Page(Addr, page_size)`.
- **frame**: A page-aligned address base in a page family.
- **frame range**: A half-open range of frames.
- **valid frame range**: A range whose base is valid and whose exclusive end is representable.

## Public namespace and source ownership

The public namespace is `stdx.addr` and `stdx.addr.pages`:

```zig
stdx.addr.pages._4kib
stdx.addr.pages._16kib
stdx.addr.pages._64kib
stdx.addr.pages._2mib
stdx.addr.pages._1gib
stdx.addr.Page
```

Source ownership is:

```text
src/addr.zig
src/addr/pages.zig
test/addr/pages_test.zig
```

`src/addr.zig` re-exports the `pages` module and `pages.Page`.

## Cross-spec relationships

A page family depends on an address-compatible type as defined by `docs/specs/addr/address.md`. This specification composes address values into page concepts but does not own address-domain policy.

## Data structures and representation

`Page` stores no runtime page-size field. `Size` is compile-time metadata. `Count` and `Frame` use `enum(AddressInt) { _ }`, where `AddressInt` is `Addr.Raw`. `FrameRange` stores a `Frame` base and a `Count` count. Its fields are intentionally public through the type definition shown in the API.

A page family is identified by both `Addr` and `page_size`. Different address types produce different `Frame` and `FrameRange` types. Different page sizes also produce different `Frame` and `FrameRange` types.

## Global invariants

- `Addr` exposes an unsigned `Raw` type, `fromInt(Raw) Addr`, and `raw(Addr) Raw`; otherwise `Page` causes a compile error.
- `page_size` is a nonzero power of two representable by `Addr.Raw`; otherwise `Page` causes a compile error.
- `Count` may represent every `AddressInt` value, including zero.
- A valid `Frame` has an address integer aligned to `Size.bytes`.
- A valid `FrameRange` has a valid base and a representable exclusive end.
- Operations allocate no memory, wait, sleep, spin, access hidden globals, issue atomics or barriers, make syscalls, or probe a target or architecture.
- Each runtime operation has constant time and does not invalidate values.

## API

```zig
pub const _4kib = 4 * 1024;
pub const _16kib = 16 * 1024;
pub const _64kib = 64 * 1024;
pub const _2mib = 2 * 1024 * 1024;
pub const _1gib = 1024 * 1024 * 1024;

pub fn Page(comptime Addr: type, comptime page_size: Addr.Raw) type;
```

`Page` returns this public namespace:

```zig
pub const Self = struct {
    pub const Address = Addr;
    pub const AddressInt = Addr.Raw;
    pub const Error = error{ Misaligned, Overflow, OutOfBounds };

    pub const Size = struct {
        pub const bytes: AddressInt = page_size;
        pub const mask: AddressInt = page_size - 1;
        pub const shift: comptime_int = @ctz(page_size);
    };

    pub const Count = enum(AddressInt) {
        _,
        pub fn fromPages(value: AddressInt) @This();
        pub fn pages(self: @This()) AddressInt;
        pub fn zero() @This();
        pub fn max() @This();
        pub fn fromBytesExact(bytes: AddressInt) Error!@This();
        pub fn fromBytesRoundUp(bytes: AddressInt) Error!@This();
        pub fn toBytes(self: @This()) Error!AddressInt;
    };

    pub const Frame = enum(AddressInt) {
        _,
        pub fn fromAddress(address: Addr) Error!@This();
        pub fn fromAddressInt(value: AddressInt) Error!@This();
        pub fn address(self: @This()) Addr;
        pub fn addressInt(self: @This()) AddressInt;
        pub fn frameIndex(self: @This()) AddressInt;
        pub fn isValid(self: @This()) bool;
        pub fn assertValid(self: @This()) void;
        pub fn isAlignedAddress(address: Addr) bool;
        pub fn containingAddress(address: Addr) Error!@This();
        pub fn nextAlignedAddress(address: Addr) Error!@This();
        pub fn add(self: @This(), count: Count) Error!@This();
        pub fn sub(self: @This(), count: Count) Error!@This();
    };

    pub const FrameRange = struct {
        base: Frame,
        count: Count,
        pub fn fromBaseCount(base: Frame, count: Count) Error!@This();
        pub fn fromAddressBytes(base: Addr, bytes: AddressInt) Error!@This();
        pub fn fromAddressByteSpan(start: Addr, byte_len: AddressInt) Error!@This();
        pub fn empty(at: Frame) @This();
        pub fn isValid(self: @This()) bool;
        pub fn assertValid(self: @This()) void;
        pub fn isEmpty(self: @This()) bool;
        pub fn byteLen(self: @This()) AddressInt;
        pub fn end(self: @This()) Frame;
        pub fn containsFrame(self: @This(), frame: Frame) bool;
        pub fn containsAddress(self: @This(), address: Addr) bool;
        pub fn containsFrameRange(self: @This(), other: @This()) bool;
        pub fn overlaps(self: @This(), other: @This()) bool;
        pub fn isAdjacent(self: @This(), other: @This()) bool;
        pub fn intersection(self: @This(), other: @This()) ?@This();
        pub fn span(self: @This(), other: @This()) @This();
        pub fn splitAt(self: @This(), at: Frame) Error!struct { left: @This(), right: @This() };
    };
};
```

## Page-size constants and `Size`

The constants are exact byte counts: `_4kib` is `4096`, `_16kib` is `16384`, `_64kib` is `65536`, `_2mib` is `2097152`, and `_1gib` is `1073741824`. They do not imply architecture support, allocation policy, a default page size, or page-table behavior.

`Size.bytes` equals `page_size`. `Size.mask` equals `Size.bytes - 1`. `Size.shift` equals `@ctz(Size.bytes)`, which is `log2(Size.bytes)` because page size is a power of two. `Size` performs no runtime work.

## `Count` contract

`fromPages` wraps an `AddressInt` page count without validation. `pages` returns the exact backing count. `zero` returns zero, and `max` returns `std.math.maxInt(AddressInt)`.

`fromBytesExact` converts a byte count to pages when the byte count is an exact multiple of `Size.bytes`; otherwise it returns `error.Misaligned`.

`fromBytesRoundUp` returns the smallest page count with byte capacity greater than or equal to `bytes`. It returns zero for zero bytes. It returns `error.Overflow` if adding the rounding offset is not representable by `AddressInt`.

`toBytes` returns `pages() * Size.bytes`. It returns `error.Overflow` if the product is not representable by `AddressInt`.

## `Frame` contract

`Frame` represents a page-aligned address base, not a page-frame number. `fromAddress` returns `error.Misaligned` unless the address is aligned to `Size.bytes`. `fromAddressInt` applies the same rule to `Addr.fromInt(value)`.

`address` returns the address-domain frame base. `addressInt` returns its raw integer. `frameIndex` returns `addressInt() >> Size.shift`.

`isValid` returns whether the stored address integer is aligned. `assertValid` asserts that condition and is for programmer errors and internal invariant checks, not external input validation. `isAlignedAddress` returns whether its address argument is aligned.

`containingAddress` returns the frame at the page boundary at or below `address`. `nextAlignedAddress` returns the frame at `address` when it is aligned; otherwise it returns the next page boundary. `nextAlignedAddress` returns `error.Overflow` if its rounding addition is not representable.

`add` and `sub` move a frame by `count` pages. They return `error.Overflow` if conversion of `count` to bytes or the resulting address arithmetic is not representable.

## `FrameRange` contract

A `FrameRange` represents `[base, base + count)`. `fromBaseCount` returns a range only when its exclusive end is representable; otherwise it returns `error.Overflow`.

`fromAddressBytes` requires a page-aligned base and an exact page-multiple length. It returns the errors from `Frame.fromAddress`, `Count.fromBytesExact`, or `fromBaseCount`.

`fromAddressByteSpan` covers the byte interval derived by rounding `start` down and `start + byte_len` up. It returns `error.Overflow` if addition of `byte_len` to `start` or upward rounding is not representable.

`empty(at)` returns a valid zero-count range at `at`. `isValid` checks base alignment and representability of the exclusive end. `assertValid` asserts `isValid`.

`isEmpty` returns whether the count is zero. `byteLen` returns the count in bytes. `end` returns the exclusive end frame. The receiver of `byteLen` and `end` MUST be valid; an invalid receiver is a programmer error.

`containsFrame` tests membership in `[base, end)`. `containsAddress` tests membership in `[base.addressInt(), end().addressInt())` and does not require alignment. `containsFrameRange` returns true when every frame in `other` is contained; an empty range is contained when its boundary is at or within either boundary of `self`.

`overlaps` returns true only for a non-empty intersection. Empty and merely adjacent ranges do not overlap. `isAdjacent` returns true when either exclusive end equals the other base; this rule also applies to empty ranges.

`intersection` returns the non-empty intersection or `null` for disjoint, adjacent, or empty inputs. `span` returns the smallest valid range that covers both inputs and any gap. `splitAt` returns `{ left, right }` with `left = [base, at)` and `right = [at, end)`. It returns `error.OutOfBounds` unless `at` is in `[base, end]`.

Every `FrameRange` operation other than `isValid` and `assertValid` requires valid receivers. `splitAt` also requires a valid `at` frame. Invalid values violate the caller contract and can trigger debug assertions.

## Errors and fault behavior

- Invalid `Addr` and `page_size` cause compile errors.
- Exact byte conversion and frame construction return `error.Misaligned` for an unaligned value.
- Checked conversion, rounding, range construction, and frame arithmetic return `error.Overflow` for unrepresentable arithmetic.
- `splitAt` returns `error.OutOfBounds` outside its inclusive split boundaries.
- Assertions identify invalid internal or caller-constructed `Frame` and `FrameRange` values; callers MUST use error-returning construction operations for malformed external input.

## Implementation constraints

The implementation MUST validate `Addr.Raw` and `page_size` at compile time. It MUST not store a runtime page-size field. It MUST use `enum(AddressInt) { _ }` for `Count` and `Frame`, expose `AddressInt` rather than a page-family `Raw` alias, use checked arithmetic where overflow or underflow is possible, and avoid loops, target probing, and architecture probing. Page constants MUST remain policy-free exact byte counts.

## Testing

Tests MUST instantiate physical and virtual four-KiB families, a custom wide address family, and a small unsigned address family. Compile-time checks MUST verify `Size` metadata and prove that family identity depends on both address type and page size. When the test harness supports expected compile failures, it MUST reject invalid page-size and address-family inputs. These methods verify strong type separation and compile-time validation.

Constant tests MUST verify the exact byte representation and comptime usability of each public page-size constant. `Count` tests MUST verify page/raw round trips, zero and maximum values, exact conversion, round-up conversion, and multiplication at successful and overflowing boundaries. These tests prove that byte/page conversion retains units and reports unrepresentable results.

`Frame` tests MUST verify aligned construction, rejection of unaligned construction, address and index conversion, alignment predicates, containing and next-boundary rounding, and page-count arithmetic at success and overflow boundaries. These tests prove that frames remain aligned and cannot wrap.

`FrameRange` tests MUST verify valid empty and non-empty construction, exact-byte construction, rounded byte spans, end and byte length, half-open containment, empty-range containment, overlap, adjacency, intersection, spanning gaps, and splitting at both boundaries and an interior point. Tests MUST also verify overflow and `error.OutOfBounds` boundaries. These tests prove range representation, interval semantics, and no-wrap behavior.
