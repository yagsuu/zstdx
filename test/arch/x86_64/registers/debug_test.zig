const std = @import("std");
const x86 = @import("stdx").arch.x86_64;
const registers = x86.registers;

const testing = std.testing;

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "model: debug register representations preserve every bit" {
    inline for (.{ registers.dr0.DR0, registers.dr1.DR1, registers.dr2.DR2, registers.dr3.DR3, registers.dr4.DR4, registers.dr5.DR5, registers.dr6.DR6, registers.dr7.DR7 }) |T| {
        try testing.expectEqual(@as(usize, 8), @sizeOf(T));
        try testing.expectEqual(@as(u64, 0xa5f3_5ca9_3d7e_1c42), T.fromInt(0xa5f3_5ca9_3d7e_1c42).raw());
    }
    try testing.expectEqual(@as(u64, 1 << 10), registers.dr7.DR7.init().raw());
    try testing.expect(registers.dr6.DR6.fromInt(1 << 15).task_switch);
    try testing.expectEqual(@as(u2, 3), registers.dr7.DR7.fromInt(3 << 16).br0.condition);
    try testing.expectEqual(@as(u2, 3), registers.dr7.DR7.fromInt(3 << 18).br0.length);
    comptime testing.expect(registers.dr0.DR0 != registers.dr1.DR1) catch unreachable;
}

test "contract: debug register accessors instantiate" {
    if (!x86.supported) return;
    inline for (.{ registers.dr0, registers.dr1, registers.dr2, registers.dr3, registers.dr4, registers.dr5, registers.dr6, registers.dr7 }) |namespace| {
        const T = @TypeOf(namespace.read());
        expectFn(fn () T, namespace.read);
        expectFn(fn (T) void, namespace.write);
    }
}
