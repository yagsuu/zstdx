# Layout endian integers

Status: Approved.

`stdx.layout.EndianInt(T, endian)` is a byte-stable integer storage type.
`stdx.layout.Le(T)` and `stdx.layout.Be(T)` specialize it for little-endian
and big-endian fields.

Endian wrappers model wire, ABI, and persisted integer lanes whose byte order is
part of the data contract. They are storage types, not readers, cursors, or
semantic validators.

## Owned scope

This spec owns:

- `layout.EndianInt(T, endian)`;
- `layout.Le(T)`;
- `layout.Be(T)`;
- endian integer storage wrappers;
- unsigned byte-aligned integer type restrictions;
- native integer conversion;
- exact byte-count and alignment guarantees;
- composition with `bytes.loadUnaligned` and `bytes.storeUnaligned`;
- required tests.

This spec does not own:

- bounds-checked read or write helpers;
- byte cursors, builders, readers, or writers;
- variable-length integers;
- bit readers or bit writers;
- enum, packed-struct, or extern-struct endian wrappers;
- pointer reinterpretation;
- volatile or MMIO access;
- semantic validation of loaded values;
- checksum or reserved-bit policy;
- root exports.

## Public namespace

Endian integer wrappers live under `stdx.layout`:

```zig
stdx.layout.EndianInt
stdx.layout.Le
stdx.layout.Be
```

They are not root-promoted:

```zig
stdx.EndianInt // not exported
stdx.Le // not exported
stdx.Be // not exported
```

Source ownership:

```text
src/layout.zig
src/layout/endian.zig
test/layout/endian_test.zig
```

`src/layout.zig` re-exports:

```zig
pub const endian = @import("layout/endian.zig");

pub const EndianInt = endian.EndianInt;
pub const Le = endian.Le;
pub const Be = endian.Be;
```

## Approved API

```zig
pub fn EndianInt(comptime T: type, comptime endian: std.builtin.Endian) type;
pub fn Le(comptime T: type) type;
pub fn Be(comptime T: type) type;
```

Returned type from `EndianInt`:

```zig
pub const Self = extern struct {
    bytes: [byte_count]u8,

    pub const Native = T;
    pub const byte_order = endian;
    pub const bit_count = @bitSizeOf(T);
    pub const byte_count = bit_count / 8;

    pub fn fromNative(value: T) Self;
    pub fn native(self: Self) T;
};
```

Convenience factories:

```zig
pub fn Le(comptime T: type) type {
    return EndianInt(T, .little);
}

pub fn Be(comptime T: type) type {
    return EndianInt(T, .big);
}
```

## Type contract

`T` must be an unsigned byte-aligned integer type with a bit width from 8 to 128
inclusive.

Allowed examples:

```zig
u8
u16
u24
u32
u40
u64
u128
```

Rejected type categories must fail at compile time where practical:

- signed integers;
- `usize` and `isize`;
- `comptime_int`;
- integer widths below 8 bits;
- integer widths above 128 bits;
- integer widths that are not a multiple of 8;
- bools;
- floats;
- enums;
- packed structs;
- extern structs;
- pointers and slices;
- optionals;
- error unions and error sets;
- unions;
- functions;
- comptime-only types.

Enums, packed flags, and domain types must convert through an explicit backing
integer before using endian wrappers.

## Layout guarantees

For a valid `T`:

```zig
@sizeOf(stdx.layout.Le(T)) == @bitSizeOf(T) / 8
@sizeOf(stdx.layout.Be(T)) == @bitSizeOf(T) / 8
@alignOf(stdx.layout.Le(T)) == 1
@alignOf(stdx.layout.Be(T)) == 1
```

The returned type is an `extern struct` wrapping exactly one field:

```zig
bytes: [@bitSizeOf(T) / 8]u8
```

`@sizeOf(T)` is not the wrapper byte count. Non-native integer widths use their
bit width:

```zig
@sizeOf(stdx.layout.Le(u24)) == 3
@sizeOf(stdx.layout.Be(u40)) == 5
```

## Byte order

For `Le(T)`, `bytes[0]` contains the least significant byte of the integer.

For `Be(T)`, `bytes[0]` contains the most significant byte of the integer.

For `u8`, little-endian and big-endian encodings are identical.

Byte order is independent of the host target's native endianness.

## Conversion semantics

`fromNative(value)` returns an endian wrapper whose bytes encode `value` in the
wrapper's byte order.

`native()` decodes the wrapper bytes into native integer `T`.

Required round trip:

```zig
EndianInt(T, endian).fromNative(value).native() == value
```

Every byte pattern is valid because `T` is restricted to unsigned integers.
Conversion never allocates, waits, validates external policy, or touches memory
outside the wrapper value.

## Struct field usage

Endian wrappers are intended for explicit wire and ABI fields:

```zig
const Header = extern struct {
    length: stdx.layout.Le(u16),
    generation: stdx.layout.Le(u64),
};

const length = header.length.native();
header.generation = stdx.layout.Le(u64).fromNative(next_generation);
```

The wrapper's alignment is 1, so this models unaligned byte layouts without
`u32 align(1)` fields plus local conversion code.

## Unaligned composition

`bytes.loadUnaligned` and `bytes.storeUnaligned` are byte-copy primitives.
Endian wrappers compose with them for endian-aware unaligned fields:

```zig
const le = stdx.bytes.loadUnaligned(stdx.layout.Le(u32), bytes[pos..][0..4]);
const value = le.native();

stdx.bytes.storeUnaligned(
    stdx.layout.Le(u32),
    bytes[pos..][0..4],
    stdx.layout.Le(u32).fromNative(value),
);
```

Bounds checking remains the caller's responsibility until a cursor or checked
offset spec owns that behavior.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `fromNative` | never | never | O(`byte_count`) | none | value type | none |
| `native` | never | never | O(`byte_count`) | none | value type | none |
| `Le` | never | never | comptime | none | type factory | none |
| `Be` | never | never | comptime | none | type factory | none |

These helpers perform no allocation, waiting, hidden global access, atomics,
barriers, volatile access, or target probing.

## Error behavior

These helpers have no error set.

Invalid `T` categories are compile errors where practical.

Semantic validation belongs to the consuming parser, view, builder, or domain
type after converting to the native unsigned integer.

## Implementation constraints

Implementation must:

- use `@bitSizeOf(T) / 8` as the byte count;
- never use `@sizeOf(T)` as the integer lane width;
- preserve exactly `byte_count` bytes;
- be independent of target native endianness;
- avoid allocation, global state, atomics, fences, and volatile access;
- avoid pointer reinterpretation as a larger aligned integer;
- compile for all supported Zig targets;
- produce compile errors for invalid `T` categories where practical.

## Planned consumers

`zvm` uses little-endian canonical digest and TLV fields currently written with
`std.mem.writeInt`, `std.mem.readInt`, and `std.mem.nativeToLittle`.

`zfw` uses little-endian UEFI NV variable record headers and GUID fields. Its
TPM command codec needs big-endian integer lanes.

`zacpi` uses little-endian ACPI integer fields. XSDT entries are 64-bit physical
addresses after a 36-byte SDT header, so endian wrappers compose with unaligned
loads and stores.

## Required tests

Required for `Le(u8)`, `Le(u16)`, `Le(u32)`, `Le(u64)`, `Be(u8)`, `Be(u16)`,
`Be(u32)`, and `Be(u64)`.

### Byte order

- `Le(u16).fromNative(0x1234).bytes` equals `.{ 0x34, 0x12 }`;
- `Be(u16).fromNative(0x1234).bytes` equals `.{ 0x12, 0x34 }`;
- `Le(u32)`, `Le(u64)`, `Be(u32)`, and `Be(u64)` match known constants;
- `Le(u8)` and `Be(u8)` preserve the single byte.

### Non-native widths

- `Le(u24)` has size 3 and alignment 1;
- `Be(u40)` has size 5 and alignment 1;
- `Le(u24)` and `Be(u40)` match known byte constants;
- `fromNative(...).native()` round trips for non-native widths.

### Layout

- `@alignOf(Le(u64)) == 1`;
- `@alignOf(Be(u64)) == 1`;
- an `extern struct` with `u8`, `Le(u16)`, and `Le(u64)` fields has expected
  offsets and size;
- an `extern struct` with `u8`, `Be(u16)`, and `Be(u64)` fields has expected
  offsets and size.

### Round trips

- `fromNative(value).native()` returns `value` for every required width;
- zero and max values round trip;
- repeated conversion does not change bytes.

### Unaligned composition

- `bytes.loadUnaligned(Le(u32), bytes[offset..][0..4]).native()` decodes the
  expected value at a deliberately unaligned offset;
- `bytes.storeUnaligned(Le(u32), bytes[offset..][0..4], Le(u32).fromNative(value))`
  writes only the selected byte window;
- equivalent `Be(u32)` load and store cases are covered.

### Packed flag lanes

- load a `Le(u32)` value, convert to native, and `@bitCast` into a packed flag
  struct;
- convert a packed flag struct to its backing integer, then store as `Le(u32)`.

### Compile-time behavior

Where practical:

```zig
comptime {
    const le = stdx.layout.Le(u16).fromNative(0x1234);
    std.debug.assert(le.bytes[0] == 0x34);
    std.debug.assert(le.bytes[1] == 0x12);
    std.debug.assert(le.native() == 0x1234);
}
```

### Invalid types

Where practical, compile-fail tests cover signed integers, `usize`, `isize`,
`comptime_int`, non-byte-aligned integer widths, integers wider than 128 bits,
bools, floats, enums, structs, pointers, slices, optionals, unions, functions,
and error types.

## Open questions

None.
