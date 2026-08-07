const std = @import("std");
const x86 = @import("stdx").arch.x86_64;
const rflags = x86.registers.rflags;

const testing = std.testing;

test "model: RFLAGS representation and initialization preserve the contract" {
    try testing.expectEqual(@as(usize, 8), @sizeOf(rflags.RFLAGS));
    try testing.expectEqual(@as(u64, 0xa5f3_5ca9_3d7e_1c42), rflags.RFLAGS.fromInt(0xa5f3_5ca9_3d7e_1c42).raw());
    try testing.expectEqual(@as(u64, 0b10), rflags.RFLAGS.init().raw());
    try testing.expect(rflags.RFLAGS.fromInt(1 << 9).interrupt_enable);
}

test "compile: RFLAGS access instantiates" {
    if (!x86.supported) return;
    comptime {
        testing.expectEqual(fn () rflags.RFLAGS, @TypeOf(rflags.read)) catch unreachable;
        testing.expectEqual(fn (rflags.RFLAGS) void, @TypeOf(rflags.write)) catch unreachable;
    }
}

test "host: RFLAGS is readable" {
    if (!x86.supported) return;
    try testing.expect(rflags.read().fixed_one);
}
