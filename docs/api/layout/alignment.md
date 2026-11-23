# `stdx.layout` alignment

Unsigned-integer helpers for rounding values to power-of-two boundaries and
computing the distance to those boundaries.

## Domain and preconditions

The explicit type argument `T` must be an unsigned integer type, including
non-native widths. Signed integers, `comptime_int`, and non-integer types are
compile errors. `value` and `alignment` both use `T`.

Every operation requires a non-zero, power-of-two `alignment`. Invalid alignment
violates a `std.debug.assert` precondition in `Debug` and `ReleaseSafe`.
Assertions are disabled in `ReleaseFast` and `ReleaseSmall`.
`u0` cannot represent a valid alignment.

## Operations

| Operation | Result |
| --- | --- |
| `layout.alignUp(T, value, alignment)` | Smallest multiple of `alignment` greater than or equal to `value`. Returns `error.Overflow` if that value is not representable in `T` |
| `layout.alignDown(T, value, alignment)` | Greatest multiple of `alignment` less than or equal to `value` |
| `layout.isAligned(T, value, alignment)` | Whether `value` is a multiple of `alignment` |
| `layout.alignUpDelta(T, value, alignment)` | Upward rounded value minus `value`. Returns `error.Overflow` under the same condition as `layout.alignUp()` |
| `layout.alignDownDelta(T, value, alignment)` | `value` minus the downward rounded value, equal to `value & (alignment - 1)` |

Already aligned values remain unchanged and have zero deltas. Zero is aligned
to every valid alignment. Alignment `1` leaves every value unchanged.
Downward rounding and its delta cannot overflow.

All operations support comptime evaluation and take O(1) time without allocation,
waiting, or input mutation.

## References

- [Integer alignment](../../../src/layout/alignment.zig)
