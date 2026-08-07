# Static bit set

Status: Approved.

`stdx.bits.BitSet.Static(N)` is a fixed-capacity set of integer indexes in `0..N`.

## What this spec is

This spec defines `stdx.bits.BitSet.Static(N)`, its inline storage, single-index operations, same-capacity set algebra, lowest-set-bit operations, the unused-bit invariant, and required tests.

## What this spec is not

This spec does not define named ABI flag words, enum-backed flag sets, dynamic bitmaps, bitmap allocators, atomic bit sets, bit-scan wrappers, sparse sets, or slot maps.

## Public namespace and source ownership

```zig
stdx.bits.BitSet
```

`src/bits.zig` re-exports `BitSet` from `src/bits/set.zig`. The tests are in `test/bits/set_test.zig`.

## Data structures and representation

`Static(capacity_bits)` returns a distinct type with inline `[word_count]Word` storage. `Word` is `u64`; `word_bits` is `@bitSizeOf(Word)`; `bit_capacity` is `capacity_bits`; and `word_count` is `word.count(Word, capacity_bits)`. Storage layout is not a stable wire or ABI layout.

## Global invariants

`capacity_bits` is a comptime bit count. `Static(0)` is a compile error. Valid indexes satisfy `0 <= index < bit_capacity`.

For a capacity that is not a multiple of `word_bits`, unused high bits in the final word MUST be zero after every public operation. `assertValid` asserts this invariant.

The type does not allocate, wait, access hidden globals, perform atomics or barriers, or establish ordering. Callers MUST externally synchronize concurrent mutable access. No operation invalidates the set or its inline storage.

## API

```zig
pub const BitSet = struct {
    pub fn Static(comptime capacity_bits: usize) type;
};
```

`Static` returns a type with this public surface:

```zig
pub const Error = error{OutOfBounds};
pub const Word = u64;
pub const word_bits = @bitSizeOf(Word);
pub const bit_capacity = capacity_bits;
pub const word_count = word.count(Word, capacity_bits);

pub fn init() Self;
pub fn full() Self;
pub fn clearRetainingCapacity(self: *Self) void;
pub fn setAll(self: *Self) void;
pub fn isEmpty(self: *const Self) bool;
pub fn isFull(self: *const Self) bool;
pub fn count(self: *const Self) usize;
pub fn isSet(self: *const Self, index: usize) bool;
pub fn set(self: *Self, index: usize) Error!bool;
pub fn unset(self: *Self, index: usize) Error!bool;
pub fn assign(self: *Self, index: usize, value: bool) Error!bool;
pub fn toggle(self: *Self, index: usize) Error!bool;
pub fn firstSet(self: *const Self) ?usize;
pub fn popFirstSet(self: *Self) ?usize;
pub fn eql(self: *const Self, other: *const Self) bool;
pub fn containsAll(self: *const Self, other: *const Self) bool;
pub fn containsAny(self: *const Self, other: *const Self) bool;
pub fn unionWith(self: *Self, other: *const Self) void;
pub fn intersectWith(self: *Self, other: *const Self) void;
pub fn differenceWith(self: *Self, other: *const Self) void;
pub fn assertValid(self: *const Self) void;
```

### Construction and whole-set operations

`init()` and a default struct literal return an empty set. `full()` and `setAll()` set every valid bit and clear every unused high bit. `clearRetainingCapacity()` clears every valid bit and does not change `bit_capacity`.

`isEmpty()` returns `true` when no valid bit is set. `isFull()` returns `true` when every valid bit is set. `count()` returns the number of valid set bits.

### Single-index operations

`isSet(index)` returns whether `index` is set. It returns `false` for `index >= bit_capacity`.

`set(index)`, `unset(index)`, `assign(index, value)`, and `toggle(index)` return `error.OutOfBounds` for `index >= bit_capacity` and leave the set unchanged on that error. `set`, `unset`, and `assign` return the prior bit value. `toggle` returns the new bit value.

### Lowest-set-bit operations

`firstSet()` returns the lowest set index, or `null` when the set is empty. `popFirstSet()` returns and clears the lowest set index, or returns `null` when the set is empty. Both operations have $O(word_count)$ time complexity.

### Set algebra

Set algebra accepts only values of the same `Self` type; bit sets with different capacities are distinct types.

`eql(other)` returns whether both sets contain the same valid bits. `containsAll(other)` returns whether every bit set in `other` is set in `self`. `containsAny(other)` returns whether any bit set in `other` is set in `self`.

`unionWith(other)` sets `self` to `self ∪ other`. `intersectWith(other)` sets `self` to `self ∩ other`. `differenceWith(other)` sets `self` to `self - other`. Each operation preserves the unused-bit invariant.

## Implementation constraints

The implementation MUST use `u64` words, reject `Static(0)` at comptime, compute `word_count` without integer overflow, and clear unused high bits after every public mutation. It MUST use `@popCount` for `count` and `@ctz` for lowest-set-bit scans, or provide exactly matching behavior. It MUST not expose a public wrapper for Zig bit-scan builtins.

## Testing

Tests MUST evaluate `Static(1)`, `Static(64)`, `Static(65)`, and a non-word-multiple capacity such as `Static(129)`.

Construction and whole-set tests MUST verify empty initialization, full initialization, capacity retention, and empty, partial, and full predicates.

Single-index tests MUST verify first, middle, and last valid indexes; every prior-value transition for `set`, `unset`, and `assign`; both toggle directions; and the `index == bit_capacity` error boundary.

Scan tests MUST verify empty results, ascending `popFirstSet` order, and removal of each returned bit.

Algebra tests MUST verify equality, containment, union, intersection, and difference for sets whose relations produce both true and false predicates.

Invariant tests MUST verify that public mutations preserve clear unused bits, including on non-word-multiple capacities. This proves that padding cannot become observable set membership. A corruption test MAY manually set an unused bit and verify the debug assertion when the test harness supports assertion capture.
