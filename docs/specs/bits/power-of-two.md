# Bits power-of-two

Status: Approved.

`zstdx.bits` owns power-of-two integer helpers used by alignment, ring capacities, bitsets, hash maps, and other low-level primitives.

## Owned scope

This spec owns:

- `bits.isPowerOfTwo`;
- `bits.nextPowerOfTwo`;
- unsigned integer type restrictions;
- overflow behavior;
- required tests.

This spec does not own:

- alignment helpers;
- integer `log2` helpers;
- bit scans;
- popcount wrappers;
- saturating next-power-of-two variants;
- wrapping next-power-of-two variants;
- signed integer support.

## Public namespace

Power-of-two helpers live under `zstdx.bits`:

```zig
zstdx.bits.isPowerOfTwo
zstdx.bits.nextPowerOfTwo
```

They are not root-promoted:

```zig
zstdx.isPowerOfTwo // not exported
```

Source ownership:

```text
src/bits.zig
src/bits/power_of_two.zig
```

`src/bits.zig` re-exports:

```zig
pub const power_of_two = @import("bits/power_of_two.zig");

pub const isPowerOfTwo = power_of_two.isPowerOfTwo;
pub const nextPowerOfTwo = power_of_two.nextPowerOfTwo;
```

## Approved API

```zig
pub const Error = error{
    Overflow,
};

pub fn isPowerOfTwo(comptime T: type, value: T) bool;
pub fn nextPowerOfTwo(comptime T: type, value: T) Error!T;
```

`T` must be an unsigned integer type. Signed integers, floats, bools, enums, pointers, and comptime integers without an explicit `T` are compile errors.

Usage:

```zig
if (zstdx.bits.isPowerOfTwo(usize, capacity)) {
    // capacity is a power of two.
}

const next = try zstdx.bits.nextPowerOfTwo(usize, requested);
```

## `isPowerOfTwo` semantics

`isPowerOfTwo(T, value)` returns true iff `value` is a non-zero power of two.

Required behavior:

```zig
isPowerOfTwo(T, 0) == false
isPowerOfTwo(T, 1) == true
isPowerOfTwo(T, 2) == true
isPowerOfTwo(T, 3) == false
```

Canonical rule:

```zig
value != 0 and (value & (value - 1)) == 0
```

## `nextPowerOfTwo` semantics

`nextPowerOfTwo(T, value)` returns the smallest power of two greater than or equal to `value`.

Required behavior:

```zig
try nextPowerOfTwo(T, 0) == 1
try nextPowerOfTwo(T, 1) == 1
try nextPowerOfTwo(T, 2) == 2
try nextPowerOfTwo(T, 3) == 4
```

Overflow behavior:

- returns `error.Overflow` when no representable power of two exists.

For `u8`:

```zig
try nextPowerOfTwo(u8, 128) == 128
nextPowerOfTwo(u8, 129) == error.Overflow
```

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `isPowerOfTwo` | never | never | O(1) | none | pure function | none |
| `nextPowerOfTwo` | never | never | O(1) | none | pure function | none |

These functions perform no allocation, waiting, hidden global access, atomics, or barriers.

## Implementation constraints

Implementation must:

- avoid unchecked overflow;
- not use loops proportional to integer value;
- compile for all unsigned integer widths Zig supports;
- treat `0` as a special case returning `1` for `nextPowerOfTwo`;
- produce a compile error for invalid `T`.

Acceptable implementation approaches:

- `@clz` and bit-width based computation;
- checked shifts;
- a standard-library primitive only if behavior exactly matches this spec.

## Required tests

Required for `usize`, `u8`, and at least one non-native width such as `u17`.

### `isPowerOfTwo`

- `0` returns false;
- `1` returns true;
- exact powers return true;
- values adjacent to powers return false;
- max value behavior is covered for the type.

### `nextPowerOfTwo`

- `0` returns `1`;
- `1` returns `1`;
- exact powers return themselves;
- non-powers round up;
- highest representable power returns itself;
- values above the highest representable power return `error.Overflow`.

### Compile-time and type tests

Where practical:

- signed integer instantiation fails;
- bool and floats are rejected;
- comptime evaluation works:

```zig
comptime {
    std.debug.assert((try zstdx.bits.nextPowerOfTwo(u8, 7)) == 8);
}
```
