const std = @import("std");
const x86 = @import("stdx").arch.x86_64;
const registers = x86.registers;

const testing = std.testing;

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "model: control register representations preserve every bit" {
    inline for (.{ registers.cr0.CR0, registers.cr2.CR2, registers.cr3.CR3, registers.cr4.CR4, registers.cr8.CR8, registers.xcr0.XCR0 }) |T| {
        try testing.expectEqual(@as(usize, 8), @sizeOf(T));
        try testing.expectEqual(@as(u64, 0xa5f3_5ca9_3d7e_1c42), T.fromInt(0xa5f3_5ca9_3d7e_1c42).raw());
    }
}

test "model: control register initialization sets canonical defaults" {
    try testing.expectEqual(@as(u64, 1 << 4), registers.cr0.CR0.init().raw());
    try testing.expectEqual(@as(u64, 0), registers.cr2.CR2.init().raw());
    try testing.expectEqual(@as(u64, 0), registers.cr3.CR3.init().raw());
    try testing.expectEqual(@as(u64, 0), registers.cr4.CR4.init().raw());
    try testing.expectEqual(@as(u64, 0), registers.cr8.CR8.init().raw());
    try testing.expectEqual(@as(u64, 1), registers.xcr0.XCR0.init().raw());
}

test "model: control register fields match architectural bit positions" {
    try testing.expect(registers.cr0.CR0.fromInt(1 << 0).protection_enable);
    try testing.expect(registers.cr0.CR0.fromInt(1 << 31).paging);
    try testing.expect(registers.cr3.CR3.fromInt(1 << 61).lam_u57);
    try testing.expect(registers.cr3.CR3.fromInt(1 << 62).lam_u48);
    try testing.expect(registers.cr4.CR4.fromInt(1 << 5).physical_address_extension);
    try testing.expect(registers.cr4.CR4.fromInt(1 << 18).osxsave);
    try testing.expect(registers.cr4.CR4.fromInt(1 << 28).lam_supervisor);
    try testing.expectEqual(@as(u4, 0xf), registers.cr8.CR8.fromInt(0xf).task_priority);
    try testing.expect(registers.xcr0.XCR0.fromInt(1 << 7).hi16_zmm);
}

test "unit: CR3 interprets root, low-bit, LAM, and no-flush fields" {
    const CR3 = registers.cr3.CR3;
    const value = CR3.fromInt(0x0000_0001_1234_5018);

    try testing.expectEqual(@as(u64, 0x0000_0001_1234_5000), (try value.tableBaseAddress(52)).raw());
    try testing.expectEqual(@as(u12, 0x18), (try value.low(true)).pcid);
    const cache_controls = (try value.low(false)).cache;
    try testing.expect(cache_controls.write_through);
    try testing.expect(cache_controls.cache_disable);

    try testing.expectError(error.InvalidPhysicalAddressWidth, value.tableBaseAddress(31));
    try testing.expectError(error.PhysicalAddressTooWide, value.tableBaseAddress(32));
    try testing.expectError(error.ReservedBits, CR3.fromInt(1 << 52).tableBaseAddress(52));
    try testing.expectError(error.ReservedLowBits, CR3.fromInt(1).low(false));

    const lam_u48 = CR3.fromInt(1 << 62);
    const lam_u57 = CR3.fromInt(1 << 61);
    const both_lam = CR3.fromInt((1 << 62) | (1 << 61));
    try testing.expectEqual(.u48, try lam_u48.userLAM(true));
    try testing.expectEqual(.u57, try lam_u57.userLAM(true));
    try testing.expectEqual(.u57, try both_lam.userLAM(true));
    try testing.expectError(error.UnsupportedLAM, lam_u48.userLAM(false));
    try testing.expect(CR3.fromInt(1 << 63).no_flush);
}

test "unit: CR4 validates paging controls against capabilities" {
    const value = registers.cr4.CR4.fromInt((1 << 12) | (1 << 17) | (1 << 28));
    try testing.expect(try value.pcidEnabled(true));
    try testing.expect(try value.level5Enabled(true));
    try testing.expectEqual(.u57, try value.supervisorLAM(true));
    try testing.expectError(error.UnsupportedPCID, value.pcidEnabled(false));
    try testing.expectError(error.UnsupportedFiveLevelPaging, value.level5Enabled(false));
    try testing.expectError(error.UnsupportedLAM, value.supervisorLAM(false));
}

test "compile: control register accessors instantiate" {
    if (!x86.supported) return;
    inline for (.{ registers.cr0, registers.cr2, registers.cr3, registers.cr4, registers.cr8, registers.xcr0 }) |namespace| {
        const T = @TypeOf(namespace.read());
        expectFn(fn () T, namespace.read);
        expectFn(fn (T) void, namespace.write);
    }
}
