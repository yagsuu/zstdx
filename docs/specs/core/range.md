# Core range

Status: Approved.

`zstdx.core.Range(T)` is a small half-open range value for unsigned integer domains. It is used for indices, byte offsets, bitmap spans, allocator extents, and other count-like intervals. Address-specific ranges are owned by address/page specs.

## Owned scope

This spec owns:

- `Range(T)` type factory;
- half-open range semantics;
- constructor and query APIs;
- split, offset, and shift APIs;
- behavior contract and required tests.

This spec does not own:

- address ranges;
- page ranges;
- pointer spans;
- non-null pointer wrappers;
- range sets or range maps.

## Public namespace

`Range` lives under `zstdx.core`:

```zig
zstdx.core.Range
```

It is not root-promoted:

```zig
zstdx.Range // not exported
```

Source ownership:

```text
src/core.zig
src/core/range.zig
```

`src/core.zig` re-exports:

```zig
pub const Range = @import("core/range.zig").Range;
```

## Approved API

```zig
pub fn Range(comptime T: type) type;
```

`T` must be an unsigned integer type. Other types are a compile error.

Returned type:

```zig
pub const Self = struct {
    start: T,
    end: T,

    pub const Error = error{
        InvalidRange,
        Overflow,
        OutOfBounds,
    };


    pub fn fromBounds(start: T, end: T) Error!Self;
    pub fn fromStartLen(start: T, len: T) Error!Self;
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

    pub fn prefix(self: Self, point: T) Error!Self;
    pub fn suffix(self: Self, point: T) Error!Self;
    pub fn offsetOf(self: Self, value: T) ?T;
    pub fn atOffset(self: Self, offset: T) ?T;

    pub fn shiftForward(self: Self, amount: T) Error!Self;
    pub fn shiftBackward(self: Self, amount: T) Error!Self;
};
```

## Semantics

Ranges are half-open:

```text
[start, end)
```

Valid invariant:

```zig
start <= end
```

Empty range:

```zig
start == end
```

## Constructors

`fromBounds(start, end)` returns `error.InvalidRange` when `end < start`.

`fromStartLen(start, len)` constructs `[start, start + len)`. It returns `error.Overflow` when `start + len` overflows `T`.

`empty(at)` returns `[at, at)`.

Callers with proven validity may construct via struct literal: `Range(T){ .start = a, .end = b }`. There is no `initUnchecked` variant.

## Validation

`isValid()` returns `start <= end`.

`assertValid()` asserts `start <= end`. It is for programmer errors and internal invariant checks, not external input validation.

## Queries

`len()` returns `end - start`. Calling `len()` on an invalid range is a programmer error.

`isEmpty()` returns `start == end`.

`contains(value)` returns true when:

```zig
start <= value and value < end
```

`containsRange(other)` returns true when:

```zig
start <= other.start and other.end <= end
```

Empty ranges are contained if their point is inside the containing range or on either boundary. Therefore `[a, b)` contains `[a, a)` and `[b, b)` when `a <= b`.

`overlaps(other)` returns true only for a non-empty intersection. Empty ranges never overlap.

`isAdjacent(other)` returns true when:

```zig
self.end == other.start or other.end == self.start
```

Empty ranges may be adjacent by the same boundary rule.

## Intersection and span

`intersection(other)` returns the non-empty intersection. It returns `null` when the intersection is empty.

`span(other)` returns the smallest range covering both ranges, including any gap between them.

`span` never overflows because its result uses existing bounds.

## Prefix, suffix, and offset

`prefix(point)` accepts `point` in `[start, end]` and returns `[start, point)`. A point outside `[start, end]` returns `error.OutOfBounds`.

`suffix(point)` accepts `point` in `[start, end]` and returns `[point, end)`. A point outside `[start, end]` returns `error.OutOfBounds`.

`point == start` produces an empty prefix; `point == end` produces an empty suffix.

`offsetOf(value)` returns `value - start` when `value` is contained, else `null`.

`atOffset(offset)` returns `start + offset` when `offset < len()`, else `null`. Round trip with `offsetOf` preserves containment.

## Shift

`shiftForward(amount)` adds `amount` to both bounds. It returns `error.Overflow` if either addition overflows.

`shiftBackward(amount)` subtracts `amount` from both bounds. It returns `error.Overflow` if either subtraction underflows. Underflow is reported as `error.Overflow` because the saturating value would not be representable in `T`.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| all operations | never | never | O(1) | none | value type | none |

`Range(T)` performs no allocation, waits, atomics, barriers, or hidden global access.

## Error behavior

- malformed constructor input returns `error.InvalidRange`;
- arithmetic overflow or underflow returns `error.Overflow`;
- split/offset requests outside the range return `error.OutOfBounds`;
- invalid `T` is a compile error;
- methods that require a valid receiver may assert on invalid `self`.

## Non-goals

`Range(T)` does not provide:

- iteration;
- slicing helpers;
- coalescing;
- range-set storage;
- address arithmetic;
- page alignment;
- pointer/length span semantics;
- signed range semantics.

## Required tests

Required for `Range(usize)` and at least one small unsigned integer type such as `Range(u8)`:

- `fromBounds` accepts valid and empty ranges;
- `fromBounds` rejects `end < start`;
- `fromStartLen` catches overflow;
- `empty` creates `[at, at)`;
- `isValid` and `assertValid` cover valid ranges;
- `len` covers empty and non-empty ranges;
- `contains` includes start and excludes end;
- `containsRange` handles empty subranges at start and end;
- `overlaps` rejects adjacent ranges and empty intersections;
- `isAdjacent` detects boundary contact;
- `intersection` returns expected ranges and `null` for no overlap;
- `span` covers disjoint ranges;
- `prefix` and `suffix` handle start, middle, and end;
- `prefix` and `suffix` reject outside points with `error.OutOfBounds`;
- `offsetOf` and `atOffset` round trip;
- `atOffset(len())` returns `null`;
- `shiftForward` catches overflow;
- `shiftBackward` catches underflow;
- signed integer instantiation fails at compile time where practical.

## Open questions

None.
