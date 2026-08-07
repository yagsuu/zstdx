//! IA-32e descriptor entry value types. See `docs/specs/arch/x86_64/descriptors.md`.

const std = @import("std");

pub const PrivilegeLevel = enum(u2) {
    ring0 = 0,
    ring1 = 1,
    ring2 = 2,
    ring3 = 3,
};

pub const SegmentKind = enum(u4) {
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

pub const SystemKind = enum(u4) {
    ldt = 0x2,
    tss_available = 0x9,
    tss_busy = 0xb,
    _,
};

pub const GateKind = enum(u4) {
    interrupt = 0xe,
    trap = 0xf,
    _,
};

pub const SegmentOptions = struct {
    privilege: PrivilegeLevel = .ring0,
    present: bool = true,
    available: bool = false,
    long_mode: bool = false,
    default_operand_size: bool = false,
    granularity: bool = false,
};

pub const SystemOptions = struct {
    privilege: PrivilegeLevel = .ring0,
    present: bool = true,
    available: bool = false,
    granularity: bool = false,
};

pub const GateOptions = struct {
    privilege: PrivilegeLevel = .ring0,
    present: bool = true,
    ist: u3 = 0,
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
    kind: SegmentKind,
    descriptor_class: bool,
    privilege: PrivilegeLevel,
    present: bool,
    limit_high: u4,
    available: bool,
    long_mode: bool,
    default_operand_size: bool,
    granularity: bool,
    base_high: u8,

    const Self = @This();

    pub fn init(base_value: u32, raw_limit: u20, kind: SegmentKind, options: SegmentOptions) Error!Self {
        const value: Self = .{
            .limit_low = @truncate(raw_limit),
            .base_low = @truncate(base_value),
            .base_middle = @truncate(base_value >> 16),
            .kind = kind,
            .descriptor_class = true,
            .privilege = options.privilege,
            .present = options.present,
            .limit_high = @truncate(raw_limit >> 16),
            .available = options.available,
            .long_mode = options.long_mode,
            .default_operand_size = options.default_operand_size,
            .granularity = options.granularity,
            .base_high = @truncate(base_value >> 24),
        };
        try value.validate();
        return value;
    }

    pub fn fromRaw(value: u64) Self {
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

    pub fn effectiveLimit(self: Self) u32 {
        const limit: u32 = self.rawLimit();
        return if (self.granularity) (limit << 12) | 0xfff else limit;
    }

    pub fn validate(self: Self) Error!void {
        if (!self.descriptor_class) return error.ReservedBits;
        const executable = (@intFromEnum(self.kind) & 0x8) != 0;
        if (self.long_mode and (!executable or self.default_operand_size)) {
            return error.InvalidSegmentMode;
        }
    }

    comptime {
        std.debug.assert(@bitSizeOf(Self) == 64);
        std.debug.assert(@sizeOf(Self) == 8);
        std.debug.assert(@bitOffsetOf(Self, "limit_low") == 0);
        std.debug.assert(@bitOffsetOf(Self, "base_low") == 16);
        std.debug.assert(@bitOffsetOf(Self, "base_middle") == 32);
        std.debug.assert(@bitOffsetOf(Self, "kind") == 40);
        std.debug.assert(@bitOffsetOf(Self, "descriptor_class") == 44);
        std.debug.assert(@bitOffsetOf(Self, "privilege") == 45);
        std.debug.assert(@bitOffsetOf(Self, "present") == 47);
        std.debug.assert(@bitOffsetOf(Self, "limit_high") == 48);
        std.debug.assert(@bitOffsetOf(Self, "available") == 52);
        std.debug.assert(@bitOffsetOf(Self, "long_mode") == 53);
        std.debug.assert(@bitOffsetOf(Self, "default_operand_size") == 54);
        std.debug.assert(@bitOffsetOf(Self, "granularity") == 55);
        std.debug.assert(@bitOffsetOf(Self, "base_high") == 56);
    }
};

pub const System = packed struct(u128) {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    kind: SystemKind,
    descriptor_class: bool,
    privilege: PrivilegeLevel,
    present: bool,
    limit_high: u4,
    available: bool,
    _reserved_low: u2,
    granularity: bool,
    base_high: u8,
    base_upper: u32,
    _reserved_high: u32,

    const Self = @This();

    pub fn init(base_value: u64, raw_limit: u20, kind: SystemKind, options: SystemOptions) Error!Self {
        const value: Self = .{
            .limit_low = @truncate(raw_limit),
            .base_low = @truncate(base_value),
            .base_middle = @truncate(base_value >> 16),
            .kind = kind,
            .descriptor_class = false,
            .privilege = options.privilege,
            .present = options.present,
            .limit_high = @truncate(raw_limit >> 16),
            .available = options.available,
            ._reserved_low = 0,
            .granularity = options.granularity,
            .base_high = @truncate(base_value >> 24),
            .base_upper = @truncate(base_value >> 32),
            ._reserved_high = 0,
        };
        try value.validate();
        return value;
    }

    pub fn fromRaw(value: u128) Self {
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

    pub fn effectiveLimit(self: Self) u32 {
        const limit: u32 = self.rawLimit();
        return if (self.granularity) (limit << 12) | 0xfff else limit;
    }

    pub fn validate(self: Self) Error!void {
        if (self.descriptor_class or self._reserved_low != 0 or self._reserved_high != 0) {
            return error.ReservedBits;
        }
        switch (self.kind) {
            .ldt, .tss_available, .tss_busy => {},
            _ => return error.InvalidSystemKind,
        }
    }

    comptime {
        std.debug.assert(@bitSizeOf(Self) == 128);
        std.debug.assert(@sizeOf(Self) == 16);
        std.debug.assert(@bitOffsetOf(Self, "limit_low") == 0);
        std.debug.assert(@bitOffsetOf(Self, "base_low") == 16);
        std.debug.assert(@bitOffsetOf(Self, "base_middle") == 32);
        std.debug.assert(@bitOffsetOf(Self, "kind") == 40);
        std.debug.assert(@bitOffsetOf(Self, "descriptor_class") == 44);
        std.debug.assert(@bitOffsetOf(Self, "privilege") == 45);
        std.debug.assert(@bitOffsetOf(Self, "present") == 47);
        std.debug.assert(@bitOffsetOf(Self, "limit_high") == 48);
        std.debug.assert(@bitOffsetOf(Self, "available") == 52);
        std.debug.assert(@bitOffsetOf(Self, "_reserved_low") == 53);
        std.debug.assert(@bitOffsetOf(Self, "granularity") == 55);
        std.debug.assert(@bitOffsetOf(Self, "base_high") == 56);
        std.debug.assert(@bitOffsetOf(Self, "base_upper") == 64);
        std.debug.assert(@bitOffsetOf(Self, "_reserved_high") == 96);
    }
};

pub const Gate = packed struct(u128) {
    offset_low: u16,
    segment_selector: u16,
    ist: u3,
    _reserved_low: u5,
    kind: GateKind,
    descriptor_class: bool,
    privilege: PrivilegeLevel,
    present: bool,
    offset_middle: u16,
    offset_high: u32,
    _reserved_high: u32,

    const Self = @This();

    pub fn init(offset_value: u64, selector_value: u16, kind: GateKind, options: GateOptions) Error!Self {
        const value: Self = .{
            .offset_low = @truncate(offset_value),
            .segment_selector = selector_value,
            .ist = options.ist,
            ._reserved_low = 0,
            .kind = kind,
            .descriptor_class = false,
            .privilege = options.privilege,
            .present = options.present,
            .offset_middle = @truncate(offset_value >> 16),
            .offset_high = @truncate(offset_value >> 32),
            ._reserved_high = 0,
        };
        try value.validate();
        return value;
    }

    pub fn fromRaw(value: u128) Self {
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

    pub fn selector(self: Self) u16 {
        return self.segment_selector;
    }

    pub fn validate(self: Self) Error!void {
        if (self._reserved_low != 0 or self.descriptor_class or self._reserved_high != 0) {
            return error.ReservedBits;
        }
        switch (self.kind) {
            .interrupt, .trap => {},
            _ => return error.InvalidGateKind,
        }
    }

    comptime {
        std.debug.assert(@bitSizeOf(Self) == 128);
        std.debug.assert(@sizeOf(Self) == 16);
        std.debug.assert(@bitOffsetOf(Self, "offset_low") == 0);
        std.debug.assert(@bitOffsetOf(Self, "segment_selector") == 16);
        std.debug.assert(@bitOffsetOf(Self, "ist") == 32);
        std.debug.assert(@bitOffsetOf(Self, "_reserved_low") == 35);
        std.debug.assert(@bitOffsetOf(Self, "kind") == 40);
        std.debug.assert(@bitOffsetOf(Self, "descriptor_class") == 44);
        std.debug.assert(@bitOffsetOf(Self, "privilege") == 45);
        std.debug.assert(@bitOffsetOf(Self, "present") == 47);
        std.debug.assert(@bitOffsetOf(Self, "offset_middle") == 48);
        std.debug.assert(@bitOffsetOf(Self, "offset_high") == 64);
        std.debug.assert(@bitOffsetOf(Self, "_reserved_high") == 96);
    }
};
