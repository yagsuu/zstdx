const std = @import("std");
const x86 = @import("stdx").arch.x86_64;

const testing = std.testing;

test "unit: Port.fromInt and raw round-trip at boundaries" {
    try testing.expectEqual(@as(u16, 0), x86.Port.fromInt(0).raw());
    try testing.expectEqual(@as(u16, 0x3f8), x86.Port.fromInt(0x3f8).raw());
    try testing.expectEqual(@as(u16, 0xffff), x86.Port.fromInt(0xffff).raw());
}

test "compile: Port scalar I/O instantiates for every width" {
    if (!x86.supported) return;
    comptime {
        testing.expectEqual(fn (x86.Port) u8, @TypeOf(x86.Port.in8)) catch unreachable;
        testing.expectEqual(fn (x86.Port) u16, @TypeOf(x86.Port.in16)) catch unreachable;
        testing.expectEqual(fn (x86.Port) u32, @TypeOf(x86.Port.in32)) catch unreachable;
        testing.expectEqual(fn (x86.Port, u8) void, @TypeOf(x86.Port.out8)) catch unreachable;
        testing.expectEqual(fn (x86.Port, u16) void, @TypeOf(x86.Port.out16)) catch unreachable;
        testing.expectEqual(fn (x86.Port, u32) void, @TypeOf(x86.Port.out32)) catch unreachable;
    }
}
