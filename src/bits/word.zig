//! Unchecked word-of-bits arithmetic used by every bitmap consumer.
//! See `docs/specs/bits/word.md`.

const std = @import("std");

const debug = @import("../core/debug.zig");

fn requireUnsignedInt(comptime Word: type) void {
    const info = @typeInfo(Word);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("bits.word requires an unsigned integer type");
    }
}

/// Returns the number of words needed to hold `bit_capacity` bits.
pub fn count(comptime Word: type, bit_capacity: usize) usize {
    comptime requireUnsignedInt(Word);
    const bits: usize = @bitSizeOf(Word);
    return @divFloor(bit_capacity, bits) + @intFromBool(bit_capacity % bits != 0);
}

/// Returns a mask for the used low bits of a bitmap's trailing word. Returns
/// `0` when `bit_capacity == 0` and all ones when `bit_capacity` is a whole
/// multiple of `@bitSizeOf(Word)`.
pub fn lastMask(comptime Word: type, bit_capacity: usize) Word {
    comptime requireUnsignedInt(Word);
    if (bit_capacity == 0) return 0;
    const bits: usize = @bitSizeOf(Word);
    const rem: usize = bit_capacity % bits;
    if (rem == 0) return ~@as(Word, 0);
    const shift: std.math.Log2Int(Word) = @intCast(rem);
    return (@as(Word, 1) << shift) - 1;
}

/// Returns the word index that contains `bit_index`.
pub fn indexOf(comptime Word: type, bit_index: usize) usize {
    comptime requireUnsignedInt(Word);
    return @divFloor(bit_index, @bitSizeOf(Word));
}

/// Returns the single-bit mask at `bit_index % @bitSizeOf(Word)`.
pub fn maskOf(comptime Word: type, bit_index: usize) Word {
    comptime requireUnsignedInt(Word);
    const shift: std.math.Log2Int(Word) = @intCast(bit_index % @bitSizeOf(Word));
    return @as(Word, 1) << shift;
}

/// Returns whether the bit at `bit_index` is set. Precondition:
/// `indexOf(Word, bit_index) < words.len`. Under safety checks this
/// precondition is asserted; under release it is undefined behavior.
pub fn isSet(comptime Word: type, words: []const Word, bit_index: usize) bool {
    comptime requireUnsignedInt(Word);
    const word_index = indexOf(Word, bit_index);
    if (debug.checksEnabled(.build_mode)) std.debug.assert(word_index < words.len);
    return (words[word_index] & maskOf(Word, bit_index)) != 0;
}

/// Sets the bit at `bit_index`. The precondition and safety contract match
/// `isSet`.
pub fn set(comptime Word: type, words: []Word, bit_index: usize) void {
    comptime requireUnsignedInt(Word);
    const word_index = indexOf(Word, bit_index);
    if (debug.checksEnabled(.build_mode)) std.debug.assert(word_index < words.len);
    words[word_index] |= maskOf(Word, bit_index);
}

/// Clears the bit at `bit_index`. The precondition and safety contract match
/// `isSet`.
pub fn clear(comptime Word: type, words: []Word, bit_index: usize) void {
    comptime requireUnsignedInt(Word);
    const word_index = indexOf(Word, bit_index);
    if (debug.checksEnabled(.build_mode)) std.debug.assert(word_index < words.len);
    words[word_index] &= ~maskOf(Word, bit_index);
}
