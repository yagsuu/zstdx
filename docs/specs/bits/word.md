# Bitmap word arithmetic

Status: Approved.

`stdx.bits.word` owns the unchecked word-of-bits arithmetic used to
build bitmap consumers: ceiling-divide a bit capacity into words,
mask the trailing bits in the last word, index into a word/bit pair,
and set/clear/query a single bit within a word slice.

The module is deliberately unchecked. It performs no bounds validation,
no allocation, no waiting, and no policy decisions. Bounds checking,
capacity policy, and error surface are the caller's contract.

## Owned scope

This spec owns:

- `bits.word.count(comptime Word, bit_capacity)`;
- `bits.word.lastMask(comptime Word, bit_capacity)`;
- `bits.word.indexOf(comptime Word, bit_index)`;
- `bits.word.maskOf(comptime Word, bit_index)`;
- `bits.word.isSet(comptime Word, words, bit_index)`;
- `bits.word.set(comptime Word, words, bit_index)`;
- `bits.word.clear(comptime Word, words, bit_index)`;
- `Word` type contract (unsigned integer);
- unchecked-arithmetic and no-bounds-check behavior;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- bounds-checked bitmap operations (each consumer owns its own bounds
  rules);
- `findFirstFree`, `findFirstSet`, `popCount`, or any scan/reduce
  operation (deferred until at least one second consumer picks the same
  algorithm shape);
- toggle / assign / prior-value-returning mutators (each consumer that
  needs a `prior_value` bool pairs `isSet` with `set`/`clear`);
- iteration, range operations, or bit-slice extraction;
- concurrency, atomics, or fences;
- allocator-backed word storage;
- root promotion of any name in this module.

## Public namespace

The module lives under `stdx.bits`:

```zig
stdx.bits.word
stdx.bits.word.count
stdx.bits.word.lastMask
stdx.bits.word.indexOf
stdx.bits.word.maskOf
stdx.bits.word.isSet
stdx.bits.word.set
stdx.bits.word.clear
```

No root promotion:

```zig
stdx.word // not exported
```

Source ownership:

```text
src/bits.zig
src/bits/word.zig
test/bits/word_test.zig
```

`src/bits.zig` re-exports:

```zig
pub const word = @import("bits/word.zig");
```

## Approved API

```zig
pub fn count(comptime Word: type, bit_capacity: usize) usize;
pub fn lastMask(comptime Word: type, bit_capacity: usize) Word;
pub fn indexOf(comptime Word: type, bit_index: usize) usize;
pub fn maskOf(comptime Word: type, bit_index: usize) Word;

pub fn isSet(comptime Word: type, words: []const Word, bit_index: usize) bool;
pub fn set(comptime Word: type, words: []Word, bit_index: usize) void;
pub fn clear(comptime Word: type, words: []Word, bit_index: usize) void;
```

`Word` MUST be an unsigned integer type. Signed integers, floats,
bools, enums, pointers, and comptime integers without an explicit
`Word` are compile errors.

## Semantics

### `count(Word, bit_capacity)`

Returns the number of `Word`-sized elements required to hold
`bit_capacity` bits:

```text
count(Word, 0)              == 0
count(Word, 1)              == 1
count(Word, @bitSizeOf(Word)) == 1
count(Word, @bitSizeOf(Word) + 1) == 2
```

Equivalent to `ceilDiv(bit_capacity, @bitSizeOf(Word))`. Never
overflows `usize` for any representable `bit_capacity` because the
result is bounded above by `bit_capacity`.

### `lastMask(Word, bit_capacity)`

Returns the bit-mask covering the used low bits of the trailing word
in a bitmap of `bit_capacity` bits:

```text
lastMask(Word, 0)                     == 0
lastMask(Word, @bitSizeOf(Word))      == ~@as(Word, 0)   // all ones
lastMask(Word, @bitSizeOf(Word) + 1)  == 1
lastMask(Word, 2 * @bitSizeOf(Word))  == ~@as(Word, 0)
```

For a bitmap of `bit_capacity` bits laid out over
`count(Word, bit_capacity)` words, applying `lastMask` to the last
word's contents extracts only the in-capacity bits and clears any
padding bits above `bit_capacity`.

When `bit_capacity == 0`, `lastMask` returns `0`. Callers that access
the last word MUST check for zero capacity first; the mask alone does
not encode "no word exists".

### `indexOf(Word, bit_index)`

Returns the word index containing `bit_index`:

```text
indexOf(Word, bit_index) == bit_index / @bitSizeOf(Word)
```

Never asserts bounds. Callers with a `bit_capacity` in hand MUST
enforce `bit_index < bit_capacity` themselves.

### `maskOf(Word, bit_index)`

Returns a `Word` with exactly one bit set at position
`bit_index % @bitSizeOf(Word)`:

```text
maskOf(Word, 0)                     == 1
maskOf(Word, 1)                     == 2
maskOf(Word, @bitSizeOf(Word) - 1)  == 1 << (@bitSizeOf(Word) - 1)
maskOf(Word, @bitSizeOf(Word))      == 1
```

Never asserts bounds.

### `isSet(Word, words, bit_index)`

Returns whether the bit at `bit_index` is set in `words`. Precondition
(caller-enforced, NOT checked here):
`indexOf(Word, bit_index) < words.len`.

Under `stdx.core.debug.checksEnabled(.build_mode)` the implementation
MAY assert the precondition. Under release builds it does not.

### `set(Word, words, bit_index)`

Sets the bit at `bit_index` in `words`. Same precondition as `isSet`.
`void` return; callers that need the prior bit value call `isSet`
first.

### `clear(Word, words, bit_index)`

Clears the bit at `bit_index` in `words`. Same precondition and
return contract as `set`.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `count` | never | never | O(1) | none | pure function | none |
| `lastMask` | never | never | O(1) | none | pure function | none |
| `indexOf` | never | never | O(1) | none | pure function | none |
| `maskOf` | never | never | O(1) | none | pure function | none |
| `isSet` | never | never | O(1) | none | pure function | none |
| `set` | never | never | O(1) | bit at `bit_index` | caller-owned buffer | none |
| `clear` | never | never | O(1) | bit at `bit_index` | caller-owned buffer | none |

These operations perform no heap allocation, waiting, hidden global
access, atomics, barriers, volatile access, target probing, syscalls,
or I/O.

Concurrent mutation of `words` is outside the contract. Callers MUST
externally synchronize shared mutable access.

## Error behavior

- invalid `Word` type is a compile error;
- out-of-bounds `bit_index` is a caller contract violation, NOT an
  error return. Under safety checks, `set`/`clear`/`isSet` MAY assert;
  under release, behavior is undefined and callers MUST prevent it;
- no runtime error set.

## Implementation constraints

Implementation MUST:

- validate `Word` is an unsigned integer type at comptime with a
  clear message;
- compute `indexOf` and `maskOf` with unchecked arithmetic (guaranteed
  by the `Word` type contract);
- use `std.math.Log2Int(Word)` for the shift amount in `maskOf`;
- produce zero mask for `lastMask(Word, 0)`;
- add no runtime allocation, no hidden globals, no atomics, no
  barriers.

Implementation MAY:

- use `@ctz` / `@clz` / `@popCount` internally when it helps;
- assert the precondition of `isSet`/`set`/`clear` when
  `stdx.core.debug.checksEnabled(.build_mode)` is true.

## Usage

Bitmap allocator: word-count math and last-word cleanup.

```zig
const stdx = @import("stdx");
const Word = u64;

const bit_capacity: usize = 200;
const word_count = stdx.bits.word.count(Word, bit_capacity);
var words: [word_count]Word = [_]Word{0} ** word_count;

// Mark a bit.
stdx.bits.word.set(Word, words[0..], 137);

// Query it.
const live = stdx.bits.word.isSet(Word, words[0..], 137);
_ = live;

// Reject padding bits when the tail word is inspected directly.
const tail_mask = stdx.bits.word.lastMask(Word, bit_capacity);
const tail_live = words[word_count - 1] & tail_mask;
_ = tail_live;
```

## Planned use

- `stdx.bits.BitSet.Static` word-count and mask primitives;
- `stdx.mem.BitmapAllocator` (Static / Bounded) word-count and query
  primitives;
- `stdx.mem.BuddyAllocator` per-order word-count math;
- `stdx.tags.TagAllocator` (Static / Bounded) word-count, last-mask,
  and single-bit primitives;
- downstream bitmap consumers that need the same word-level
  arithmetic without duplicating it per site.

## Required tests

Tests live in `test/bits/word_test.zig`. Every test exercises at least
`u8`, `u32`, and `u64` to cover the width matrix.

### `count`

- `count(Word, 0) == 0`;
- `count(Word, 1) == 1`;
- `count(Word, @bitSizeOf(Word)) == 1`;
- `count(Word, @bitSizeOf(Word) + 1) == 2`;
- `count(Word, 3 * @bitSizeOf(Word) - 1) == 3`;
- values consistent with `ceilDiv(bit_capacity, @bitSizeOf(Word))` for a
  representative parameter grid over `Word ∈ {u8, u32, u64}` and
  `bit_capacity ∈ {0, 1, bits-1, bits, bits+1, 2*bits}`.

### `lastMask`

- `lastMask(Word, 0) == 0`;
- `lastMask(Word, @bitSizeOf(Word)) == ~@as(Word, 0)`;
- `lastMask(Word, @bitSizeOf(Word) + 1) == 1`;
- `lastMask(Word, 2 * @bitSizeOf(Word) - 1)` has bit `@bitSizeOf(Word) - 1`
  clear;
- `lastMask(Word, k)` matches
  `(1 << (k % @bitSizeOf(Word))) - 1` for `k % @bitSizeOf(Word) != 0`.

### `indexOf` / `maskOf`

- `indexOf(Word, k) == k / @bitSizeOf(Word)` across a range of `k`;
- `maskOf(Word, k) == @as(Word, 1) << (k % @bitSizeOf(Word))`;
- `maskOf(Word, @bitSizeOf(Word)) == 1` (wraps at word boundary).

### Single-bit ops

For at least `Word = u64` and one non-`u64` width:

- `isSet` on a zeroed buffer returns false;
- `set` followed by `isSet` returns true;
- `set` on a range of bits leaves every set bit reporting `true` and
  every other bit reporting `false`;
- `clear` reverses `set`;
- `set` and `clear` of adjacent bits do not disturb neighbors within
  or across word boundaries;
- `set`/`clear` at the last bit of the last word does not touch bits
  beyond `words.len * @bitSizeOf(Word)`.

### Comptime rejection

- `Word = i32`, `Word = f32`, `Word = bool`, and `Word = enum{a}` are
  each compile errors when passed to any function in this module.

### Compile-time constants

- `count(u64, 0) == 0`, `count(u64, 65) == 2`, `count(u64, 64) == 1`
  as `comptime` expressions;
- `lastMask(u64, 64) == std.math.maxInt(u64)` as `comptime`.

## Open questions

None.
