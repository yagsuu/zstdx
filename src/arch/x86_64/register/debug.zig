//! register access requires privilege level 0 and can fault when DR7.GD is set.

const std = @import("std");

const target = @import("../target.zig");

pub const DR0 = enum(u64) {
    _,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @enumFromInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @intFromEnum(self);
    }

    pub fn read() Self {
        return Impl.read(Self, "dr0");
    }

    pub fn write(self: Self) void {
        Impl.write("dr0", self);
    }
};

pub const DR1 = enum(u64) {
    _,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @enumFromInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @intFromEnum(self);
    }

    pub fn read() Self {
        return Impl.read(Self, "dr1");
    }

    pub fn write(self: Self) void {
        Impl.write("dr1", self);
    }
};

pub const DR2 = enum(u64) {
    _,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @enumFromInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @intFromEnum(self);
    }

    pub fn read() Self {
        return Impl.read(Self, "dr2");
    }

    pub fn write(self: Self) void {
        Impl.write("dr2", self);
    }
};

pub const DR3 = enum(u64) {
    _,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @enumFromInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @intFromEnum(self);
    }

    pub fn read() Self {
        return Impl.read(Self, "dr3");
    }

    pub fn write(self: Self) void {
        Impl.write("dr3", self);
    }
};

/// aliases DR6 when CR4.DE is clear; access raises #UD when CR4.DE is set.
pub const DR4 = enum(u64) {
    _,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @enumFromInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @intFromEnum(self);
    }

    pub fn read() Self {
        return Impl.read(Self, "dr4");
    }

    pub fn write(self: Self) void {
        Impl.write("dr4", self);
    }
};

/// aliases DR7 when CR4.DE is clear; access raises #UD when CR4.DE is set.
pub const DR5 = enum(u64) {
    _,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @enumFromInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @intFromEnum(self);
    }

    pub fn read() Self {
        return Impl.read(Self, "dr5");
    }

    pub fn write(self: Self) void {
        Impl.write("dr5", self);
    }
};

pub const DR6 = packed struct(u64) {
    br0: bool,
    br1: bool,
    br2: bool,
    br3: bool,
    _reserved_4: u7,
    bus_lock_detect: bool,
    _reserved_12: bool,
    debug_register_access: bool,
    single_step: bool,
    task_switch: bool,
    restricted_transactional_memory: bool,
    _reserved_17: u47,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u64 {
        return @bitCast(self);
    }

    pub fn read() Self {
        return Impl.read(Self, "dr6");
    }

    pub fn write(self: Self) void {
        Impl.write("dr6", self);
    }
};

pub const DR7 = packed struct(u64) {
    local_0: bool,
    global_0: bool,
    local_1: bool,
    global_1: bool,
    local_2: bool,
    global_2: bool,
    local_3: bool,
    global_3: bool,
    local_exact: bool,
    global_exact: bool,
    fixed_one: bool,
    _unknown_11: bool,
    _reserved_12: bool,
    general_detect: bool,
    _reserved_14: u2,
    br0: Breakpoint,
    br1: Breakpoint,
    br2: Breakpoint,
    br3: Breakpoint,
    _reserved_32: u32,

    const Self = @This();

    pub fn init() Self {
        return Self.from(1 << 10);
    }

    pub fn from(value: u64) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u64 {
        return @bitCast(self);
    }

    pub fn read() Self {
        return Impl.read(Self, "dr7");
    }

    pub fn write(self: Self) void {
        Impl.write("dr7", self);
    }
};

pub const Breakpoint = packed struct(u4) {
    condition: u2,
    length: u2,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u4) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u4 {
        return @bitCast(self);
    }
};

const Impl = struct {
    fn read(comptime T: type, comptime name: []const u8) T {
        comptime target.require();
        return T.from(asm volatile ("mov %%" ++ name ++ ", %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    fn write(comptime name: []const u8, value: anytype) void {
        comptime target.require();
        asm volatile ("mov %[v], %%" ++ name
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "debug status and breakpoint fields retain architectural encodings" {
        const status = DR6.from((1 << 3) | (1 << 11) | (1 << 13) | (1 << 14) | (1 << 15) | (1 << 16));

        var control = DR7.init();
        control.br0 = .{ .condition = 3, .length = 2 };
        control.br3 = Breakpoint.from(0b0110);
        control.general_detect = true;

        try testing.expect(status.br3);
        try testing.expect(status.bus_lock_detect);
        try testing.expect(status.debug_register_access);
        try testing.expect(status.single_step);
        try testing.expect(status.task_switch);
        try testing.expect(status.restricted_transactional_memory);
        try testing.expectEqual(@as(u64, (1 << 10) | (1 << 13) | (0b1011 << 16) | (0b0110 << 28)), control.raw());
        try testing.expect(control.fixed_one);
        try testing.expect(!DR7.from(0).fixed_one);
        try testing.expectEqual(@as(u4, 0b0110), control.br3.raw());
    }
};
