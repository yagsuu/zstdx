//! Unchecked word-of-bits arithmetic used by every bitmap consumer. Spec:
//! docs/specs/bits/word.md.

const std = @import("std");

const debug = @import("../core/debug.zig");

fn requireUnsignedInt(comptime Word: type) void {
    const info = @typeInfo(Word);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("bits.word requires an unsigned integer type");
    }
}

/// Words required to hold `bit_capacity` bits.
/// `ceilDiv(bit_capacity, @bitSizeOf(Word))`.
pub fn count(comptime Word: type, bit_capacity: usize) usize {
    comptime requireUnsignedInt(Word);
    const bits: usize = @bitSizeOf(Word);
    return bit_capacity / bits + @intFromBool(bit_capacity % bits != 0);
}

/// Mask covering the used low bits of the trailing word in a bitmap of
/// `bit_capacity` bits. Returns `0` when `bit_capacity == 0`,
/// all-ones when `bit_capacity` is a whole multiple of `@bitSizeOf(Word)`.
pub fn lastMask(comptime Word: type, bit_capacity: usize) Word {
    comptime requireUnsignedInt(Word);
    if (bit_capacity == 0) return 0;
    const bits: usize = @bitSizeOf(Word);
    const rem: usize = bit_capacity % bits;
    if (rem == 0) return ~@as(Word, 0);
    const shift: std.math.Log2Int(Word) = @intCast(rem);
    return (@as(Word, 1) << shift) - 1;
}

/// Word index containing `bit_index`: `bit_index / @bitSizeOf(Word)`.
pub fn indexOf(comptime Word: type, bit_index: usize) usize {
    comptime requireUnsignedInt(Word);
    return bit_index / @bitSizeOf(Word);
}

/// Single-bit mask at position `bit_index % @bitSizeOf(Word)`.
pub fn maskOf(comptime Word: type, bit_index: usize) Word {
    comptime requireUnsignedInt(Word);
    const shift: std.math.Log2Int(Word) = @intCast(bit_index % @bitSizeOf(Word));
    return @as(Word, 1) << shift;
}

/// Whether the bit at `bit_index` is set. Precondition:
/// `indexOf(Word, bit_index) < words.len`. Under safety checks this
/// precondition is asserted; under release it is undefined behavior.
pub fn isSet(comptime Word: type, words: []const Word, bit_index: usize) bool {
    comptime requireUnsignedInt(Word);
    const word_index = indexOf(Word, bit_index);
    if (debug.checksEnabled(.build_mode)) std.debug.assert(word_index < words.len);
    return (words[word_index] & maskOf(Word, bit_index)) != 0;
}

/// Set the bit at `bit_index`. Precondition and safety contract as
/// `isSet`. Returns `void`; callers who need the prior bit value call
/// `isSet` first.
pub fn set(comptime Word: type, words: []Word, bit_index: usize) void {
    comptime requireUnsignedInt(Word);
    const word_index = indexOf(Word, bit_index);
    if (debug.checksEnabled(.build_mode)) std.debug.assert(word_index < words.len);
    words[word_index] |= maskOf(Word, bit_index);
}

/// Clear the bit at `bit_index`. Precondition and safety contract as
/// `isSet`.
pub fn clear(comptime Word: type, words: []Word, bit_index: usize) void {
    comptime requireUnsignedInt(Word);
    const word_index = indexOf(Word, bit_index);
    if (debug.checksEnabled(.build_mode)) std.debug.assert(word_index < words.len);
    words[word_index] &= ~maskOf(Word, bit_index);
}
