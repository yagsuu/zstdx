//! single-integer bit words

const std = @import("std");

const debug = @import("core").debug;

pub fn Word(comptime T: type) type {
    comptime {
        const info = @typeInfo(T);
        if (info != .int or info.int.signedness != .unsigned) {
            @compileError("Word requires an unsigned integer type");
        }

        if (info.int.bits == 0) {
            @compileError("Word requires a positive-width integer");
        }
    }

    return enum(T) {
        zero = 0,
        _,

        const Self = @This();

        pub const Int = T;
        pub const Shift = std.math.Log2Int(T);

        pub const width: usize = @bitSizeOf(T);
        pub const size: usize = @sizeOf(T);
        pub const full: Self = from(std.math.maxInt(T));

        pub fn wordsFor(bit_count: usize) usize {
            return bit_count / width + @intFromBool(bit_count % width != 0);
        }

        pub fn from(value: T) Self {
            return @enumFromInt(value);
        }

        pub fn raw(self: Self) T {
            return @intFromEnum(self);
        }

        pub fn isSet(self: Self, index: usize) bool {
            return self.raw() & maskOf(index) != 0;
        }

        pub fn set(self: *Self, index: usize) void {
            self.* = from(self.raw() | maskOf(index));
        }

        pub fn unset(self: *Self, index: usize) void {
            self.* = from(self.raw() & ~maskOf(index));
        }

        pub fn toggle(self: *Self, index: usize) void {
            self.* = from(self.raw() ^ maskOf(index));
        }

        pub fn maskOf(index: usize) T {
            if (debug.checksEnabled()) {
                std.debug.assert(index < width);
            }
            const shift: Shift = @intCast(index);
            return @as(T, 1) << shift;
        }
    };
}

pub const unit = struct {
    const testing = std.testing;

    test "word mutations preserve neighboring bits" {
        inline for (.{ u1, u8, u17, u64, u128 }) |T| {
            const W = Word(T);
            var word: W = .zero;

            for (0..W.width) |index| {
                word.set(index);

                try testing.expectEqual(W.maskOf(index), word.raw());
                for (0..W.width) |other| {
                    try testing.expectEqual(index == other, word.isSet(other));
                }

                word.toggle(index);

                try testing.expectEqual(W.zero, word);

                word = W.full;
                word.unset(index);

                try testing.expectEqual(W.full.raw() & ~W.maskOf(index), word.raw());

                word.toggle(index);

                try testing.expectEqual(W.full, word);
                word = .zero;
            }
        }
    }

    test "word counts round up without overflowing at the bit-count limit" {
        inline for (.{ u8, u17, u64, u128 }) |T| {
            const W = Word(T);
            const bits = [_]usize{ 0, 1, W.width, W.width + 1, 3 * W.width - 1, 3 * W.width, 3 * W.width + 1 };
            const counts = [_]usize{ 0, 1, 1, 2, 3, 3, 4 };

            for (bits, counts) |bit_count, expected| {
                try testing.expectEqual(expected, W.wordsFor(bit_count));
            }
        }

        const limit = std.math.maxInt(usize);

        try testing.expectEqual(limit, Word(u1).wordsFor(limit));
        try testing.expectEqual(@as(usize, 1) << (@bitSizeOf(usize) - 6), Word(u64).wordsFor(limit));

        comptime {
            std.debug.assert(Word(u64).wordsFor(65) == 2);
        }
    }

    test "word operations support narrow widths at comptime" {
        comptime {
            const Narrow = Word(u1);

            var narrow: Narrow = .zero;
            narrow.set(0);
            std.debug.assert(narrow == Narrow.full);

            narrow.unset(0);
            std.debug.assert(narrow == Narrow.zero);

            const Odd = Word(u17);

            var odd = Odd.from(1);
            odd.set(16);
            std.debug.assert(odd.raw() == 0x10001);

            odd.unset(0);
            std.debug.assert(odd.raw() == 0x10000);

            odd.toggle(16);
            std.debug.assert(odd == Odd.zero);
        }
    }
};
