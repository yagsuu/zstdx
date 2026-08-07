# Layout endian integers

Status: Approved.

`stdx.layout.EndianInt(T, endian)` defines an unsigned integer storage type with an explicit, byte-stable order.

## What this spec is

This spec defines:

- `stdx.layout.EndianInt(T, endian)`, `stdx.layout.Le(T)`, and `stdx.layout.Be(T)`;
- accepted integer types;
- storage representation, size, alignment, and byte order;
- conversion between native integers and endian storage values;
- allocation, waiting, concurrency, and error behavior; and
- required tests.

## What this spec is not

This spec does not define:

- bounds-checked or sequential byte access;
- variable-length integer or bit access;
- enum, packed-struct, or extern-struct conversion;
- pointer reinterpretation;
- volatile, MMIO, or atomic access;
- domain-specific integer validation; or
- root namespace exports.

## Public namespace and source ownership

The public declarations are:

```zig
stdx.layout.EndianInt
stdx.layout.Le
stdx.layout.Be
```

`src/layout/endian.zig` implements the declarations. `src/layout.zig` MUST re-export them as follows:

```zig
pub const endian = @import("layout/endian.zig");
pub const EndianInt = endian.EndianInt;
pub const Le = endian.Le;
pub const Be = endian.Be;
```

`test/layout/endian_test.zig` contains the required tests.

## Cross-spec relationships

`stdx.bytes.loadSlice` and `stdx.bytes.storeSlice` define runtime-offset bounds checks for byte slices. `std.mem.bytesToValue` and `std.mem.toBytes` define fixed-window object-representation conversion. This spec does not define those contracts.

## Data structures and representation

For valid `T` and `endian`, `EndianInt(T, endian)` MUST return an `extern struct` equivalent to:

```zig
extern struct {
    bytes: [count_bytes]u8,

    pub const Native = T;
    pub const byte_order = endian;
    pub const count_bits = @bitSizeOf(T);
    pub const count_bytes = count_bits / 8;

    pub fn fromNative(value: T) Self;
    pub fn native(self: Self) T;
}
```

The returned type MUST satisfy:

```zig
@sizeOf(EndianInt(T, endian)) == @bitSizeOf(T) / 8
@alignOf(EndianInt(T, endian)) == 1
```

The `bytes` field MUST be the only instance field. The type MUST contain no padding bytes.

For `.little`, `bytes[0]` MUST contain the least-significant byte. For `.big`, `bytes[0]` MUST contain the most-significant byte. The representation MUST be independent of target native endianness.

## Global invariants

Every bit pattern of `bytes` MUST represent one valid `T` value.

An operation on an endian integer value MUST NOT:

- allocate or free memory;
- wait, block, sleep, or spin;
- access hidden mutable state;
- issue a syscall;
- read a clock;
- perform an atomic, volatile, or barrier operation; or
- invoke a callback.

Endian integer values MAY be copied by value. A copy MUST preserve all representation bytes.

## API

```zig
pub fn EndianInt(
    comptime T: type,
    comptime endian: std.builtin.Endian,
) type;

pub fn Le(comptime T: type) type;
pub fn Be(comptime T: type) type;
```

`Le(T)` MUST return `EndianInt(T, .little)`. `Be(T)` MUST return `EndianInt(T, .big)`.

## Type contract

`T` MUST be an unsigned integer type. `@bitSizeOf(T)` MUST be a multiple of 8 from 8 through 128, inclusive. `T` MUST NOT be `usize`, `isize`, or a comptime-only type.

Instantiation MUST fail at compile time for:

- signed integers;
- `usize` and `isize`;
- `comptime_int` and `comptime_float`;
- integers narrower than 8 bits;
- integers wider than 128 bits;
- integer widths that are not multiples of 8;
- bools;
- floats;
- enums;
- packed structs;
- extern structs;
- pointers and slices;
- optionals;
- error unions and error sets;
- unions;
- functions; and
- `noreturn`, `null`, `undefined`, `type`, and `void`.

A caller MUST convert an enum, packed field set, or domain type to an accepted unsigned integer before it instantiates an endian integer type.

## `fromNative`

### Contract

`fromNative(value)` MUST return an endian integer whose `bytes` field encodes `value` in `byte_order`.

For each byte index `i` in `0..count_bytes`, `.little` encoding MUST store bits `i * 8 .. i * 8 + 8` at `bytes[i]`. For each byte index `i` in `0..count_bytes`, `.big` encoding MUST store bits `(count_bytes - 1 - i) * 8 .. (count_bytes - i) * 8` at `bytes[i]`.

### Errors and fault behavior

`fromNative` MUST NOT return an error.

### Complexity and progress

`fromNative` MUST have O(`count_bytes`) time complexity and MUST NOT wait.

## `native`

### Contract

`native()` MUST decode `bytes` according to `byte_order` and return the corresponding `T` value.

For every valid `value`, this round trip MUST hold:

```zig
EndianInt(T, endian).fromNative(value).native() == value
```

### Errors and fault behavior

`native` MUST NOT return an error.

### Complexity and progress

`native` MUST have O(`count_bytes`) time complexity and MUST NOT wait.

## Implementation constraints

The implementation MUST use `@bitSizeOf(T) / 8` as the representation byte count. The implementation MUST NOT use `@sizeOf(T)` as the integer lane width. The implementation MUST preserve exactly `count_bytes` representation bytes. The implementation MUST NOT reinterpret the byte array as a pointer to a more-aligned integer type. The implementation MUST compile for every target supported by the repository.

## Testing

Tests in `test/layout/endian_test.zig` MUST construct public endian types and compare compile-time layout queries, representation bytes, decoded values, and standard-library conversion results. These runtime and compile-time assertions verify the observable layout and conversion contract; this repository does not require compile-fail test infrastructure for rejected type arguments.

### Type and layout

Tests MUST compare `@sizeOf` and `@alignOf` with `count_bytes` and 1 for native and non-native widths. Tests MUST embed `Le(u16)` and `Be(u32)` in an `extern struct` and compare field offsets and total size. These assertions prove the exact representation size, byte alignment, and composable extern layout.

### Byte order and round trips

Tests MUST compare little-endian and big-endian byte sequences for a non-palindromic `u32` value. Tests MUST decode an explicit byte sequence and round-trip zero, a maximum value, and a non-palindromic value. These cases prove byte order and preservation of the full supported value range.

### Standard byte conversion

Tests MUST convert an endian value with `std.mem.toBytes`, recover it with `std.mem.bytesToValue`, and compare the decoded native value. This case proves that the exact object representation composes with standard byte-value conversion.
