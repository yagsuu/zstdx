//! Bit-mask construction. See `docs/specs/bits/mask.md`.

const std = @import("std");

/// Requirements: `T` is a non-zero-width unsigned integer and `count <= @bitSizeOf(T)`.
pub fn low(comptime T: type, count: usize) T {
    comptime requireUnsignedInt(T);
    std.debug.assert(count <= @bitSizeOf(T));

    if (count == @bitSizeOf(T)) {
        return ~@as(T, 0);
    }

    const shift: std.math.Log2Int(T) = @intCast(count);
    return (@as(T, 1) << shift) - 1;
}

/// Requirements: `T` is a non-zero-width unsigned integer and `index < @bitSizeOf(T)`.
pub fn single(comptime T: type, index: usize) T {
    comptime requireUnsignedInt(T);
    std.debug.assert(index < @bitSizeOf(T));
    const shift: std.math.Log2Int(T) = @intCast(index);
    return @as(T, 1) << shift;
}

/// Requirements: `T` is a non-zero-width unsigned integer, `first <= last`, and `last < @bitSizeOf(T)`.
pub fn range(comptime T: type, first: usize, last: usize) T {
    comptime requireUnsignedInt(T);
    std.debug.assert(first <= last);
    std.debug.assert(last < @bitSizeOf(T));

    const width = last - first + 1;
    const first_shift: std.math.Log2Int(T) = @intCast(first);
    return low(T, width) << first_shift;
}

pub const unit = struct {
    const testing = std.testing;

    test "low masks cover empty, single-bit, and full widths" {
        inline for (.{ u1, u8, u17, u32, u64, u128 }) |T| {
            try testing.expectEqual(@as(T, 0), low(T, 0));
            try testing.expectEqual(@as(T, 1), low(T, 1));
            try testing.expectEqual(~@as(T, 0), low(T, @bitSizeOf(T)));
        }
    }

    test "low masks equal the union of selected bits" {
        inline for (.{ u8, u17, u64, u128 }) |T| {
            const bit_count = @bitSizeOf(T);
            var n: usize = 0;
            while (n <= bit_count) : (n += 1) {
                var expected: T = 0;
                var index: usize = 0;
                while (index < n) : (index += 1) {
                    expected |= single(T, index);
                }

                try testing.expectEqual(expected, low(T, n));
            }
        }
    }

    test "single masks select boundary and interior bits" {
        inline for (.{ u8, u32, u64 }) |T| {
            const last = @bitSizeOf(T) - 1;

            try testing.expectEqual(@as(T, 1), single(T, 0));
            try testing.expectEqual(@as(T, 1) << @intCast(last / 2), single(T, last / 2));
            try testing.expectEqual(@as(T, 1) << @intCast(last), single(T, last));
        }
        try testing.expectEqual(@as(u1, 1), single(u1, 0));
        try testing.expectEqual(@as(u128, 1) << 127, single(u128, 127));
        try testing.expectEqual(@as(u1, 1), range(u1, 0, 0));
    }

    test "inclusive ranges match IntegerBitSet for every legal bound" {
        inline for (.{ u8, u17, u64, u128 }) |T| {
            const Set = std.bit_set.IntegerBitSet(@bitSizeOf(T));
            const bit_count = @bitSizeOf(T);
            var first: usize = 0;
            while (first < bit_count) : (first += 1) {
                var last = first;
                while (last < bit_count) : (last += 1) {
                    var expected = Set.empty;
                    expected.setRangeValue(.{ .start = first, .end = last + 1 }, true);

                    try testing.expectEqual(expected.mask, range(T, first, last));
                }
            }
        }
    }

    test "mask primitives evaluate at comptime" {
        comptime {
            std.debug.assert(low(u64, 52) == 0x000f_ffff_ffff_ffff);
            std.debug.assert(single(u64, 63) == @as(u64, 1) << 63);
            std.debug.assert(range(u64, 12, 51) == 0x000f_ffff_ffff_f000);
        }
    }
};

fn requireUnsignedInt(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != .unsigned or info.int.bits == 0) {
        @compileError("bits.mask requires a non-zero-width unsigned integer type");
    }
}
