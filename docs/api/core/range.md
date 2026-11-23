# `stdx.ranges.Range` / `stdx.ranges.InclusiveRange`

Intervals with public `start: T` and `end: T` bounds: `Range(T)` is half-open
`[start, end)`. `InclusiveRange(T)` is inclusive `[start, end]`.

## Domains and validity

| Contract | `Range(T)` | `InclusiveRange(T)` |
| --- | --- | --- |
| Endpoint domain | Unsigned integer, including `u0`, or a typed-address enum with unsigned `T.Int`, `T.from()` and `T.raw()` | Non-zero-width unsigned integer |
| Arithmetic domain | `Range.Int`: `T` for integers, `T.Int` for addresses. Lengths, offsets, and shift amounts use this type | `T` |
| Valid bounds | `start <= end`, compared through raw values for addresses | `start <= end` |
| Equal bounds | Empty | Singleton |

Unsupported endpoint types are compile errors. Address comparisons use `T.raw()`.
Resulting endpoints use `T.from()`. Inclusive ranges are non-empty and may span
the full domain even when their cardinality exceeds `T`.

Direct field initialization and range operations require valid bounds.
`Range.isValid()` and `InclusiveRange.isValid()` test validity.
Their `assertValid()` methods assert it.

Operations do not mutate their inputs. They perform O(1) endpoint work without
allocation or waiting, excluding address-type `T.raw()` and `T.from()` calls.

## Construction

| Operation | `Range(T)` | `InclusiveRange(T)` |
| --- | --- | --- |
| `Range.init(start, end)` / `InclusiveRange.init(start, end)` | Returns `[start, end)` | Returns `[start, end]` |
| `Range.of(start, end)` / `InclusiveRange.of(start, end)` | Constructs comptime bounds. Inverted bounds are a compile error | Same rule |
| `Range.fromStartLen(start, length)` / `InclusiveRange.fromStartLen(start, length)` | Returns `[start, start + length)`. Zero length is valid | Returns `[start, start + length - 1]`. Zero length returns `error.InvalidRange` before endpoint arithmetic |
| `Range.empty(at)` / `InclusiveRange.single(at)` | Returns `[at, at)` | Returns `[at, at]` |

`Range.init()` and `InclusiveRange.init()` return `error.InvalidRange` for
inverted bounds. `Range.fromStartLen()` and `InclusiveRange.fromStartLen()`
return `error.Overflow` when the resulting endpoint is not representable in
the arithmetic domain.

## Queries and combinations

| Operation | `Range(T)` | `InclusiveRange(T)` |
| --- | --- | --- |
| `Range.len()` | `end - start` | — |
| `Range.isEmpty()` / `InclusiveRange.isSingleton()` | `start == end` | `start == end` |
| `Range.contains(value)` / `InclusiveRange.contains(value)` | `start <= value and value < end` | `start <= value and value <= end` |
| `Range.containsRange(other)` / `InclusiveRange.containsRange(other)` | `start <= other.start and other.end <= end`. Includes empty subranges at either boundary | Same bound comparison |
| `Range.overlaps(other)` / `InclusiveRange.overlaps(other)` | True exactly when the intersection is non-empty. Empty ranges never overlap | True exactly when `max(start, other.start) <= min(end, other.end)`. Shared endpoints overlap |
| `Range.adjacent(other)` / `InclusiveRange.adjacent(other)` | `end == other.start or other.end == start`, including empty ranges | `end < other.start and other.start - end == 1`, or the symmetric condition |
| `Range.intersection(other)` / `InclusiveRange.intersection(other)` | Returns `[max(start, other.start), min(end, other.end))`, or `null` for empty intersection | Returns the inclusive bounds when ordered, otherwise `null`. Equal bounds produce a singleton |
| `Range.span(other)` / `InclusiveRange.span(other)` | Returns `[min(start, other.start), max(end, other.end))` | Returns the same bounds inclusively |

## Splits, offsets, and shifts

| Operation | `Range(T)` | `InclusiveRange(T)` |
| --- | --- | --- |
| `Range.prefix(point)` / `InclusiveRange.prefix(point)` | Accepts `point` in `[start, end]`. Returns `[start, point)` | Accepts a contained point. Returns `[start, point]` |
| `Range.suffix(point)` / `InclusiveRange.suffix(point)` | Accepts `point` in `[start, end]`. Returns `[point, end)` | Accepts a contained point. Returns `[point, end]` |
| `Range.offsetOf(value)` / `InclusiveRange.offsetOf(value)` | Returns `value - start` for a contained value, otherwise `null` | Same rule, including the final endpoint |
| `Range.atOffset(offset)` / `InclusiveRange.atOffset(offset)` | Returns `start + offset` when `offset < Range.len()`, otherwise `null` | Returns `start + offset` when `offset <= end - start`, otherwise `null` |
| `Range.shiftForward(amount)` / `InclusiveRange.shiftForward(amount)` | Adds `amount` to both bounds | Same rule |
| `Range.shiftBackward(amount)` / `InclusiveRange.shiftBackward(amount)` | Subtracts `amount` from both bounds | Same rule |

Split points outside the accepted interval return `error.OutOfBounds`.
Forward shifts return `error.Overflow` if either resulting bound is
unrepresentable. Backward shifts return it when `amount > start`.
Successful shifts preserve interval size.

## References

- [Range values and operations](../../../src/ranges/range.zig)
- [Range sets](../ranges/set.md) and [range maps](../ranges/map.md) consume
  half-open ranges, not inclusive ranges.
