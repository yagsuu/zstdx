# Core range

Status: Approved.

`stdx.core.Range(T)` is a half-open range value for unsigned integer domains. It represents indices, byte offsets, bitmap spans, allocator extents, and other count-like intervals.

## What this spec is

This specification defines `Range(T)`, its half-open interval semantics, construction, queries, range arithmetic, failure behavior, and tests.

## What this spec is not

This specification does not define address ranges, page ranges, pointer spans, non-null pointer wrappers, range sets, range maps, iteration, slicing helpers, coalescing, address arithmetic, page alignment, or signed-range semantics.

## Public namespace and source ownership

`Range` is available as `stdx.core.Range`. It is not available as `stdx.Range`.

Source ownership:

```text
src/core.zig
src/core/range.zig
```

`src/core.zig` re-exports `Range` from `core/range.zig`.

## Data structures and representation

`Range(T)` is a value type with public `start` and `end` fields of type `T`. A valid range represents `[start, end)` and satisfies `start <= end`. An empty range satisfies `start == end`.

Copies are independent values. No operation allocates, waits, performs atomics or barriers, or accesses hidden globals.

## Global invariants

`T` MUST be an unsigned integer type. `Range(T)` with another type is a compile error.

A method that requires a valid receiver asserts when `start > end`. Fallible methods leave the input values unchanged on error.

## API

```zig
pub fn Range(comptime T: type) type;
```

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

## Construction and validation

`fromBounds(start, end)` returns `[start, end)` or `error.InvalidRange` when `end < start`.

`of(start, end)` constructs `[start, end)` from compile-time-known bounds. It is a compile error when `end < start`.

`fromStartLen(start, length)` returns `[start, start + length)` or `error.Overflow` when the addition overflows `T`.

`empty(at)` returns `[at, at)`.

A caller with proven validity MAY use `Range(T){ .start = a, .end = b }`. `Range(T)` does not provide `initUnchecked`.

`isValid()` returns `start <= end`. `assertValid()` asserts `start <= end`; it detects programmer errors and internal invariant violations, not invalid external input.

## Queries and range arithmetic

`len()` returns `end - start`. `isEmpty()` returns `start == end`.

`contains(value)` returns `true` exactly when `start <= value and value < end`.

`containsRange(other)` returns `true` exactly when `start <= other.start and other.end <= end`. A containing range `[a, b)` contains the empty ranges `[a, a)` and `[b, b)` when `a <= b`.

`overlaps(other)` returns `true` only when the intersection is non-empty. Empty ranges never overlap.

`isAdjacent(other)` returns `true` exactly when `self.end == other.start` or `other.end == self.start`. Empty ranges can be adjacent under the same rule.

`intersection(other)` returns the non-empty intersection or `null` when the intersection is empty.

`span(other)` returns the smallest range that covers both ranges, including a gap. It does not overflow because its bounds are existing input bounds.

`prefix(point)` accepts `point` in the closed interval `[start, end]` and returns `[start, point)`. `suffix(point)` accepts the same interval and returns `[point, end)`. Each returns `error.OutOfBounds` for another point. `point == start` returns an empty prefix. `point == end` returns an empty suffix.

`offsetOf(value)` returns `value - start` when `contains(value)` is true and otherwise returns `null`.

`atOffset(offset)` returns `start + offset` when `offset < len()` and otherwise returns `null`. For every contained value, `atOffset(offsetOf(value).?)` returns `value`.

`shiftForward(amount)` adds `amount` to both bounds and returns `error.Overflow` when either addition overflows `T`.

`shiftBackward(amount)` subtracts `amount` from both bounds and returns `error.Overflow` when `amount > start`. This condition also prevents underflow of `end` because valid ranges satisfy `start <= end`.

## Errors and fault behavior

`fromBounds` returns `error.InvalidRange` for invalid bounds. `fromStartLen`, `shiftForward`, and `shiftBackward` return `error.Overflow` for unrepresentable arithmetic. `prefix` and `suffix` return `error.OutOfBounds` for a point outside `[start, end]`. An invalid type argument is a compile error. A method that requires a valid receiver asserts on an invalid receiver.

## Implementation constraints

Every public operation is $O(1)$. Every public operation is allocation-free and non-blocking. `Range(T)` is a value type; it creates no handles, borrowed storage, or invalidatable references.

## Testing

Tests MUST exercise `Range(usize)` and at least one small unsigned instantiation such as `Range(u8)`. Constructor tests MUST verify valid and empty bounds, rejection of `end < start`, compile-time `of` validation, and `fromStartLen` overflow. These tests prove construction and numeric-boundary behavior.

Query and arithmetic tests MUST verify empty and non-empty lengths; inclusion of `start` and exclusion of `end`; empty subranges at both containing boundaries; adjacent and empty non-overlap; adjacency; intersection and disjoint `null`; disjoint span; prefix and suffix at start, middle, and end; outside-point `error.OutOfBounds`; `offsetOf`/`atOffset` round trips; `atOffset(len()) == null`; forward overflow; and backward underflow. These tests prove half-open semantics and preserve all range-arithmetic boundaries.

Compile-fail testing MUST instantiate `Range` with a signed integer type and verify that compilation fails. This proves the unsigned-domain restriction without relying on a runtime test.
