# Bitmap word arithmetic

Status: Approved.

`stdx.bits.word` provides unchecked word-of-bits arithmetic for bitmap consumers: capacity-to-word conversion, trailing-word masks, word and bit indexes, and single-bit slice operations.

## Terminology

A *word* is one `Word` value. A *padding bit* is a bit above a bitmap's `bit_capacity` in its final word.

## Global invariants

`Word` MUST be an unsigned integer type with nonzero bit width. Other types and `u0` are outside the supported type domain.

`count`, `lastMask`, `indexOf`, and `maskOf` accept every `usize` input. `isSet`, `set`, and `clear` require `indexOf(Word, bit_index) < words.len`. The caller MUST enforce that precondition. When `debug.checksEnabled()` is true, the implementation asserts the precondition. When it is false, an invalid index has undefined behavior.

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

The implementation MUST validate `Word` at comptime and use `std.math.Log2Int(Word)` as the shift type in `maskOf`.

## Testing

Tests MUST cover `u8`, `u32`, and `u64`; zero, partial-word, exact-word, and next-word capacities; trailing masks; division/modulo index and mask formulas; and set/query/clear with neighbor preservation. Compile-time tests MUST check constant evaluation and unsupported types.
