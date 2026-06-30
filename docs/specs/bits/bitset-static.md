# Bits static bit set

Status: Approved.

`stdx.bits.BitSet.Static(N)` is a fixed-capacity set of integer indexes in
`0..N`. It is used for slot occupancy, free-index tracking, resource masks, and
small bounded integer domains.

## Owned scope

This spec owns:

- `bits.BitSet.Static(N)`;
- fixed-capacity bitset storage;
- single-index mutation and query operations;
- same-capacity set algebra;
- lowest-set-bit scan and pop operations;
- unused-bit invariants;
- required tests.

This spec does not own:

- named ABI flag words;
- enum-backed flag sets;
- dynamic bitmaps;
- bitmap allocators;
- atomic bit sets;
- bit-scan wrappers around Zig builtins;
- sparse sets or slot maps.

## Public namespace

`BitSet` lives under `stdx.bits`:

```zig
stdx.bits.BitSet
```

It is not root-promoted:

```zig
stdx.BitSet // not exported
```

Source ownership:

```text
src/bits.zig
src/bits/set.zig
test/bits/set_test.zig
```

`src/bits.zig` re-exports:

```zig
pub const BitSet = @import("bits/set.zig").BitSet;
```

## Approved API

```zig
pub const BitSet = struct {
    pub fn Static(comptime capacity_bits: usize) type;
};
```

Returned type:

```zig
pub const Self = struct {
    words: [word_count]Word = [_]Word{0} ** word_count,

    pub const Error = error{OutOfBounds};
    pub const Word = u64;
    pub const word_bits = @bitSizeOf(Word);
    pub const bit_capacity = capacity_bits;
    pub const word_count = capacity_bits / word_bits +
        @intFromBool(capacity_bits % word_bits != 0);

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
};
```

`word_count` must be computed without overflowing `usize`.

`words` is storage, not a stable wire or ABI layout. Direct mutation must preserve
the unused-bit invariant.

## Capacity

`bit_capacity` is a comptime bit count. `Static(0)` is rejected at compile time with `@compileError`; bit sets over an empty universe carry no useful behavior and every mutator path would be statically unreachable.

Valid indexes are:

```text
0 <= index < bit_capacity
```

Mutators (`set`, `unset`, `assign`, `toggle`) return `error.OutOfBounds` when `index >= bit_capacity`. `isSet` returns `false` for out-of-range indexes; predicate queries do not error.

## Unused-bit invariant

When `bit_capacity` is not a multiple of `word_bits`, the final word has unused high
bits. Those bits must always be zero after every public operation.

`assertValid()` asserts that every unused high bit is zero.

## Constructors

`init()` returns an empty set.

A default struct literal is also an empty set:

```zig
var set: stdx.bits.BitSet.Static(64) = .{};
```

`full()` returns a set with every valid bit set and every unused high bit clear.

## Whole-set operations

`clearRetainingCapacity()` clears every valid bit. The slot count `bit_capacity` is unchanged.

`setAll()` sets every valid bit and clears every unused high bit.

`isEmpty()` returns true when no valid bits are set.

`isFull()` returns true when every valid bit is set.

`count()` returns the population (number of valid set bits). It ignores unused high bits;
valid receivers have no unused high bits set.

## Single-index operations

`isSet(index)` returns whether `index` is set. Returns `false` for `index >= bit_capacity`.

`set(index)` sets `index` and returns the prior bit value. The return is `true`
when the bit was already set.

`unset(index)` clears `index` and returns the prior bit value. The return is
`true` when the bit was previously set.

`assign(index, value)` writes `value` and returns the prior bit value. Callers
that want a "did this change anything?" signal compute
`(try bs.assign(i, v)) != v`.

`toggle(index)` flips `index` and returns the **new** bit value. The asymmetry
with `set`/`unset`/`assign` is deliberate: a toggle always changes state, so
the prior value is just `!new` and would carry no extra information.

Callers that do not need the return value write `_ = try bs.set(i);` (or the
equivalent for the other mutators).

## Lowest-set-bit operations

`firstSet()` returns the lowest set index, or `null` when the set is empty.

`popFirstSet()` returns and clears the lowest set index, or returns `null` when
the set is empty.

Implementations should use Zig builtins such as `@ctz` and must define zero-word
handling at the bitset level.

## Set algebra

Set algebra operates on values of the same `Self` type. Different capacities are
different types and cannot be mixed accidentally.

`eql(other)` returns true when both sets contain the same valid bits.

`containsAll(other)` returns true when every bit set in `other` is also set in
`self`.

`containsAny(other)` returns true when any bit set in `other` is also set in
`self`.

`unionWith(other)` sets `self` to `self ∪ other`.

`intersectWith(other)` sets `self` to `self ∩ other`.

`differenceWith(other)` sets `self` to `self - other`.

All set algebra operations must preserve the unused-bit invariant.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| single-index operations | never | never | O(1) | none | caller-owned value | none |
| `firstSet`, `popFirstSet` | never | never | O(word_count) | none | caller-owned value | none |
| whole-set operations | never | never | O(word_count) | none | caller-owned value | none |
| set algebra | never | never | O(word_count) | none | caller-owned value | none |

`BitSet.Static` performs no allocation, waiting, hidden global access, atomics, or
barriers.

## Error behavior

- index-taking mutators return `error.OutOfBounds` for `index >= bit_capacity`;
- methods that require a valid receiver may assert on invalid unused high bits;
- `Static(N)` itself has no fallible construction path.

## Implementation constraints

Implementation must:

- use `u64` words;
- reject `Static(0)` at compile time with `@compileError`;
- compute `word_count` without integer overflow;
- keep unused high bits clear after every public mutation;
- avoid public bit-scan wrappers around Zig builtins;
- use `@popCount` for `count()` or exactly matching behavior;
- use `@ctz` for lowest-set-bit scans or exactly matching behavior.

## Required tests

Required capacities:

- `Static(1)`;
- `Static(64)`;
- `Static(65)`;
- a non-word multiple such as `Static(129)`.

### Construction and whole-set behavior

- default struct literal is empty;
- `init()` is empty;
- `full()` sets only valid bits;
- `setAll()` fills an empty set;
- `isEmpty()` and `isFull()` cover empty, partial, and full sets.

### Single-index behavior

- `set` and `isSet` cover first, middle, and last valid index;
- `unset` clears an existing bit;
- `assign` sets and clears;
- `toggle` flips both directions;
- `set` returns false when the bit was previously clear;
- `set` returns true when the bit was previously set, and the bit remains set;
- `unset` returns true when the bit was previously set;
- `unset` returns false when the bit was previously clear, and the bit remains clear;
- `assign(i, true)` and `assign(i, false)` each return the prior value across every transition (false→false, false→true, true→false, true→true);
- `toggle` returns the post-toggle (new) value;
- mutators return `error.OutOfBounds` when `index == bit_capacity`;
- `isSet` returns `false` for `index >= bit_capacity` without erroring.

### Lowest-set-bit behavior

- `firstSet()` returns `null` for an empty set;
- `firstSet()` returns the lowest set bit when several bits are set;
- `popFirstSet()` returns bits in ascending order;
- `popFirstSet()` clears the returned bit;
- `popFirstSet()` returns `null` after the set becomes empty.

### Set algebra

- `eql` distinguishes equal and unequal sets;
- `containsAll` covers true and false cases;
- `containsAny` covers true and false cases;
- `unionWith` combines bits;
- `intersectWith` keeps only common bits;
- `differenceWith` removes bits from `self`.

### Invariant tests

- `assertValid()` succeeds after every public mutation;
- unused high bits stay clear after `full`, `setAll`, `toggle`, `unionWith`,
  `intersectWith`, and `differenceWith`;
- debug assertion behavior for manually corrupted unused high bits is covered
  where practical.

## Open questions

None.
