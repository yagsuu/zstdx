//! Unaligned bytes access contract tests. Spec: docs/specs/bytes/unaligned.md.

const std = @import("std");

const zstdx = @import("zstdx");

const bytes = zstdx.bytes;

const testing = std.testing;

test "unit: unaligned load/store round-trips every supported integer width" {
    inline for (.{ u8, u16, u32, u64, usize }) |T| {
        var buf: [@sizeOf(T)]u8 = undefined;
        bytes.storeUnaligned(T, &buf, @as(T, 7));
        try testing.expectEqual(@as(T, 7), bytes.loadUnaligned(T, &buf));
    }
}

test "unit: unaligned load/store works on fixed-size arrays" {
    var arr_bytes: [@sizeOf([3]u8)]u8 = undefined;
    bytes.storeUnaligned([3]u8, &arr_bytes, .{ 1, 2, 3 });
    try testing.expectEqual([3]u8{ 1, 2, 3 }, bytes.loadUnaligned([3]u8, &arr_bytes));
}

test "unit: unaligned load/store accepts a packed struct" {
    const Packed = packed struct { a: u3, b: u5 };
    try testing.expectEqual(@as(usize, 1), @sizeOf(Packed));
    var packed_bytes: [1]u8 = undefined;
    bytes.storeUnaligned(Packed, &packed_bytes, .{ .a = 5, .b = 17 });
    try testing.expectEqual(@as(u5, 17), bytes.loadUnaligned(Packed, &packed_bytes).b);
}

test "unit: unaligned load/store accepts an extern struct" {
    const Extern = extern struct { a: u8, b: u32 };
    try testing.expectEqual(@as(usize, 4), @alignOf(Extern));
    try testing.expect(@offsetOf(Extern, "b") >= 4);
    var ext_bytes: [@sizeOf(Extern)]u8 = undefined;
    bytes.storeUnaligned(Extern, &ext_bytes, .{ .a = 1, .b = 2 });
    try testing.expectEqual(@as(u32, 2), bytes.loadUnaligned(Extern, &ext_bytes).b);
}
