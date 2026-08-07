# Bit masks

Status: Approved.

`stdx.bits.mask` constructs low-bit, single-bit, and inclusive bit-range masks for unsigned integer values.

## What this spec is

This spec defines `stdx.bits.mask.low`, `stdx.bits.mask.single`, and `stdx.bits.mask.range`, their unsigned-integer type restriction, and their bounds assertions.

## What this spec is not

This spec does not define bitmap storage, word-index arithmetic, bit scans, bit mutation, typed bitfields, or hardware-register layouts. `docs/specs/bits/word.md` defines bitmap word operations.

## Public namespace and source ownership

```zig
stdx.bits.mask
stdx.bits.mask.low
stdx.bits.mask.single
stdx.bits.mask.range
```

`src/bits.zig` exports `mask`. The implementation is `src/bits/mask.zig`. The tests are in `test/bits/mask_test.zig`.

## Global invariants

`T` MUST be a non-zero-width unsigned integer type. An invalid `T` is a compile error.

`count` is in `0...@bitSizeOf(T)`. `index`, `first`, and `last` are zero-based bit positions; a valid position is less than `@bitSizeOf(T)`.

The caller MUST provide a valid `count` to `low`. The caller MUST provide valid positions and `first <= last` to `range`. The implementation MUST assert invalid counts, positions, and inverted ranges.

The operations do not allocate, wait, mutate caller state, or establish ordering or concurrency effects.

## API

```zig
pub fn low(comptime T: type, count: usize) T;
pub fn single(comptime T: type, index: usize) T;
pub fn range(comptime T: type, first: usize, last: usize) T;
```

`low(T, count)` returns `T` with its lowest `count` bits set. It returns zero for `count == 0` and all ones for `count == @bitSizeOf(T)`.

`single(T, index)` returns `T` with only bit `index` set.

`range(T, first, last)` returns `T` with every bit from `first` through `last`, inclusive, set.

## Implementation constraints

The implementation MUST not shift by `@bitSizeOf(T)`. `low` and `range` MUST return all ones for a full-width mask.

## Testing

Tests MUST evaluate `u8`, `u32`, and `u64` to verify the type-width contract. Tests MUST verify zero, partial, and full-width `low` masks; first, interior, and last `single` masks; and interior and full-width inclusive ranges. These cases prove the inclusive bounds and the full-width no-invalid-shift behavior. Tests MUST also evaluate the operations at comptime to prove that the API supports comptime use.
