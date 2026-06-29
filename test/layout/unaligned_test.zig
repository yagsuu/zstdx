//! Unaligned layout access contract tests. Spec: docs/specs/layout/unaligned.md.

const std = @import("std");

const zstdx = @import("zstdx");

const layout = zstdx.layout;

const testing = std.testing;

test "unit: unaligned load/store round-trips every supported integer width" {
    inline for (.{ u8, u16, u32, u64, usize }) |T| {
        var bytes: [@sizeOf(T)]u8 = undefined;
        layout.unalignedStore(T, &bytes, @as(T, 7));
        try testing.expectEqual(@as(T, 7), layout.unalignedLoad(T, &bytes));
    }
}

test "unit: unaligned load/store works on fixed-size arrays" {
    var arr_bytes: [@sizeOf([3]u8)]u8 = undefined;
    layout.unalignedStore([3]u8, &arr_bytes, .{ 1, 2, 3 });
    try testing.expectEqual([3]u8{ 1, 2, 3 }, layout.unalignedLoad([3]u8, &arr_bytes));
}

test "unit: unaligned load/store accepts a packed struct" {
    const Packed = packed struct { a: u3, b: u5 };
    try testing.expectEqual(@as(usize, 1), @sizeOf(Packed));
    var packed_bytes: [1]u8 = undefined;
    layout.unalignedStore(Packed, &packed_bytes, .{ .a = 5, .b = 17 });
    try testing.expectEqual(@as(u5, 17), layout.unalignedLoad(Packed, &packed_bytes).b);
}

test "unit: unaligned load/store accepts an extern struct" {
    const Extern = extern struct { a: u8, b: u32 };
    try testing.expectEqual(@as(usize, 4), @alignOf(Extern));
    try testing.expect(@offsetOf(Extern, "b") >= 4);
    var ext_bytes: [@sizeOf(Extern)]u8 = undefined;
    layout.unalignedStore(Extern, &ext_bytes, .{ .a = 1, .b = 2 });
    try testing.expectEqual(@as(u32, 2), layout.unalignedLoad(Extern, &ext_bytes).b);
}
