const std = @import("std");
const x86 = @import("stdx").arch.x86_64;

const testing = std.testing;

test "unit: MSR named tags match architectural addresses" {
    try testing.expectEqual(@as(u32, 0x0000_0010), x86.MSR.tsc.raw());
    try testing.expectEqual(@as(u32, 0x0000_001b), x86.MSR.apic_base.raw());
    try testing.expectEqual(@as(u32, 0xc000_0080), x86.MSR.efer.raw());
    try testing.expectEqual(@as(u32, 0xc000_0100), x86.MSR.fs_base.raw());
    try testing.expectEqual(@as(u32, 0xc001_0117), x86.MSR.vm_hsave_pa.raw());
}

test "compile: MSR access instantiates" {
    if (!x86.supported) return;
    comptime {
        testing.expectEqual(fn (x86.MSR) u64, @TypeOf(x86.MSR.read)) catch unreachable;
        testing.expectEqual(fn (x86.MSR, u64) void, @TypeOf(x86.MSR.write)) catch unreachable;
    }
}
