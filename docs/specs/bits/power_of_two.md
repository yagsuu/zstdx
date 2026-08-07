# Power-of-two integer helpers

Status: Approved.

`stdx.bits` provides unsigned-integer predicates and rounding for powers of two.

## What this spec is

This spec defines `stdx.bits.isPowerOfTwo`, `stdx.bits.nextPowerOfTwo`, their unsigned-integer type restriction, overflow behavior, and required tests.

## What this spec is not

This spec does not define alignment helpers, integer `log2` helpers, bit scans, popcount wrappers, saturating or wrapping rounding, or signed-integer support.

## Public namespace and source ownership

```zig
stdx.bits.isPowerOfTwo
stdx.bits.nextPowerOfTwo
```

`src/bits.zig` re-exports the declarations from `src/bits/power_of_two.zig`. The tests are in `test/bits/power_of_two_test.zig`.

## Global invariants

`T` MUST be an unsigned integer type. Signed integers, floats, bools, enums, pointers, and comptime integers without an explicit `T` are compile errors.

The functions do not allocate, wait, access hidden globals, perform atomics or barriers, or invalidate caller state. Each operation has $O(1)$ time complexity.

## API

```zig
pub const Error = error{
    Overflow,
};

pub fn isPowerOfTwo(comptime T: type, value: T) bool;
pub fn nextPowerOfTwo(comptime T: type, value: T) Error!T;
```

### `isPowerOfTwo`

`isPowerOfTwo(T, value)` returns `true` exactly when `value` is a non-zero power of two. It returns `false` for zero and values with more than one set bit.

### `nextPowerOfTwo`

`nextPowerOfTwo(T, value)` returns the smallest representable power of two greater than or equal to `value`. It returns `1` for `value == 0` and `value == 1`. It returns `value` when `value` is already a power of two. It returns `error.Overflow` when no representable power of two satisfies the result contract; for example, `nextPowerOfTwo(u8, 129)` returns `error.Overflow`.

## Implementation constraints

The implementation MUST avoid unchecked overflow, support every Zig unsigned-integer width, and reject an invalid `T` at comptime. It MUST not use work proportional to the integer value.

## Testing

Tests MUST evaluate `usize`, `u8`, and one non-native width such as `u17` to verify width-independent behavior. Tests MUST verify zero, one, exact powers, and values adjacent to powers for `isPowerOfTwo`; these cases distinguish the non-zero predicate from single-bit and multi-bit inputs. Tests MUST verify zero, one, exact powers, round-up values, the highest representable power, and the next value for `nextPowerOfTwo`; these cases prove rounding and the overflow boundary. Compile-time tests MUST verify comptime evaluation. When the test harness supports expected compile failures, it MUST reject signed, boolean, and floating-point types.
