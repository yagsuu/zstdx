# Bit masks

Status: Approved.

`stdx.bits.mask` constructs low-bit, single-bit, and inclusive bit-range masks for unsigned integer values.

## What this spec is

This spec owns:

- `stdx.bits.mask.low(comptime T, count)`;
- `stdx.bits.mask.single(comptime T, index)`;
- `stdx.bits.mask.range(comptime T, first, last)`;
- unsigned-integer type validation;
- bounds assertions;
- `src/bits/mask.zig` and `test/bits/mask_test.zig`.

## What this spec is not

This spec does not own bitmap storage, word-index arithmetic, bit scans,
mutation, typed bitfields, or hardware-register layouts.
`docs/specs/bits/word.md` owns bitmap word operations.

## Public namespace and source ownership

```zig
stdx.bits.mask
stdx.bits.mask.low
stdx.bits.mask.single
stdx.bits.mask.range
```

`src/bits.zig` exports `mask`. No name is root-promoted.

Source ownership:

```text
src/bits.zig
src/bits/mask.zig
test/bits/mask_test.zig
```

## Global invariants

`T` MUST be a non-zero-width unsigned integer type. Invalid `T` is a compile error.

`count` is a bit count in the inclusive range `0...@bitSizeOf(T)`. `index`,
`first`, and `last` are zero-based bit positions. A valid position is less than
`@bitSizeOf(T)`.

`low` requires a valid `count`. `range` requires `first <= last`. Invalid
counts, positions, or inverted ranges are caller contract violations. The
implementation MUST assert these conditions.

The operations allocate never, wait never, mutate no caller state, and have no ordering or concurrency effects.

## API

```zig
pub fn low(comptime T: type, count: usize) T;
pub fn single(comptime T: type, index: usize) T;
pub fn range(comptime T: type, first: usize, last: usize) T;
```

### `low`

`low(T, count)` returns `T` with its lowest `count` bits set. It returns zero
when `count` is zero and all ones when `count == @bitSizeOf(T)`.

```text
low(u8, 0) == 0b0000_0000
low(u8, 3) == 0b0000_0111
low(u8, 8) == 0b1111_1111
```

### `single`

`single(T, index)` returns `T` with only bit `index` set.

```text
single(u8, 0) == 0b0000_0001
single(u8, 7) == 0b1000_0000
```

### `range`

`range(T, first, last)` returns `T` with every bit from `first` through `last`, inclusive, set.

```text
range(u8, 0, 0) == 0b0000_0001
range(u8, 2, 5) == 0b0011_1100
range(u8, 0, 7) == 0b1111_1111
```

## Implementation constraints

The implementation MUST avoid a shift by `@bitSizeOf(T)`. `low` and `range`
MUST return the all-ones value for a full-width mask.

## Testing

Tests MUST cover `u8`, `u32`, and `u64`.

Tests MUST cover:

- zero-, partial-, and full-width low masks;
- first and last single bits;
- an interior single bit;
- an interior inclusive range;
- the full-width range;
- comptime evaluation.
