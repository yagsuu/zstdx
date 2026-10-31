const std = @import("std");

pub const PrivilegeLevel = enum(u2) {
    ring0 = 0,
    ring1 = 1,
    ring2 = 2,
    ring3 = 3,
};

pub const Error = error{
    ReservedBits,
    InvalidSegmentMode,
    InvalidSystemKind,
    InvalidGateKind,
};

pub const Segment = packed struct(u64) {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    kind: Kind,
    descriptor_class: bool,
    privilege: PrivilegeLevel,
    present: bool,
    limit_high: u4,
    available: bool,
    long_mode: bool,
    default_operand_size: bool,
    granularity: bool,
    base_high: u8,

    pub const Kind = enum(u4) {
        data_read_only = 0x0,
        data_read_only_accessed = 0x1,
        data_read_write = 0x2,
        data_read_write_accessed = 0x3,
        data_read_only_expand_down = 0x4,
        data_read_only_expand_down_accessed = 0x5,
        data_read_write_expand_down = 0x6,
        data_read_write_expand_down_accessed = 0x7,
        code_execute_only = 0x8,
        code_execute_only_accessed = 0x9,
        code_execute_read = 0xa,
        code_execute_read_accessed = 0xb,
        code_execute_only_conforming = 0xc,
        code_execute_only_conforming_accessed = 0xd,
        code_execute_read_conforming = 0xe,
        code_execute_read_conforming_accessed = 0xf,
    };

    pub const Options = struct {
        privilege: PrivilegeLevel = .ring0,
        present: bool = true,
        available: bool = false,
        long_mode: bool = false,
        default_operand_size: bool = false,
        granularity: bool = false,
    };

    const Self = @This();

    pub fn init(address: u32, raw_limit: u20, kind: Kind, options: Options) Error!Self {
        const value: Self = .{
            .limit_low = @truncate(raw_limit),
            .base_low = @truncate(address),
            .base_middle = @truncate(address >> 16),
            .kind = kind,
            .descriptor_class = true,
            .privilege = options.privilege,
            .present = options.present,
            .limit_high = @truncate(raw_limit >> 16),
            .available = options.available,
            .long_mode = options.long_mode,
            .default_operand_size = options.default_operand_size,
            .granularity = options.granularity,
            .base_high = @truncate(address >> 24),
        };
        try value.validate();
        return value;
    }

    pub fn from(value: u64) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u64 {
        return @bitCast(self);
    }

    pub fn base(self: Self) u32 {
        return @as(u32, self.base_low) |
            (@as(u32, self.base_middle) << 16) |
            (@as(u32, self.base_high) << 24);
    }

    pub fn rawLimit(self: Self) u20 {
        return @as(u20, self.limit_low) | (@as(u20, self.limit_high) << 16);
    }

    /// inclusive byte limit.
    pub fn limit(self: Self) u32 {
        const raw_limit: u32 = self.rawLimit();
        if (self.granularity) {
            return (raw_limit << 12) | 0xfff;
        }
        return raw_limit;
    }

    pub fn validate(self: Self) Error!void {
        if (!self.descriptor_class) {
            return error.ReservedBits;
        }
        const executable = (@intFromEnum(self.kind) & 0x8) != 0;
        if (self.long_mode and (!executable or self.default_operand_size)) {
            return error.InvalidSegmentMode;
        }
    }
};

pub const System = packed struct(u128) {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    kind: Kind,
    descriptor_class: bool,
    privilege: PrivilegeLevel,
    present: bool,
    limit_high: u4,
    available: bool,
    _reserved_53: u2,
    granularity: bool,
    base_high: u8,
    base_upper: u32,
    _reserved_96: u32,

    pub const Kind = enum(u4) {
        ldt = 0x2,
        tss_available = 0x9,
        tss_busy = 0xb,
        _,
    };

    pub const Options = struct {
        privilege: PrivilegeLevel = .ring0,
        present: bool = true,
        available: bool = false,
        granularity: bool = false,
    };

    const Self = @This();

    pub fn init(address: u64, raw_limit: u20, kind: Kind, options: Options) Error!Self {
        const value: Self = .{
            .limit_low = @truncate(raw_limit),
            .base_low = @truncate(address),
            .base_middle = @truncate(address >> 16),
            .kind = kind,
            .descriptor_class = false,
            .privilege = options.privilege,
            .present = options.present,
            .limit_high = @truncate(raw_limit >> 16),
            .available = options.available,
            ._reserved_53 = 0,
            .granularity = options.granularity,
            .base_high = @truncate(address >> 24),
            .base_upper = @truncate(address >> 32),
            ._reserved_96 = 0,
        };
        try value.validate();
        return value;
    }

    pub fn from(value: u128) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u128 {
        return @bitCast(self);
    }

    pub fn base(self: Self) u64 {
        return @as(u64, self.base_low) |
            (@as(u64, self.base_middle) << 16) |
            (@as(u64, self.base_high) << 24) |
            (@as(u64, self.base_upper) << 32);
    }

    pub fn rawLimit(self: Self) u20 {
        return @as(u20, self.limit_low) | (@as(u20, self.limit_high) << 16);
    }

    /// inclusive byte limit.
    pub fn limit(self: Self) u32 {
        const raw_limit: u32 = self.rawLimit();
        if (self.granularity) {
            return (raw_limit << 12) | 0xfff;
        }
        return raw_limit;
    }

    pub fn validate(self: Self) Error!void {
        if (self.descriptor_class or self._reserved_53 != 0 or self._reserved_96 != 0) {
            return error.ReservedBits;
        }
        switch (self.kind) {
            .ldt, .tss_available, .tss_busy => {},
            _ => return error.InvalidSystemKind,
        }
    }
};

pub const Gate = packed struct(u128) {
    offset_low: u16,
    selector: u16,
    ist: u3,
    _reserved_35: u5,
    kind: Kind,
    descriptor_class: bool,
    privilege: PrivilegeLevel,
    present: bool,
    offset_middle: u16,
    offset_high: u32,
    _reserved_96: u32,

    pub const Kind = enum(u4) {
        interrupt = 0xe,
        trap = 0xf,
        _,
    };

    pub const Options = struct {
        privilege: PrivilegeLevel = .ring0,
        present: bool = true,
        ist: u3 = 0,
    };

    const Self = @This();

    pub fn init(address: u64, selector: u16, kind: Kind, options: Options) Error!Self {
        const value: Self = .{
            .offset_low = @truncate(address),
            .selector = selector,
            .ist = options.ist,
            ._reserved_35 = 0,
            .kind = kind,
            .descriptor_class = false,
            .privilege = options.privilege,
            .present = options.present,
            .offset_middle = @truncate(address >> 16),
            .offset_high = @truncate(address >> 32),
            ._reserved_96 = 0,
        };
        try value.validate();
        return value;
    }

    pub fn from(value: u128) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u128 {
        return @bitCast(self);
    }

    pub fn offset(self: Self) u64 {
        return @as(u64, self.offset_low) |
            (@as(u64, self.offset_middle) << 16) |
            (@as(u64, self.offset_high) << 32);
    }

    pub fn validate(self: Self) Error!void {
        if (self._reserved_35 != 0 or self.descriptor_class or self._reserved_96 != 0) {
            return error.ReservedBits;
        }
        switch (self.kind) {
            .interrupt, .trap => {},
            _ => return error.InvalidGateKind,
        }
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "segment encoding and limit extraction" {
        const code = try Segment.init(0, 0xfffff, .code_execute_read, .{
            .long_mode = true,
            .granularity = true,
        });
        const data = try Segment.init(0, 0xfffff, .data_read_write, .{
            .default_operand_size = true,
            .granularity = true,
        });
        const bytes = try Segment.init(0x89ab_cdef, 0x12345, .data_read_only, .{});

        try testing.expectEqual(@as(u64, 0x00af_9a00_0000_ffff), code.raw());
        try testing.expectEqual(@as(u64, 0x00cf_9200_0000_ffff), data.raw());
        try testing.expectEqual(@as(u32, 0xffff_ffff), code.limit());
        try testing.expectEqual(@as(u32, 0x89ab_cdef), bytes.base());
        try testing.expectEqual(@as(u20, 0x12345), bytes.rawLimit());
        try testing.expectEqual(@as(u32, 0x12345), bytes.limit());
    }

    test "system encoding and byte or page limits" {
        const ldt = try System.init(0x1234_5678_9abc_def0, 0xffff, .ldt, .{});
        const available = try System.init(0x1234_5678_9abc_def0, 0x67, .tss_available, .{});
        const busy = try System.init(0x1234_5678_9abc_def0, 0x67, .tss_busy, .{});
        const pages = try System.init(0, 0xfffff, .ldt, .{ .granularity = true });

        try testing.expectEqual(@as(u128, 0x0000_0000_1234_5678_9a00_82bc_def0_ffff), ldt.raw());
        try testing.expectEqual(@as(u128, 0x0000_0000_1234_5678_9a00_89bc_def0_0067), available.raw());
        try testing.expectEqual(@as(u128, 0x0000_0000_1234_5678_9a00_8bbc_def0_0067), busy.raw());
        try testing.expectEqual(@as(u64, 0x1234_5678_9abc_def0), ldt.base());
        try testing.expectEqual(@as(u20, 0xffff), ldt.rawLimit());
        try testing.expectEqual(@as(u32, 0xffff), ldt.limit());
        try testing.expectEqual(@as(u32, 0xffff_ffff), pages.limit());
    }

    test "gate encoding and target extraction" {
        const interrupt = try Gate.init(0x1234_5678_9abc_def0, 0x8, .interrupt, .{ .ist = 3 });
        const trap = try Gate.init(0xfedc_ba98_7654_3210, 0x10, .trap, .{ .privilege = .ring3 });

        try testing.expectEqual(@as(u128, 0x0000_0000_1234_5678_9abc_8e03_0008_def0), interrupt.raw());
        try testing.expectEqual(@as(u128, 0x0000_0000_fedc_ba98_7654_ef00_0010_3210), trap.raw());
        try testing.expectEqual(@as(u64, 0x1234_5678_9abc_def0), interrupt.offset());
        try testing.expectEqual(@as(u16, 0x8), interrupt.selector);
        try testing.expectEqual(@as(u3, 3), interrupt.ist);
    }

    test "validation rejects fixed fields and invalid modes or kinds" {
        try testing.expectError(error.ReservedBits, Segment.from(0).validate());
        try testing.expectError(error.InvalidSegmentMode, Segment.from(0x0030_9200_0000_0000).validate());
        try testing.expectError(error.InvalidSegmentMode, Segment.from(0x0070_9a00_0000_0000).validate());

        const system = (try System.init(0, 0, .ldt, .{})).raw();
        inline for (.{ 44, 53, 54, 96, 127 }) |bit| {
            try testing.expectError(error.ReservedBits, System.from(system | (@as(u128, 1) << bit)).validate());
        }
        const invalid_system = (system & ~(@as(u128, 0xf) << 40)) | (@as(u128, 1) << 40);
        try testing.expectError(error.InvalidSystemKind, System.from(invalid_system).validate());

        const gate = (try Gate.init(0, 0, .interrupt, .{})).raw();
        inline for (.{ 35, 39, 44, 96, 127 }) |bit| {
            try testing.expectError(error.ReservedBits, Gate.from(gate | (@as(u128, 1) << bit)).validate());
        }
        const invalid_gate = (gate & ~(@as(u128, 0xf) << 40)) | (@as(u128, 1) << 40);
        try testing.expectError(error.InvalidGateKind, Gate.from(invalid_gate).validate());
    }
};
