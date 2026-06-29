# Layout unaligned access

Status: Approved.

`zstdx.layout.unalignedLoad` and `zstdx.layout.unalignedStore` copy a
fixed-size value representation to or from a byte window whose address may be
less aligned than the value type.

They are byte-copy primitives. They do not perform endian conversion, bounds
checking, validation, volatile access, or pointer reinterpretation.

## Owned scope

This spec owns:

- `layout.unalignedLoad`;
- `layout.unalignedStore`;
- unaligned fixed-size byte-window loads and stores;
- allowed type categories and caller validity rules;
- no-allocation and no-waiting behavior;
- required tests.

This spec does not own:

- endian conversion;
- offset arithmetic or bounds checking;
- cursor, builder, reader, or writer APIs;
- pointer provenance or lifetime recovery;
- semantic validation of external bytes;
- volatile or MMIO access;
- atomic access or memory fences;
- packed-view field access;
- slice, string, or allocator-bearing object serialization.

## Public namespace

Unaligned helpers live under `zstdx.layout`:

```zig
zstdx.layout.unalignedLoad
zstdx.layout.unalignedStore
```

They are not root-promoted:

```zig
zstdx.unalignedLoad // not exported
zstdx.unalignedStore // not exported
```

Source ownership:

```text
src/layout.zig
src/layout/unaligned.zig
test/layout/unaligned_test.zig
```

`src/layout.zig` re-exports:

```zig
pub const unaligned = @import("layout/unaligned.zig");

pub const unalignedLoad = unaligned.unalignedLoad;
pub const unalignedStore = unaligned.unalignedStore;
```

## Approved API

```zig
pub fn unalignedLoad(comptime T: type, bytes: *const [@sizeOf(T)]u8) T;
pub fn unalignedStore(comptime T: type, bytes: *[@sizeOf(T)]u8, value: T) void;
```

`bytes` is a fixed-size byte window. Its pointer may have byte alignment only;
it does not need to satisfy `@alignOf(T)`.

No slice overload is approved in this spec. Callers with a slice must establish
bounds first, then pass a fixed window:

```zig
const value = zstdx.layout.unalignedLoad(u32, bytes[offset..][0..4]);
```

## Type contract

Supported uses:

- unsigned and signed integers;
- floats when raw bit round trips are intended;
- fixed-size arrays;
- packed structs whose owning spec proves bit layout;
- extern structs whose owning spec proves size, alignment, and offsets;
- endian wrapper types after `layout.Le(T)` and `layout.Be(T)` are approved.

Invalid or unsupported type categories must fail at compile time where
practical:

- slices;
- pointers;
- optionals;
- error unions and error sets;
- unions;
- functions;
- comptime-only types;
- zero-sized types.

A caller that loads bytes into `T` must ensure the byte pattern is a valid value
of `T`. This helper is not a validator. External wire formats should load an
integer or explicit layout wrapper first, then validate or convert into the
semantic type.

## Load semantics

`unalignedLoad(T, bytes)` copies exactly `@sizeOf(T)` bytes from `bytes` into a
new `T` value and returns it.

The result has the same object representation as the source bytes. No byte
order conversion occurs.

The implementation must not read outside `bytes[0..@sizeOf(T)]` and must not use
`@ptrCast(@alignCast(...))` to reinterpret the input as `*const T`.

## Store semantics

`unalignedStore(T, bytes, value)` copies exactly `@sizeOf(T)` bytes from `value`
into `bytes`.

No byte order conversion occurs.

The implementation must not write outside `bytes[0..@sizeOf(T)]` and must not
use `@ptrCast(@alignCast(...))` to reinterpret the destination as `*T`.

## Endian composition

Endian behavior belongs to `layout.Le(T)` and `layout.Be(T)`, not this spec.

Once endian wrapper types are approved, endian-aware code should compose them
with unaligned access:

```zig
const raw = zstdx.layout.unalignedLoad(zstdx.layout.Le(u32), bytes);
const value = raw.native();

zstdx.layout.unalignedStore(
    zstdx.layout.Le(u32),
    bytes,
    zstdx.layout.Le(u32).fromNative(value),
);
```

Until those wrappers exist, downstream projects may continue using
`std.mem.readInt` and `std.mem.writeInt` for endian-aware byte access.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `unalignedLoad` | never | never | O(`@sizeOf(T)`) | none | caller-owned memory | none |
| `unalignedStore` | never | never | O(`@sizeOf(T)`) | destination bytes | caller-owned memory | none |

These helpers perform no allocation, waiting, hidden global access, atomics,
barriers, volatile access, or target probing.

## Error behavior

These helpers have no error set.

Invalid `T` categories are compile errors where practical.

Supplying a byte pattern that is not a valid `T` value is a caller contract
violation. Runtime validation belongs in the consuming parser, view, builder, or
endian wrapper.

## Implementation constraints

Implementation must:

- use byte copying equivalent to `@memcpy`;
- avoid typed loads from under-aligned pointers;
- avoid unchecked pointer reinterpretation;
- read or write exactly `@sizeOf(T)` bytes;
- avoid loops where the compiler-provided copy is sufficient;
- preserve every byte of the representation;
- compile for all supported Zig targets.

## Usage

Native object-representation load from a fixed byte window:

```zig
const value = zstdx.layout.unalignedLoad(u32, bytes[pos..][0..4]);
```

Native object-representation store:

```zig
zstdx.layout.unalignedStore(u64, bytes[pos..][0..8], value);
```

Packed flags through an integer lane:

```zig
const bits = zstdx.layout.unalignedLoad(u32, bytes[pos..][0..4]);
const flags: Flags = @bitCast(bits);
```

Endian-aware access after endian wrappers are approved:

```zig
const le = zstdx.layout.unalignedLoad(zstdx.layout.Le(u64), bytes[pos..][0..8]);
const phys = le.native();
```

## Planned consumers

`zvm` uses this shape for KVM MMIO/PIO byte payload marshaling and identity
digest byte encoders. Endian-aware TLV helpers should compose through
`layout.Le(T)` after that spec lands.

`zfw` uses this shape for UEFI NV variable record headers, GUID byte fields, and
device-path node lengths. Packed flag words should load an integer lane first,
then `@bitCast` to the packed flag type.

`zacpi` uses this shape under ACPI little-endian helpers. XSDT entries are the
load-bearing case: `u64` entries begin after a 36-byte SDT header, so they are
not naturally 8-byte aligned.

## Required tests

Required for `u8`, `u16`, `u32`, `u64`, and `usize`.

### Integer round trips

- load returns the value represented by the source bytes in native object order;
- store writes the exact native object representation of the value;
- store followed by load returns the original value.

### Non-native widths

Where practical:

- a non-native integer width such as `u24` or `u40` round trips;
- all bytes in the non-native-width representation are preserved.

### Offset windows

- load succeeds from byte windows starting at deliberately unaligned offsets;
- store succeeds into byte windows starting at deliberately unaligned offsets;
- store mutates only the selected `0..@sizeOf(T)` byte window.

### Layout types

- a packed struct round trips;
- an extern `align(1)` struct round trips;
- layout-boundary test types include colocated `@sizeOf`, `@alignOf`, and
  `@offsetOf` assertions.

### Compile-time behavior

Where practical:

```zig
comptime {
    var bytes = [_]u8{ 0x34, 0x12 };
    const value = zstdx.layout.unalignedLoad(u16, &bytes);
    var out = [_]u8{ 0, 0 };
    zstdx.layout.unalignedStore(u16, &out, value);
    std.debug.assert(out[0] == bytes[0]);
    std.debug.assert(out[1] == bytes[1]);
}
```

### Invalid types

Where practical, compile-fail tests cover unsupported type categories such as
pointers, slices, optionals, unions, functions, and zero-sized types.

## Open questions

None.
