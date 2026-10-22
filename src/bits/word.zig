//! Single-integer bit operations. See `docs/specs/bits/word.md`.

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

    return struct {
        pub const Int = T;
        pub const Shift = std.math.Log2Int(T);

        pub const width: usize = @bitSizeOf(T);
        pub const size: usize = @sizeOf(T);
        pub const full: T = std.math.maxInt(T);

        pub fn maskOf(index: usize) T {
            if (debug.checksEnabled()) {
                std.debug.assert(index < width);
            }
            const shift: Shift = @intCast(index);
            return @as(T, 1) << shift;
        }

        pub fn isSet(value: T, index: usize) bool {
            return (value & maskOf(index)) != 0;
        }

        pub fn set(value: *T, index: usize) void {
            value.* |= maskOf(index);
        }

        pub fn clear(value: *T, index: usize) void {
            value.* &= ~maskOf(index);
        }
    };
}

pub const unit = struct {
    const testing = std.testing;

    test "word mutations preserve neighboring bits" {
        inline for (.{ u8, u32, u64 }) |T| {
            const W = Word(T);
            var value: T = 0;

            for (0..W.width) |index| {
                W.set(&value, index);
                try testing.expectEqual(W.maskOf(index), value);

                for (0..W.width) |other| {
                    try testing.expectEqual(index == other, W.isSet(value, other));
                }

                W.clear(&value, index);
                try testing.expectEqual(@as(T, 0), value);
            }
        }
    }

    test "word operations support narrow widths at comptime" {
        comptime {
            const Narrow = Word(u1);
            var narrow: u1 = 0;

            Narrow.set(&narrow, 0);
            std.debug.assert(narrow == Narrow.full);

            Narrow.clear(&narrow, 0);
            std.debug.assert(narrow == 0);

            const Odd = Word(u17);
            var odd: u17 = 1;

            Odd.set(&odd, 16);
            std.debug.assert(odd == 0x10001);

            Odd.clear(&odd, 0);
            std.debug.assert(odd == 0x10000);
        }
    }
};
