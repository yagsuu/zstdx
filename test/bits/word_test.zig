//! bits.word contract tests. See `docs/specs/bits/word.md`.

const std = @import("std");

const stdx = @import("stdx");

const word = stdx.bits.word;

const testing = std.testing;

test "unit: count matches ceilDiv over the width matrix" {
    inline for (.{ u8, u32, u64 }) |Word| {
        const bits: usize = @bitSizeOf(Word);
        try testing.expectEqual(@as(usize, 0), word.count(Word, 0));
        try testing.expectEqual(@as(usize, 1), word.count(Word, 1));
        try testing.expectEqual(@as(usize, 1), word.count(Word, bits));
        try testing.expectEqual(@as(usize, 2), word.count(Word, bits + 1));
        try testing.expectEqual(@as(usize, 3), word.count(Word, 3 * bits - 1));
        try testing.expectEqual(@as(usize, 3), word.count(Word, 3 * bits));
        try testing.expectEqual(@as(usize, 4), word.count(Word, 3 * bits + 1));
    }
}

test "unit: lastMask is zero at zero, all-ones at word boundary, one bit past" {
    inline for (.{ u8, u32, u64 }) |Word| {
        const bits: usize = @bitSizeOf(Word);
        try testing.expectEqual(@as(Word, 0), word.lastMask(Word, 0));
        try testing.expectEqual(~@as(Word, 0), word.lastMask(Word, bits));
        try testing.expectEqual(~@as(Word, 0), word.lastMask(Word, 2 * bits));
        try testing.expectEqual(@as(Word, 1), word.lastMask(Word, bits + 1));
    }
}

test "unit: lastMask exposes exactly the in-capacity bits of the tail word" {
    inline for (.{ u8, u32, u64 }) |Word| {
        const bits: usize = @bitSizeOf(Word);
        var k: usize = 1;
        while (k <= 3 * bits) : (k += 1) {
            const rem = k % bits;
            const expected: Word = if (rem == 0)
                ~@as(Word, 0)
            else
                (@as(Word, 1) << @as(std.math.Log2Int(Word), @intCast(rem))) - 1;
            try testing.expectEqual(expected, word.lastMask(Word, k));
        }
    }
}

test "unit: indexOf and maskOf partition the bit space" {
    inline for (.{ u8, u32, u64 }) |Word| {
        const bits: usize = @bitSizeOf(Word);
        var k: usize = 0;
        while (k < 4 * bits) : (k += 1) {
            try testing.expectEqual(k / bits, word.indexOf(Word, k));
            const shift: std.math.Log2Int(Word) = @intCast(k % bits);
            try testing.expectEqual(@as(Word, 1) << shift, word.maskOf(Word, k));
        }
    }
}

test "unit: isSet on a zeroed buffer is uniformly false" {
    inline for (.{ u8, u64 }) |Word| {
        const bits: usize = @bitSizeOf(Word);
        var storage: [4]Word = [_]Word{0} ** 4;
        var k: usize = 0;
        while (k < 4 * bits) : (k += 1) {
            try testing.expect(!word.isSet(Word, storage[0..], k));
        }
    }
}

test "unit: set then isSet returns true; clear restores false" {
    inline for (.{ u8, u64 }) |Word| {
        const bits: usize = @bitSizeOf(Word);
        var storage: [4]Word = [_]Word{0} ** 4;
        const targets = [_]usize{ 0, 1, bits - 1, bits, bits + 1, 2 * bits - 1, 3 * bits };
        for (targets) |k| {
            word.set(Word, storage[0..], k);
            try testing.expect(word.isSet(Word, storage[0..], k));
        }
        for (targets) |k| {
            word.clear(Word, storage[0..], k);
            try testing.expect(!word.isSet(Word, storage[0..], k));
        }
    }
}

test "unit: set at k does not disturb any neighbor bit" {
    inline for (.{ u8, u64 }) |Word| {
        const bits: usize = @bitSizeOf(Word);
        const targets = [_]usize{ 0, 1, bits - 1, bits, bits + 1, 2 * bits };
        for (targets) |k| {
            var storage: [4]Word = [_]Word{0} ** 4;
            word.set(Word, storage[0..], k);

            var i: usize = 0;
            while (i < 3 * bits) : (i += 1) {
                const expect_set = (i == k);
                try testing.expectEqual(expect_set, word.isSet(Word, storage[0..], i));
            }
        }
    }
}

test "unit: set and clear at the last bit of the last word do not overflow" {
    const Word = u64;
    const bits: usize = @bitSizeOf(Word);
    var storage: [2]Word = [_]Word{0} ** 2;
    const last_bit = 2 * bits - 1;

    word.set(Word, storage[0..], last_bit);
    try testing.expect(word.isSet(Word, storage[0..], last_bit));
    try testing.expectEqual(@as(Word, 1) << @as(std.math.Log2Int(Word), @intCast(bits - 1)), storage[1]);
    try testing.expectEqual(@as(Word, 0), storage[0]);

    word.clear(Word, storage[0..], last_bit);
    try testing.expectEqual(@as(Word, 0), storage[0]);
    try testing.expectEqual(@as(Word, 0), storage[1]);
}

test "unit: comptime evaluation of arithmetic helpers" {
    comptime {
        std.debug.assert(word.count(u64, 0) == 0);
        std.debug.assert(word.count(u64, 64) == 1);
        std.debug.assert(word.count(u64, 65) == 2);
        std.debug.assert(word.lastMask(u64, 64) == std.math.maxInt(u64));
        std.debug.assert(word.lastMask(u64, 0) == 0);
        std.debug.assert(word.indexOf(u64, 128) == 2);
        std.debug.assert(word.maskOf(u64, 63) == @as(u64, 1) << 63);
    }
}
