//! IA-32e descriptor entry contract tests.
//! See `docs/specs/arch/x86_64/descriptors.md`.

const std = @import("std");
const descriptors = @import("stdx").arch.x86_64.descriptors;

const testing = std.testing;

const Segment = descriptors.Segment;
const System = descriptors.System;
const Gate = descriptors.Gate;

comptime {
    std.debug.assert(@bitSizeOf(Segment) == 64);
    std.debug.assert(@sizeOf(Segment) == 8);
    std.debug.assert(@bitOffsetOf(Segment, "kind") == 40);
    std.debug.assert(@bitOffsetOf(Segment, "descriptor_class") == 44);
    std.debug.assert(@bitOffsetOf(Segment, "base_high") == 56);

    std.debug.assert(@bitSizeOf(System) == 128);
    std.debug.assert(@sizeOf(System) == 16);
    std.debug.assert(@bitOffsetOf(System, "kind") == 40);
    std.debug.assert(@bitOffsetOf(System, "base_upper") == 64);
    std.debug.assert(@bitOffsetOf(System, "_reserved_high") == 96);

    std.debug.assert(@bitSizeOf(Gate) == 128);
    std.debug.assert(@sizeOf(Gate) == 16);
    std.debug.assert(@bitOffsetOf(Gate, "ist") == 32);
    std.debug.assert(@bitOffsetOf(Gate, "kind") == 40);
    std.debug.assert(@bitOffsetOf(Gate, "offset_high") == 64);

    std.debug.assert(Segment != System);
    std.debug.assert(System != Gate);
}

test "model: descriptor raw representations preserve every bit" {
    try testing.expectEqual(@as(u64, 0), Segment.fromRaw(0).raw());
    try testing.expectEqual(std.math.maxInt(u64), Segment.fromRaw(std.math.maxInt(u64)).raw());
    try testing.expectEqual(@as(u64, 0xa5f3_5ca9_3d7e_1c42), Segment.fromRaw(0xa5f3_5ca9_3d7e_1c42).raw());

    inline for (.{ System, Gate }) |T| {
        try testing.expectEqual(@as(u128, 0), T.fromRaw(0).raw());
        try testing.expectEqual(std.math.maxInt(u128), T.fromRaw(std.math.maxInt(u128)).raw());
        try testing.expectEqual(
            @as(u128, 0xa5f3_5ca9_3d7e_1c42_94b7_e026_81da_f503),
            T.fromRaw(0xa5f3_5ca9_3d7e_1c42_94b7_e026_81da_f503).raw(),
        );
    }
}

test "model: segment constructors match architectural encodings" {
    const code = try Segment.init(0, 0xfffff, .code_execute_read, .{
        .long_mode = true,
        .granularity = true,
    });
    try testing.expectEqual(@as(u64, 0x00af_9a00_0000_ffff), code.raw());

    const data = try Segment.init(0, 0xfffff, .data_read_write, .{
        .default_operand_size = true,
        .granularity = true,
    });
    try testing.expectEqual(@as(u64, 0x00cf_9200_0000_ffff), data.raw());
}

test "model: system constructors match architectural encodings" {
    const base = 0x1234_5678_9abc_def0;
    try testing.expectEqual(
        @as(u128, 0x0000_0000_1234_5678_9a00_82bc_def0_ffff),
        (try System.init(base, 0xffff, .ldt, .{})).raw(),
    );
    try testing.expectEqual(
        @as(u128, 0x0000_0000_1234_5678_9a00_89bc_def0_0067),
        (try System.init(base, 0x67, .tss_available, .{})).raw(),
    );
    try testing.expectEqual(
        @as(u128, 0x0000_0000_1234_5678_9a00_8bbc_def0_0067),
        (try System.init(base, 0x67, .tss_busy, .{})).raw(),
    );
}

test "model: gate constructors match architectural encodings" {
    try testing.expectEqual(
        @as(u128, 0x0000_0000_1234_5678_9abc_8e03_0008_def0),
        (try Gate.init(0x1234_5678_9abc_def0, 0x8, .interrupt, .{ .ist = 3 })).raw(),
    );
    try testing.expectEqual(
        @as(u128, 0x0000_0000_fedc_ba98_7654_ef00_0010_3210),
        (try Gate.init(0xfedc_ba98_7654_3210, 0x10, .trap, .{ .privilege = .ring3 })).raw(),
    );
}

test "unit: segment construction and extraction cover kinds and boundaries" {
    inline for (@typeInfo(descriptors.SegmentKind).@"enum".fields) |field| {
        const kind: descriptors.SegmentKind = @enumFromInt(field.value);
        const executable = (field.value & 0x8) != 0;
        const value = try Segment.init(0x89ab_cdef, 0xfffff, kind, .{
            .privilege = .ring3,
            .available = true,
            .long_mode = executable,
            .granularity = true,
        });
        try testing.expectEqual(@as(u32, 0x89ab_cdef), value.base());
        try testing.expectEqual(@as(u20, 0xfffff), value.rawLimit());
        try testing.expectEqual(@as(u32, 0xffff_ffff), value.effectiveLimit());
        try testing.expectEqual(descriptors.PrivilegeLevel.ring3, value.privilege);
        try value.validate();
    }

    const byte_limit = try Segment.init(0, 0, .data_read_only, .{});
    try testing.expectEqual(@as(u20, 0), byte_limit.rawLimit());
    try testing.expectEqual(@as(u32, 0), byte_limit.effectiveLimit());
}

test "unit: system construction and extraction cover kinds and privilege levels" {
    inline for (.{ descriptors.SystemKind.ldt, .tss_available, .tss_busy }) |kind| {
        inline for (.{
            descriptors.PrivilegeLevel.ring0,
            .ring1,
            .ring2,
            .ring3,
        }) |privilege| {
            const value = try System.init(0x1234_5678_9abc_def0, 0xfffff, kind, .{
                .privilege = privilege,
                .available = true,
                .granularity = true,
            });
            try testing.expectEqual(@as(u64, 0x1234_5678_9abc_def0), value.base());
            try testing.expectEqual(@as(u20, 0xfffff), value.rawLimit());
            try testing.expectEqual(@as(u32, 0xffff_ffff), value.effectiveLimit());
            try testing.expectEqual(privilege, value.privilege);
            try value.validate();
        }
    }
}

test "unit: gate construction and extraction cover kinds and IST values" {
    inline for (.{ descriptors.GateKind.interrupt, .trap }) |kind| {
        inline for (0..8) |ist| {
            const value = try Gate.init(0x1234_5678_9abc_def0, 0x28, kind, .{
                .privilege = .ring2,
                .ist = ist,
            });
            try testing.expectEqual(@as(u64, 0x1234_5678_9abc_def0), value.offset());
            try testing.expectEqual(@as(u16, 0x28), value.selector());
            try testing.expectEqual(@as(u3, ist), value.ist);
            try value.validate();
        }
    }
}

test "unit: segment validation rejects fixed-class and mode violations" {
    try testing.expectError(error.ReservedBits, Segment.fromRaw(0).validate());

    const data_long = Segment.fromRaw(0x0030_9200_0000_0000);
    try testing.expectError(error.InvalidSegmentMode, data_long.validate());

    const code_long_default = Segment.fromRaw(0x0070_9a00_0000_0000);
    try testing.expectError(error.InvalidSegmentMode, code_long_default.validate());
}

test "unit: system validation rejects fixed, reserved, and unsupported encodings" {
    const valid = (try System.init(0, 0, .ldt, .{})).raw();
    try testing.expectError(error.ReservedBits, System.fromRaw(valid | (@as(u128, 1) << 44)).validate());
    try testing.expectError(error.ReservedBits, System.fromRaw(valid | (@as(u128, 1) << 53)).validate());
    try testing.expectError(error.ReservedBits, System.fromRaw(valid | (@as(u128, 1) << 96)).validate());

    const unsupported = (valid & ~(@as(u128, 0xf) << 40)) | (@as(u128, 1) << 40);
    try testing.expectError(error.InvalidSystemKind, System.fromRaw(unsupported).validate());
}

test "unit: gate validation rejects fixed, reserved, and unsupported encodings" {
    const valid = (try Gate.init(0, 0, .interrupt, .{})).raw();
    try testing.expectError(error.ReservedBits, Gate.fromRaw(valid | (@as(u128, 1) << 35)).validate());
    try testing.expectError(error.ReservedBits, Gate.fromRaw(valid | (@as(u128, 1) << 44)).validate());
    try testing.expectError(error.ReservedBits, Gate.fromRaw(valid | (@as(u128, 1) << 96)).validate());

    const unsupported = (valid & ~(@as(u128, 0xf) << 40)) | (@as(u128, 1) << 40);
    try testing.expectError(error.InvalidGateKind, Gate.fromRaw(unsupported).validate());
}
