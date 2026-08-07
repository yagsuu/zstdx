const std = @import("std");
const x86 = @import("stdx").arch.x86_64;
const registers = x86.registers;

const testing = std.testing;

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "model: descriptor selectors preserve every bit" {
    inline for (.{ registers.tr.TR, registers.ldtr.LDTR }) |T| {
        try testing.expectEqual(@as(usize, 2), @sizeOf(T));
        try testing.expectEqual(@as(u16, 0xa5f3), T.fromInt(0xa5f3).raw());
    }
    comptime testing.expect(registers.tr.TR != registers.ldtr.LDTR) catch unreachable;
}

test "model: pseudo-descriptors have the specified layout" {
    inline for (.{ registers.gdtr.GDTR, registers.idtr.IDTR }) |T| {
        try testing.expectEqual(@as(usize, 10), @sizeOf(T));
        try testing.expectEqual(@as(usize, 2), @alignOf(T));
        try testing.expectEqual(@as(usize, 0), @offsetOf(T, "limit"));
        try testing.expectEqual(@as(usize, 2), @offsetOf(T, "base"));
    }
    try testing.expectEqual(@as(u16, 0), registers.gdtr.GDTR.init().limit);
    try testing.expectEqual(@as(u64, 0), registers.gdtr.GDTR.init().base);
    comptime testing.expect(registers.gdtr.GDTR != registers.idtr.IDTR) catch unreachable;
}

test "compile: descriptor-register wrappers have distinct typed signatures" {
    if (!x86.supported) return;
    expectFn(fn (registers.gdtr.GDTR) void, registers.gdtr.write);
    expectFn(fn () registers.gdtr.GDTR, registers.gdtr.read);
    expectFn(fn (registers.idtr.IDTR) void, registers.idtr.write);
    expectFn(fn () registers.idtr.IDTR, registers.idtr.read);
    expectFn(fn (registers.tr.TR) void, registers.tr.write);
    expectFn(fn () registers.tr.TR, registers.tr.read);
    expectFn(fn (registers.ldtr.LDTR) void, registers.ldtr.write);
    expectFn(fn () registers.ldtr.LDTR, registers.ldtr.read);
}
