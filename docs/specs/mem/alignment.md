# Memory alignment

Status: Approved.

`stdx.mem` owns small unsigned-integer alignment helpers used by allocators,
fixed storage, byte layout, address lowering, and bounded data structures.

## Owned scope

This spec owns:

- `mem.alignUp`;
- `mem.alignDown`;
- `mem.isAligned`;
- `mem.alignUpDelta`;
- `mem.alignDownDelta`;
- unsigned integer type restrictions;
- valid alignment requirements;
- overflow behavior;
- required tests.

This spec does not own:

- pointer alignment wrappers;
- allocator alignment policy;
- page-specific APIs;
- address-specific APIs;
- saturating, wrapping, or unchecked alignment variants;
- non-power-of-two alignment;
- signed integer support.

## Public namespace

Alignment helpers live under `stdx.mem`:

```zig
stdx.mem.alignUp
stdx.mem.alignDown
stdx.mem.isAligned
stdx.mem.alignUpDelta
stdx.mem.alignDownDelta
```

They are not root-promoted:

```zig
stdx.alignUp // not exported
```

Source ownership:

```text
src/mem.zig
src/mem/alignment.zig
```

`src/mem.zig` re-exports:

```zig
pub const alignment = @import("mem/alignment.zig");

pub const alignUp = alignment.alignUp;
pub const alignDown = alignment.alignDown;
pub const isAligned = alignment.isAligned;
pub const alignUpDelta = alignment.alignUpDelta;
pub const alignDownDelta = alignment.alignDownDelta;
```

## Approved API

```zig
pub const AlignError = error{InvalidAlignment};
pub const OverflowError = error{Overflow};
pub const Error = AlignError || OverflowError;

pub fn alignUp(comptime T: type, value: T, alignment: T) Error!T;
pub fn alignDown(comptime T: type, value: T, alignment: T) AlignError!T;
pub fn isAligned(comptime T: type, value: T, alignment: T) bool;
pub fn alignUpDelta(comptime T: type, value: T, alignment: T) Error!T;
pub fn alignDownDelta(comptime T: type, value: T, alignment: T) AlignError!T;
```

`T` must be an unsigned integer type. Signed integers, floats, bools, enums,
pointers, and comptime integers without an explicit `T` are compile errors.

Usage:

```zig
const start = try stdx.mem.alignUp(usize, cursor, @alignOf(Header));
const base = try stdx.mem.alignDown(u64, address, 4096);
if (stdx.mem.isAligned(usize, offset, 8)) {
    // `offset` is 8-byte aligned.
}
```

## Alignment validity

`alignment` is valid when it is a non-zero power of two:

```zig
alignment != 0 and stdx.bits.isPowerOfTwo(T, alignment)
```

`alignUp` and `alignDown` return `error.InvalidAlignment` when `alignment` is zero or not a power of two. `isAligned` asserts the same precondition because it returns a plain `bool` (no error union); `alignment` is overwhelmingly a comptime constant in practice.

`alignment == 1` is valid. It is a no-op for all operations.

## `isAligned` semantics

`isAligned(T, value, alignment)` returns true iff `value` is already a multiple of `alignment`.

Precondition: `alignment` must be a non-zero power of two. Implementations assert this via `std.debug.assert` rather than returning an error union; the predicate convention is documented in `docs/guidelines/conventions.md`.

For valid alignment:

```zig
isAligned(T, value, alignment) == (value & (alignment - 1) == 0)
```

## `alignDown` semantics

`alignDown(T, value, alignment)` returns the greatest aligned value less than or equal to `value`.

For valid alignment:

```zig
try alignDown(T, value, alignment) == (value & ~(alignment - 1))
```

`alignDown` cannot overflow after alignment validity has been checked.

## `alignUp` semantics

`alignUp(T, value, alignment)` returns the smallest aligned value greater than or equal to `value`.

Required behavior:

```zig
try alignUp(T, 0, alignment) == 0
try alignUp(T, value, 1) == value
try alignUp(T, aligned_value, alignment) == aligned_value
```

`alignUp` returns `error.Overflow` when rounding up would exceed `std.math.maxInt(T)`.

For valid alignment, an acceptable rule is:

```zig
const addend = alignment - 1;
const rounded = try std.math.add(T, value, addend);
return rounded & ~addend;
```

## `alignUpDelta` and `alignDownDelta` semantics

`alignUpDelta(T, value, alignment)` returns `alignUp(T, value, alignment) - value`. Inherits `alignUp`'s overflow behavior; returns `error.Overflow` under the same condition.

`alignDownDelta(T, value, alignment)` returns `value - alignDown(T, value, alignment)`. Equivalent to `value & (alignment - 1)` for valid alignment. Never overflows.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `alignUp` | never | never | O(1) | none | pure function | none |
| `alignDown` | never | never | O(1) | none | pure function | none |
| `isAligned` | never | never | O(1) | none | pure function | none |
| `alignUpDelta` | never | never | O(1) | none | pure function | none |
| `alignDownDelta` | never | never | O(1) | none | pure function | none |

These helpers perform no allocation, waiting, hidden global access, atomics, or barriers.

## Error behavior

- invalid alignment returns `error.InvalidAlignment`;
- `alignUp` returns `error.Overflow` when rounding up overflows;
- invalid `T` is a compile error.

`alignDown` does not return `error.Overflow`. `isAligned` has no error set; it asserts on invalid alignment.

## Implementation constraints

Implementation must:

- reuse or exactly match `stdx.bits.isPowerOfTwo` semantics for alignment validation;
- avoid unchecked overflow;
- avoid loops;
- compile for all unsigned integer widths Zig supports;
- produce a compile error for invalid `T`.

## Required tests

Required for `usize`, `u8`, and at least one non-native width such as `u17`.

### Alignment validity

- alignment `0` returns `error.InvalidAlignment`;
- non-power-of-two alignment returns `error.InvalidAlignment`;
- alignment `1` is accepted.

### `isAligned`

- `0` is aligned for every valid alignment;
- aligned values return true;
- unaligned values return false;
- max value behavior is covered for the type.

### `alignDown`

- aligned values return themselves;
- unaligned values round down;
- values smaller than alignment round down to `0`;
- max value behavior is covered for the type.

### `alignUp`

- `0` returns `0`;
- aligned values return themselves;
- unaligned values round up;
- values smaller than alignment round up to alignment;
- highest safe aligned value succeeds;
- values whose rounded result exceeds `std.math.maxInt(T)` return `error.Overflow`, for example `alignUp(u8, 255, 2)`.

### Compile-time and type tests

Where practical:

- signed integer instantiation fails;
- bool and floats are rejected;
- comptime evaluation works:

```zig
comptime {
    std.debug.assert((try stdx.mem.alignUp(u8, 7, 4)) == 8);
    std.debug.assert((try stdx.mem.alignDown(u8, 7, 4)) == 4);
    std.debug.assert(stdx.mem.isAligned(u8, 8, 4));
}
```

## Open questions

None.
