# Core range

Status: Approved.

`stdx.core.Range(T)` and `stdx.core.InclusiveRange(T)` are range values for unsigned integer
domains. `Range(T)` represents half-open intervals `[start, end)`. `InclusiveRange(T)` represents
inclusive intervals `[start, end]`. The types represent indices, bit positions, byte offsets,
bitmap spans, allocator extents, limits, and other count-like intervals.

## What this spec is

This specification defines:

- `stdx.core.Range(T)` and its half-open interval semantics;
- `stdx.core.InclusiveRange(T)` and its inclusive interval semantics;
- construction, validation, queries, range arithmetic, and conversions;
- failure behavior, implementation constraints, and required tests.

## What this spec is not

This specification does not define:

- address ranges, page ranges, pointer spans, or non-null pointer wrappers;
- range sets, range maps, iteration, slicing helpers, or coalescing;
- address arithmetic, page alignment, or signed-range semantics;
- allocation, waiting, scheduling, callbacks, synchronization, hardware access, or runtime policy.

`docs/specs/ranges/set.md` and `docs/specs/ranges/map.md` own range-collection behavior.

## Public namespace

`Range` and `InclusiveRange` are available as `stdx.core.Range` and
`stdx.core.InclusiveRange`. Neither type is available from the `stdx` namespace.

## Cross-spec relationships

The range-set and range-map specifications depend on the half-open semantics of `Range(T)`.
They compose with this specification but do not accept `InclusiveRange(T)`.

## Data structures and representation

`Range(T)` MUST be a value type with public `start` and `end` fields of type `T`. A valid
`Range(T)` represents `[start, end)` and satisfies `start <= end`. `start == end` represents an
empty range.

`InclusiveRange(T)` MUST be a value type with public `start` and `end` fields of type `T`. A valid
`InclusiveRange(T)` represents `[start, end]` and satisfies `start <= end`. `start == end`
represents a singleton range.

`[0, std.math.maxInt(T)]` MUST be invalid for `InclusiveRange(T)`. Its cardinality is not
representable in `T`. Every valid `InclusiveRange(T)` MUST contain at least one value and MUST
have a cardinality representable in `T`.

Copies MUST be independent values. No operation allocates, waits, performs atomics or barriers,
or accesses hidden globals.

## Global invariants

`Range(T)` MUST require `T` to be an unsigned integer type. `InclusiveRange(T)` MUST require `T`
to be a non-zero-width unsigned integer type. An invalid type argument is a compile error.

A method that requires a valid receiver or range argument MUST assert when that value violates
its type invariant. Fallible methods MUST leave their input values unchanged on error.

## API

```zig
pub fn Range(comptime T: type) type;
pub fn InclusiveRange(comptime T: type) type;
```

`Range(T)` returns:

```zig
pub const Self = struct {
    start: T,
    end: T,

    pub const InvalidRangeError = error{InvalidRange};
    pub const OverflowError = error{Overflow};
    pub const OutOfBoundsError = error{OutOfBounds};
    pub const Error = InvalidRangeError || OverflowError || OutOfBoundsError;

    pub fn fromBounds(start: T, end: T) InvalidRangeError!Self;
    pub fn of(comptime start: T, comptime end: T) Self;
    pub fn fromStartLen(start: T, length: T) OverflowError!Self;
    pub fn empty(at: T) Self;

    pub fn assertValid(self: Self) void;
    pub fn isValid(self: Self) bool;

    pub fn len(self: Self) T;
    pub fn isEmpty(self: Self) bool;

    pub fn contains(self: Self, value: T) bool;
    pub fn containsRange(self: Self, other: Self) bool;
    pub fn overlaps(self: Self, other: Self) bool;
    pub fn isAdjacent(self: Self, other: Self) bool;

    pub fn intersection(self: Self, other: Self) ?Self;
    pub fn span(self: Self, other: Self) Self;

    pub fn prefix(self: Self, point: T) OutOfBoundsError!Self;
    pub fn suffix(self: Self, point: T) OutOfBoundsError!Self;
    pub fn offsetOf(self: Self, value: T) ?T;
    pub fn atOffset(self: Self, offset: T) ?T;

    pub fn shiftForward(self: Self, amount: T) OverflowError!Self;
    pub fn shiftBackward(self: Self, amount: T) OverflowError!Self;
};
```

`InclusiveRange(T)` returns:

```zig
pub const Self = struct {
    start: T,
    end: T,

    pub const InvalidRangeError = error{InvalidRange};
    pub const OverflowError = error{Overflow};
    pub const OutOfBoundsError = error{OutOfBounds};
    pub const Error = InvalidRangeError || OverflowError || OutOfBoundsError;

    pub fn fromBounds(start: T, end: T) InvalidRangeError!Self;
    pub fn of(comptime start: T, comptime end: T) Self;
    pub fn fromStartLen(
        start: T,
        length: T,
    ) (InvalidRangeError || OverflowError)!Self;
    pub fn single(at: T) Self;

    pub fn fromRange(range: Range(T)) ?Self;
    pub fn toRange(self: Self) OverflowError!Range(T);

    pub fn assertValid(self: Self) void;
    pub fn isValid(self: Self) bool;

    pub fn len(self: Self) T;
    pub fn isSingleton(self: Self) bool;

    pub fn contains(self: Self, value: T) bool;
    pub fn containsRange(self: Self, other: Self) bool;
    pub fn overlaps(self: Self, other: Self) bool;
    pub fn isAdjacent(self: Self, other: Self) bool;

    pub fn intersection(self: Self, other: Self) ?Self;
    pub fn span(self: Self, other: Self) OverflowError!Self;

    pub fn prefix(self: Self, point: T) OutOfBoundsError!Self;
    pub fn suffix(self: Self, point: T) OutOfBoundsError!Self;
    pub fn offsetOf(self: Self, value: T) ?T;
    pub fn atOffset(self: Self, offset: T) ?T;

    pub fn shiftForward(self: Self, amount: T) OverflowError!Self;
    pub fn shiftBackward(self: Self, amount: T) OverflowError!Self;
};
```

## Construction and validation

### `Range`

`Range.fromBounds(start, end)` MUST return `[start, end)`. It MUST return `error.InvalidRange`
when `end < start`.

`Range.of(start, end)` MUST construct `[start, end)` from compile-time-known bounds. Invalid
bounds MUST cause a compile error.

`Range.fromStartLen(start, length)` MUST return `[start, start + length)`. It MUST return
`error.Overflow` when the addition is not representable in `T`.

`Range.empty(at)` MUST return `[at, at)`.

`Range.isValid()` MUST return `start <= end`. `Range.assertValid()` MUST assert the same
condition.

### `InclusiveRange`

`InclusiveRange.fromBounds(start, end)` MUST return `[start, end]`. It MUST return
`error.InvalidRange` when `end < start` or when the bounds equal
`[0, std.math.maxInt(T)]`.

`InclusiveRange.of(start, end)` MUST construct `[start, end]` from compile-time-known bounds.
Inverted bounds and `[0, std.math.maxInt(T)]` MUST cause a compile error.

`InclusiveRange.fromStartLen(start, length)` MUST return `[start, start + length - 1]`. It MUST
return `error.InvalidRange` when `length == 0`. It MUST return `error.Overflow` when the final
endpoint is not representable in `T`.

`InclusiveRange.single(at)` MUST return `[at, at]`.

`InclusiveRange.isValid()` MUST return:

```zig
self.start <= self.end and
    !(self.start == 0 and self.end == std.math.maxInt(T))
```

`InclusiveRange.assertValid()` MUST assert the same condition. `InclusiveRange(T)` MUST NOT
provide `empty`, `isEmpty`, or `initUnchecked`.

A caller with proven validity MAY use public field initialization for either type. Neither type
provides `initUnchecked`.

## Conversion

`InclusiveRange.fromRange(range)` MUST require a valid `Range(T)`. It MUST return `null` when
`range` is empty. For a non-empty `[start, end)`, it MUST return `[start, end - 1]`.

`InclusiveRange.toRange()` MUST return `[start, end + 1)`. It MUST return `error.Overflow` when
`end == std.math.maxInt(T)`.

Every successful conversion round trip MUST preserve the input bounds. This requirement applies
to every non-empty `Range(T)` and every `InclusiveRange(T)` whose `end` is less than
`std.math.maxInt(T)`.

## Queries and range arithmetic

### `Range`

`Range.len()` MUST return `end - start`. `Range.isEmpty()` MUST return `start == end`.

`Range.contains(value)` MUST return `true` exactly when `start <= value and value < end`.

`Range.containsRange(other)` MUST return `true` exactly when
`start <= other.start and other.end <= end`. A containing range `[a, b)` MUST contain the empty
ranges `[a, a)` and `[b, b)` when `a <= b`.

`Range.overlaps(other)` MUST return `true` only when the intersection is non-empty. Empty ranges
MUST NOT overlap.

`Range.isAdjacent(other)` MUST return `true` exactly when `self.end == other.start` or
`other.end == self.start`. Empty ranges MUST follow the same rule.

`Range.intersection(other)` MUST return the non-empty intersection. It MUST return `null` when
the intersection is empty.

`Range.span(other)` MUST return the smallest range that covers both inputs, including any gap.

`Range.prefix(point)` MUST accept `point` in `[start, end]` and return `[start, point)`.
`Range.suffix(point)` MUST accept the same interval and return `[point, end)`. Each operation
MUST return `error.OutOfBounds` for another point. `point == start` MUST produce an empty prefix.
`point == end` MUST produce an empty suffix.

`Range.offsetOf(value)` MUST return `value - start` when `contains(value)` is true. It MUST
otherwise return `null`.

`Range.atOffset(offset)` MUST return `start + offset` when `offset < len()`. It MUST otherwise
return `null`. For every contained value, `atOffset(offsetOf(value).?)` MUST return `value`.

`Range.shiftForward(amount)` MUST add `amount` to both bounds. It MUST return `error.Overflow`
when either result is not representable in `T`.

`Range.shiftBackward(amount)` MUST subtract `amount` from both bounds. It MUST return
`error.Overflow` when `amount > start`.

### `InclusiveRange`

`InclusiveRange.len()` MUST return `end - start + 1`. The operation MUST be infallible.
`InclusiveRange.isSingleton()` MUST return `start == end`.

`InclusiveRange.contains(value)` MUST return `true` exactly when
`start <= value and value <= end`.

`InclusiveRange.containsRange(other)` MUST return `true` exactly when
`start <= other.start and other.end <= end`.

`InclusiveRange.overlaps(other)` MUST return `true` exactly when
`@max(start, other.start) <= @min(end, other.end)`. Inclusive ranges that share one endpoint
MUST overlap.

`InclusiveRange.isAdjacent(other)` MUST return `true` exactly when one of these conditions is
true:

```zig
self.end < other.start and other.start - self.end == 1
other.end < self.start and self.start - other.end == 1
```

`InclusiveRange.intersection(other)` MUST return
`[@max(start, other.start), @min(end, other.end)]` when those bounds are ordered. It MUST return
`null` when the ranges are disjoint. Equal intersection bounds MUST produce a singleton.

`InclusiveRange.span(other)` MUST return the smallest inclusive range that covers both inputs,
including any gap. It MUST return `error.Overflow` exactly when the resulting bounds are
`[0, std.math.maxInt(T)]`.

`InclusiveRange.prefix(point)` MUST accept a contained point and return `[start, point]`.
`InclusiveRange.suffix(point)` MUST accept a contained point and return `[point, end]`. Each
operation MUST return `error.OutOfBounds` for a point outside `[start, end]`. Both results MUST
contain `point`, and their intersection MUST be `[point, point]`.

`InclusiveRange.offsetOf(value)` MUST return `value - start` when `contains(value)` is true. It
MUST otherwise return `null`.

`InclusiveRange.atOffset(offset)` MUST return `start + offset` when `offset <= end - start`. It
MUST otherwise return `null`. For every contained value, `atOffset(offsetOf(value).?)` MUST
return `value`.

`InclusiveRange.shiftForward(amount)` MUST add `amount` to both bounds. It MUST return
`error.Overflow` when either result is not representable in `T`.

`InclusiveRange.shiftBackward(amount)` MUST subtract `amount` from both bounds. It MUST return
`error.Overflow` when `amount > start`.

## Errors and fault behavior

`Range.fromBounds` MUST return `error.InvalidRange` for inverted bounds. `Range.fromStartLen`,
`Range.shiftForward`, and `Range.shiftBackward` MUST return `error.Overflow` for unrepresentable
arithmetic. `Range.prefix` and `Range.suffix` MUST return `error.OutOfBounds` for a point outside
`[start, end]`.

`InclusiveRange.fromBounds` MUST return `error.InvalidRange` for inverted bounds and the excluded
full-domain bounds. `InclusiveRange.fromStartLen` MUST return `error.InvalidRange` for zero length
and `error.Overflow` for an unrepresentable endpoint. `InclusiveRange.span`,
`InclusiveRange.toRange`, `InclusiveRange.shiftForward`, and `InclusiveRange.shiftBackward` MUST
return `error.Overflow` under their specified overflow conditions. `InclusiveRange.prefix` and
`InclusiveRange.suffix` MUST return `error.OutOfBounds` for a point outside `[start, end]`.

An invalid type argument MUST cause a compile error. An operation that requires a valid range
value MUST assert when the value is invalid.

## Implementation constraints

Every public operation MUST be $O(1)$, allocation-free, and non-blocking. `Range(T)` and
`InclusiveRange(T)` MUST create no handles, borrowed storage, or invalidatable references.

Operations MUST NOT invoke callbacks, perform I/O, read clocks, access hidden globals, call
scheduler or backend APIs, or establish synchronization or memory-ordering effects.

Implementations MUST use checked or proven-safe endpoint arithmetic. They MUST NOT use wrapping
or saturating arithmetic to satisfy a range operation.

## Testing

Tests MUST exercise `Range(usize)`, `InclusiveRange(usize)`, and at least one small unsigned
instantiation of each type, such as `u8`.

`Range` constructor tests MUST verify valid and empty bounds, rejection of `end < start`,
compile-time `of` validation, and `fromStartLen` overflow. `Range` query and arithmetic tests
MUST verify empty and non-empty lengths; inclusion of `start` and exclusion of `end`; empty
subranges at both containing boundaries; adjacent and empty non-overlap; adjacency; intersection
and disjoint `null`; disjoint span; prefix and suffix at start, middle, and end; outside-point
`error.OutOfBounds`; `offsetOf`/`atOffset` round trips; `atOffset(len()) == null`; forward
overflow; and backward underflow.

`InclusiveRange` constructor tests MUST verify valid bounds, singleton bounds,
`single`, rejection of `end < start`, rejection of `[0, std.math.maxInt(T)]`, compile-time `of`
validation, zero-length rejection, and `fromStartLen` overflow.

`InclusiveRange` cardinality tests MUST verify singleton length, ordinary length, and the maximum
valid length. They MUST verify that `[0, maxInt(T) - 1]` and `[1, maxInt(T)]` each have length
`maxInt(T)`.

`InclusiveRange` relationship tests MUST verify inclusion of both endpoints; containment;
disjoint ranges; overlap at one shared endpoint; adjacency in both orders and near numeric
boundaries; singleton intersection; disjoint `null`; successful disjoint span; and
`error.Overflow` when valid inputs span `[0, std.math.maxInt(T)]`.

`InclusiveRange` prefix and suffix tests MUST exercise the start, middle, and end points,
singleton outer results, the shared split point, and `error.OutOfBounds` below and above the
range. Offset tests MUST verify `offsetOf`/`atOffset` round trips, inclusion of the final offset,
and rejection of the first offset after the end. Shift tests MUST verify forward overflow and
backward underflow.

Conversion tests MUST verify non-empty `Range` conversion, empty `Range` conversion to `null`,
successful round trips, singleton conversion, and `InclusiveRange.toRange` overflow when
`end == std.math.maxInt(T)`.

Compile-fail tests MUST reject signed integer instantiations of both types and
`InclusiveRange(u0)`.

## Usage examples

A caller that requires the complete value domain of an unsigned integer type MUST use an
`InclusiveRange` backing type that can represent the domain cardinality. `InclusiveRange(u32)`
can represent all `u16` values:

```zig
const U16Domain = stdx.core.InclusiveRange(u32);
const all_u16 = U16Domain.of(0, 65_535);

comptime {
    std.debug.assert(all_u16.len() == 65_536);
}
```
