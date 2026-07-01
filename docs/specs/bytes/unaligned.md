# Bytes unaligned access

Status: Approved.

`stdx.bytes.loadUnaligned` and `stdx.bytes.storeUnaligned` copy a
fixed-size value representation to or from a byte window whose address may be
less aligned than the value type.

They are byte-copy primitives. They do not perform endian conversion, bounds
checking, validation, volatile access, or pointer reinterpretation.

These primitives are the fixed-window foundation underneath the bounds-checked
random-access helpers in `docs/specs/bytes/access.md` and the sequential
`bytes.Cursor` in `docs/specs/bytes/cursor.md`. Random-access and sequential
typed reads compose by carving a `*const [@sizeOf(T)]u8` window and calling
`loadUnaligned` on it.

## Owned scope

This spec owns:

- `bytes.loadUnaligned`;
- `bytes.storeUnaligned`;
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

Unaligned helpers live under `stdx.bytes`:

```zig
stdx.bytes.loadUnaligned
stdx.bytes.storeUnaligned
```

They are not root-promoted:

```zig
stdx.loadUnaligned  // not exported
stdx.storeUnaligned // not exported
```

Source ownership:

```text
src/bytes.zig
src/bytes/unaligned.zig
test/bytes/unaligned_test.zig
```

`src/bytes.zig` re-exports:

```zig
pub const unaligned = @import("bytes/unaligned.zig");

pub const loadUnaligned = unaligned.loadUnaligned;
pub const storeUnaligned = unaligned.storeUnaligned;
```

## Approved API

```zig
pub fn loadUnaligned(comptime T: type, bytes: *const [@sizeOf(T)]u8) T;
pub fn storeUnaligned(comptime T: type, bytes: *[@sizeOf(T)]u8, value: T) void;
```

`bytes` is a fixed-size byte window. Its pointer may have byte alignment only;
it does not need to satisfy `@alignOf(T)`.

No slice overload is approved in this spec. Callers with a slice must establish
bounds first, then pass a fixed window:

```zig
const value = stdx.bytes.loadUnaligned(u32, bytes[offset..][0..4]);
```

The bounds-checked `stdx.bytes.load` and `stdx.bytes.store` helpers in
`docs/specs/bytes/access.md` compose these primitives for callers that need
the bounds check at a runtime offset.

## Type contract

Supported uses:

- unsigned and signed integers;
- floats when raw bit round trips are intended;
- fixed-size arrays;
- packed structs whose owning spec proves bit layout;
- extern structs whose owning spec proves size, alignment, and offsets;
- endian wrapper types `layout.Le(T)` and `layout.Be(T)`.

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

`loadUnaligned(T, bytes)` copies exactly `@sizeOf(T)` bytes from `bytes` into a
new `T` value and returns it.

The result has the same object representation as the source bytes. No byte
order conversion occurs.

The implementation must not read outside `bytes[0..@sizeOf(T)]` and must not use
`@ptrCast(@alignCast(...))` to reinterpret the input as `*const T`.

## Store semantics

`storeUnaligned(T, bytes, value)` copies exactly `@sizeOf(T)` bytes from
`value` into `bytes`.

No byte order conversion occurs.

The implementation must not write outside `bytes[0..@sizeOf(T)]` and must not
use `@ptrCast(@alignCast(...))` to reinterpret the destination as `*T`.

## Endian composition

Endian behavior belongs to `layout.Le(T)` and `layout.Be(T)`, not this spec.

Endian-aware code composes endian wrappers with unaligned access:

```zig
const raw = stdx.bytes.loadUnaligned(stdx.layout.Le(u32), bytes);
const value = raw.native();

stdx.bytes.storeUnaligned(
    stdx.layout.Le(u32),
    bytes,
    stdx.layout.Le(u32).fromNative(value),
);
```

## Behavior contract

| Operation         | Allocation | Waiting | Bounds          | Invalidation       | Concurrency         | Ordering |
| ---               | ---        | ---     | ---             | ---                | ---                 | ---      |
| `loadUnaligned`   | never      | never   | O(`@sizeOf(T)`) | none               | caller-owned buffer | none     |
| `storeUnaligned`  | never      | never   | O(`@sizeOf(T)`) | destination bytes  | caller-owned buffer | none     |

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
const value = stdx.bytes.loadUnaligned(u32, bytes[pos..][0..4]);
```

Native object-representation store:

```zig
stdx.bytes.storeUnaligned(u64, bytes[pos..][0..8], value);
```

Packed flags through an integer lane:

```zig
const bits = stdx.bytes.loadUnaligned(u32, bytes[pos..][0..4]);
const flags: Flags = @bitCast(bits);
```

Endian-aware access through endian wrappers:

```zig
const le = stdx.bytes.loadUnaligned(stdx.layout.Le(u64), bytes[pos..][0..8]);
const phys = le.native();
```

## Planned use

MMIO/PIO byte payload marshaling, digest byte encoders, and endian-aware
TLV helpers compose through `layout.Le(T)` and `layout.Be(T)`.

Fixed-layout record headers, GUID byte fields, and device-path node lengths
use this shape. Packed flag words load an integer lane first, then `@bitCast`
to the packed flag type.

Little-endian on-disk or on-wire integer fields at non-natural alignment —
for example, 64-bit entries following a header whose size is not a multiple
of 8 bytes — are a load-bearing case.

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
    const value = stdx.bytes.loadUnaligned(u16, &bytes);
    var out = [_]u8{ 0, 0 };
    stdx.bytes.storeUnaligned(u16, &out, value);
    std.debug.assert(out[0] == bytes[0]);
    std.debug.assert(out[1] == bytes[1]);
}
```

### Invalid types

Where practical, compile-fail tests cover unsupported type categories such as
pointers, slices, optionals, unions, functions, and zero-sized types.

## Open questions

None.
