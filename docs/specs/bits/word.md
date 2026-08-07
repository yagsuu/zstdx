# Bitmap word arithmetic

Status: Approved.

`stdx.bits.word` provides unchecked word-of-bits arithmetic for bitmap consumers: capacity-to-word conversion, trailing-word masks, word and bit indexes, and single-bit slice operations.

## What this spec is

This spec defines `stdx.bits.word.count`, `lastMask`, `indexOf`, `maskOf`, `isSet`, `set`, and `clear`; the `Word` type restriction; unchecked bounds behavior; and required tests.

## What this spec is not

This spec does not define bounds-checked bitmap operations, scans or reductions, toggle or assign operations, iteration, range operations, atomic operations, fences, or allocator-backed storage. A bitmap consumer owns its capacity and bounds policy.

## Public namespace and source ownership

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

`src/bits.zig` exports `word`. The implementation is `src/bits/word.zig`. The tests are in `test/bits/word_test.zig`.

## Terminology

A *word* is one `Word` value. A *padding bit* is a bit above a bitmap's `bit_capacity` in its final word.

## Global invariants

`Word` MUST be an unsigned integer type. Signed integers, floats, bools, enums, pointers, and comptime integers without an explicit `Word` are compile errors.

`count`, `lastMask`, `indexOf`, and `maskOf` accept every `usize` input. `isSet`, `set`, and `clear` require `indexOf(Word, bit_index) < words.len`. The caller MUST enforce that precondition. When `debug.checksEnabled(.build_mode)` is true, the implementation asserts the precondition. When it is false, an invalid index has undefined behavior.

All operations have $O(1)$ time complexity. They do not allocate, wait, access hidden globals, perform atomics, barriers, volatile access, target probing, syscalls, or I/O. They establish no ordering. Callers MUST externally synchronize concurrent mutable access to `words`.

## API

```zig
pub fn count(comptime Word: type, bit_capacity: usize) usize;
pub fn lastMask(comptime Word: type, bit_capacity: usize) Word;
pub fn indexOf(comptime Word: type, bit_index: usize) usize;
pub fn maskOf(comptime Word: type, bit_index: usize) Word;

pub fn isSet(comptime Word: type, words: []const Word, bit_index: usize) bool;
pub fn set(comptime Word: type, words: []Word, bit_index: usize) void;
pub fn clear(comptime Word: type, words: []Word, bit_index: usize) void;
```

### Capacity and mask operations

`count(Word, bit_capacity)` returns `ceilDiv(bit_capacity, @bitSizeOf(Word))`. It returns zero for zero capacity and cannot overflow `usize`, because its result is at most `bit_capacity`.

`lastMask(Word, bit_capacity)` returns the mask for the used low bits of the final word. It returns zero for zero capacity, all ones when `bit_capacity` is a non-zero multiple of `@bitSizeOf(Word)`, and otherwise `(1 << (bit_capacity % @bitSizeOf(Word))) - 1`. Applying this mask to a final word clears padding bits. A caller MUST not infer that a word exists from `lastMask(Word, 0)`.

`indexOf(Word, bit_index)` returns `bit_index / @bitSizeOf(Word)`.

`maskOf(Word, bit_index)` returns a word with only bit `bit_index % @bitSizeOf(Word)` set. It wraps at each word boundary.

### Slice operations

`isSet` returns whether `bit_index` is set in `words`.

`set` sets `bit_index` in `words`.

`clear` clears `bit_index` in `words`.

The slice operations return no error. `set` and `clear` modify only the selected bit; they do not invalidate the slice or its elements.

## Implementation constraints

The implementation MUST validate `Word` at comptime, compute `indexOf` and `maskOf` with unchecked arithmetic, and use `std.math.Log2Int(Word)` as the shift type in `maskOf`. `lastMask(Word, 0)` MUST return zero. The implementation MUST add no runtime allocation, hidden globals, atomics, or barriers.

## Testing

Tests MUST evaluate `u8`, `u32`, and `u64` to verify the width matrix. Capacity tests MUST cover zero, a partial word, an exact word, and the first bit of the next word; these boundaries prove ceiling division. Trailing-mask tests MUST cover zero capacity, exact-word capacity, partial trailing words, and the all-ones result; these cases prove padding-bit masking without a full-width shift. Index and mask tests MUST compare representative indexes to division and modulo formulas, including a word boundary. Slice-operation tests MUST verify set, query, clear, neighbor preservation, and cross-word boundaries. Compile-time tests MUST verify representative constant evaluation and rejection of invalid `Word` types.
