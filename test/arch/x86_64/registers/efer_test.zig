const std = @import("std");
const x86 = @import("stdx").arch.x86_64;
const efer = x86.registers.efer;

const testing = std.testing;

test "model: EFER representation and initialization preserve the contract" {
    try testing.expectEqual(@as(usize, 8), @sizeOf(efer.EFER));
    try testing.expectEqual(@as(u64, 0xa5f3_5ca9_3d7e_1c42), efer.EFER.fromInt(0xa5f3_5ca9_3d7e_1c42).raw());
    try testing.expectEqual(@as(u64, 0), efer.EFER.init().raw());
    try testing.expect(efer.EFER.fromInt(1 << 11).execute_disable_enable);
}

test "unit: EFER validates execute-disable capability" {
    const value = efer.EFER.fromInt(1 << 11);
    try testing.expect(try value.executeDisableEnabled(true));
    try testing.expectError(error.UnsupportedExecuteDisable, value.executeDisableEnabled(false));
}

test "compile: EFER access instantiates" {
    if (!x86.supported) return;
    comptime {
        testing.expectEqual(fn () efer.EFER, @TypeOf(efer.read)) catch unreachable;
        testing.expectEqual(fn (efer.EFER) void, @TypeOf(efer.write)) catch unreachable;
    }
}
