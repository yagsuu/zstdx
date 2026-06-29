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
        OutOfRange,
    };

    pub const Split = struct {
        left: Self,
        right: Self,
    };

    pub fn init(start: T, end: T) Error!Self;
    pub fn initUnchecked(start: T, end: T) Self;
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

    pub fn splitAt(self: Self, point: T) Error!Split;
    pub fn offsetOf(self: Self, value: T) ?T;
    pub fn atOffset(self: Self, offset: T) Error!T;

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

`init(start, end)` returns `error.InvalidRange` when `end < start`.

`initUnchecked(start, end)` does not validate. Caller must uphold `start <= end`. Use only when the invariant has already been proven.

`fromStartLen(start, len)` constructs `[start, start + len)`. It returns `error.Overflow` when `start + len` overflows `T`.

`empty(at)` returns `[at, at)`.

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

## Split and offset

`splitAt(point)` accepts `point` in `[start, end]`.

- `point == start` returns an empty left range.
- `point == end` returns an empty right range.
- a point outside `[start, end]` returns `error.OutOfRange`.

`offsetOf(value)` returns `value - start` if `value` is contained, else `null`.

`atOffset(offset)` returns `start + offset` when `offset < len()`. It returns `error.OutOfRange` otherwise. Overflow is impossible for valid ranges when `offset < len()`.

## Shift

`shiftForward(amount)` adds `amount` to both bounds. It returns `error.Overflow` if either addition overflows.

`shiftBackward(amount)` subtracts `amount` from both bounds. It returns `error.Overflow` if either subtraction underflows.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| all operations | never | never | O(1) | none | value type; caller-owned | none |

`Range(T)` performs no allocation, waits, atomics, barriers, or hidden global access.

## Error behavior

- malformed constructor input returns `error.InvalidRange`;
- arithmetic overflow or underflow returns `error.Overflow`;
- split/offset requests outside the range return `error.OutOfRange`;
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

- `init` accepts valid and empty ranges;
- `init` rejects `end < start`;
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
- `splitAt` handles start, middle, and end;
- `splitAt` rejects outside points;
- `offsetOf` and `atOffset` round trip;
- `atOffset` rejects `offset == len()`;
- `shiftForward` catches overflow;
- `shiftBackward` catches underflow;
- signed integer instantiation fails at compile time where practical.
