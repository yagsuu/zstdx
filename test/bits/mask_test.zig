//! bits.mask contract tests. Spec: docs/specs/bits/mask.md.

const std = @import("std");

const stdx = @import("stdx");

const mask = stdx.bits.mask;
const testing = std.testing;

test "unit: low supports empty, partial, and full-width masks" {
    inline for (.{ u1, u8, u17, u32, u64, u128 }) |T| {
        const bit_count = @bitSizeOf(T);
        try testing.expectEqual(@as(T, 0), mask.low(T, 0));
        try testing.expectEqual(@as(T, 1), mask.low(T, 1));
        try testing.expectEqual(~@as(T, 0), mask.low(T, bit_count));
    }
}

test "model: low equals the union of every selected bit" {
    inline for (.{ u8, u17, u64, u128 }) |T| {
        const bit_count = @bitSizeOf(T);
        var count: usize = 0;
        while (count <= bit_count) : (count += 1) {
            var expected: T = 0;
            var index: usize = 0;
            while (index < count) : (index += 1) {
                expected |= mask.single(T, index);
            }
            try testing.expectEqual(expected, mask.low(T, count));
        }
    }
}

test "unit: single selects each tested word boundary and interior bit" {
    inline for (.{ u8, u32, u64 }) |T| {
        const last = @bitSizeOf(T) - 1;
        try testing.expectEqual(@as(T, 1), mask.single(T, 0));
        try testing.expectEqual(@as(T, 1) << @intCast(last / 2), mask.single(T, last / 2));
        try testing.expectEqual(@as(T, 1) << @intCast(last), mask.single(T, last));
    }
}

test "unit: range sets exactly the inclusive bounds" {
    inline for (.{ u8, u32, u64 }) |T| {
        const last = @bitSizeOf(T) - 1;
        try testing.expectEqual(@as(T, 1), mask.range(T, 0, 0));
        try testing.expectEqual(@as(T, 0b0011_1100), mask.range(T, 2, 5));
        try testing.expectEqual(~@as(T, 0), mask.range(T, 0, last));
    }
}

test "model: range matches std IntegerBitSet for every legal bound" {
    inline for (.{ u8, u17, u64, u128 }) |T| {
        const BitSet = std.bit_set.IntegerBitSet(@bitSizeOf(T));
        const bit_count = @bitSizeOf(T);
        var first: usize = 0;
        while (first < bit_count) : (first += 1) {
            var last = first;
            while (last < bit_count) : (last += 1) {
                var expected = BitSet.empty;
                expected.setRangeValue(.{ .start = first, .end = last + 1 }, true);
                try testing.expectEqual(expected.mask, mask.range(T, first, last));
            }
        }
    }
}

test "unit: mask primitives support single-bit and odd-width integers" {
    try testing.expectEqual(@as(u1, 1), mask.single(u1, 0));
    try testing.expectEqual(@as(u1, 1), mask.range(u1, 0, 0));
    try testing.expectEqual(@as(u17, 0x3ff8), mask.range(u17, 3, 13));
    try testing.expectEqual(@as(u128, 1) << 127, mask.single(u128, 127));
    try testing.expectEqual(~@as(u128, 0) << 64, mask.range(u128, 64, 127));
}

test "unit: mask primitives evaluate at comptime" {
    comptime {
        std.debug.assert(mask.low(u64, 0) == 0);
        std.debug.assert(mask.low(u64, 52) == 0x000f_ffff_ffff_ffff);
        std.debug.assert(mask.single(u64, 63) == @as(u64, 1) << 63);
        std.debug.assert(mask.range(u64, 12, 51) == 0x000f_ffff_ffff_f000);
    }
}
