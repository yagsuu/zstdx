const std = @import("std");

const bits = @import("bits");
const target = @import("../target.zig");

pub const DR0 = enum(u64) {
    _,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @fromBackingInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @backingInt(self);
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
        return @fromBackingInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @backingInt(self);
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
        return @fromBackingInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @backingInt(self);
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
        return @fromBackingInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @backingInt(self);
    }

    pub fn read() Self {
        return Impl.read(Self, "dr3");
    }

    pub fn write(self: Self) void {
        Impl.write("dr3", self);
    }
};

/// Aliases DR6 when CR4.DE = 0.
/// Faults: #UD on access when CR4.DE = 1.
pub const DR4 = enum(u64) {
    _,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @fromBackingInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @backingInt(self);
    }

    pub fn read() Self {
        return Impl.read(Self, "dr4");
    }

    pub fn write(self: Self) void {
        Impl.write("dr4", self);
    }
};

/// Aliases DR7 when CR4.DE = 0.
/// Faults: #UD on access when CR4.DE = 1.
pub const DR5 = enum(u64) {
    _,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @fromBackingInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @backingInt(self);
    }

    pub fn read() Self {
        return Impl.read(Self, "dr5");
    }

    pub fn write(self: Self) void {
        Impl.write("dr5", self);
    }
};

pub const DR6 = struct {
    pub fn read() DebugStatus.Word {
        return Impl.read(DebugStatus, "dr6");
    }

    pub fn write(status: DebugStatus.Word) void {
        Impl.write("dr6", status);
    }
};

/// Raw DR6 status; multiple cause bits can be set together.
pub const DebugStatus = struct {
    const Fields = bits.BitField(u64, .{
        .br0 = .{ .type = bool, .access = .ro },
        .br1 = .{ .type = bool, .access = .ro },
        .br2 = .{ .type = bool, .access = .ro },
        .br3 = .{ .type = bool, .access = .ro },
        ._reserved_4 = .{ .type = u7, .access = .reserved },
        .bus_lock_not_detected = .{ .type = bool, .access = .ro },
        ._reserved_12 = .{ .type = bool, .access = .reserved },
        .debug_register_access = .{ .type = bool, .access = .ro },
        .single_step = .{ .type = bool, .access = .ro },
        .task_switch = .{ .type = bool, .access = .ro },
        .outside_rtm = .{ .type = bool, .access = .ro },
        ._reserved_17 = .{ .type = u47, .access = .reserved },
    });

    pub const __StdxBitField = Fields.Metadata;

    pub const Int = Fields.Int;
    pub const Word = Fields.Word;

    pub const masks = Fields.masks;

    pub const default = Fields.default;
    pub const init = Fields.init;
    pub const from = Fields.from;
    pub const raw = Fields.raw;
    pub const encode = Fields.encode;
    pub const replace = Fields.replace;
    pub const mask = Fields.mask;
};

pub const DR7 = struct {
    const Fields = bits.BitField(u64, .{
        .local_0 = bool,
        .global_0 = bool,
        .local_1 = bool,
        .global_1 = bool,
        .local_2 = bool,
        .global_2 = bool,
        .local_3 = bool,
        .global_3 = bool,
        .local_exact = bool,
        .global_exact = bool,
        .fixed_one = .{ .type = bool, .access = .reserved, .default = true },
        ._reserved_12 = .{ .offset = 12, .type = bool, .access = .reserved },
        .general_detect = bool,
        ._reserved_14 = .{ .type = u2, .access = .reserved },
        .br0 = Breakpoint,
        .br1 = Breakpoint,
        .br2 = Breakpoint,
        .br3 = Breakpoint,
        ._reserved_32 = .{ .type = u32, .access = .reserved },
    });

    pub const __StdxBitField = Fields.Metadata;

    pub const Int = Fields.Int;
    pub const Word = Fields.Word;

    pub const masks = Fields.masks;

    pub const default = Fields.default;
    pub const init = Fields.init;
    pub const from = Fields.from;
    pub const raw = Fields.raw;
    pub const encode = Fields.encode;
    pub const replace = Fields.replace;
    pub const mask = Fields.mask;

    pub fn read() Word {
        return Impl.read(DR7, "dr7");
    }

    pub fn write(word: Word) void {
        Impl.write("dr7", word);
    }
};

pub const Breakpoint = struct {
    const Fields = bits.BitField(u4, .{
        .condition = Condition,
        .length = u2,
    });

    pub const __StdxBitField = Fields.Metadata;

    pub const Int = Fields.Int;
    pub const Word = Fields.Word;

    pub const masks = Fields.masks;

    pub const default = Fields.default;
    pub const init = Fields.init;
    pub const from = Fields.from;
    pub const raw = Fields.raw;
    pub const encode = Fields.encode;
    pub const replace = Fields.replace;
    pub const mask = Fields.mask;

    pub const Condition = enum(u2) {
        execute = 0b00,
        write = 0b01,
        io = 0b10,
        read_write = 0b11,
    };
};

const Impl = struct {
    fn read(comptime T: type, comptime name: []const u8) if (@typeInfo(T) == .@"enum") T else T.Word {
        comptime target.require();
        return T.from(asm volatile ("mov %%" ++ name ++ ", %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    fn write(comptime name: []const u8, value: anytype) void {
        comptime target.require();
        const raw: u64 = if (@typeInfo(@TypeOf(value)) == .@"enum") @backingInt(value) else @bitCast(value);
        asm volatile ("mov %[v], %%" ++ name
            :
            : [v] "r" (raw),
            : .{ .memory = true });
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "debug register defaults and policies preserve raw status and nested fields" {
        try testing.expectEqual(@as(u64, 0), DebugStatus.raw(DebugStatus.default()));
        try testing.expectEqual(@as(u64, 0), DebugStatus.masks.assign);
        try testing.expectEqual(@as(u64, 0), DebugStatus.masks.clear);
        try testing.expectEqual(@as(u64, 0), DebugStatus.masks.unnamed);
        try testing.expectEqual(@as(u64, 1 << 10), DR7.raw(DR7.default()));
        try testing.expectEqual(@as(u64, 1 << 11), DR7.masks.unnamed);
        try testing.expectEqual(@as(u4, 0xf), Breakpoint.masks.assign);
        try testing.expectEqual(@as(u64, 0xffff0000), DR7.masks.assign & DR7.mask(.{ .br0, .br1, .br2, .br3 }));

        const status = DebugStatus.from(std.math.maxInt(u64));
        try testing.expectEqual(DebugStatus.raw(status), DebugStatus.raw(DebugStatus.replace(status, .{})));

        const snapshot = DR7.from(std.math.maxInt(u64));
        const updated = DR7.replace(snapshot, .{ .br0 = Breakpoint.default(), .general_detect = false });
        try testing.expectEqual(DR7.raw(snapshot) & ~DR7.masks.assign, DR7.raw(updated) & ~DR7.masks.assign);
        try testing.expectEqual(@as(u4, 0), Breakpoint.raw(updated.br0));
        try testing.expect(!updated.general_detect);
    }

    test "debug status and breakpoint fields retain architectural encodings" {
        const status = DebugStatus.from((1 << 3) | (1 << 13) | (1 << 14) | (1 << 15));

        var control = DR7.default();
        control.br0 = .{ .condition = .read_write, .length = 2 };
        control.br3 = Breakpoint.from(0b0110);
        control.general_detect = true;

        try testing.expect(status.br3);
        try testing.expect(!status.bus_lock_not_detected);
        try testing.expect(status.debug_register_access);
        try testing.expect(status.single_step);
        try testing.expect(status.task_switch);
        try testing.expect(!status.outside_rtm);
        try testing.expectEqual(@as(u64, (1 << 10) | (1 << 13) | (0b1011 << 16) | (0b0110 << 28)), DR7.raw(control));
        try testing.expect(control.fixed_one);
        try testing.expect(!DR7.from(0).fixed_one);
        try testing.expectEqual(@as(u4, 0b0110), Breakpoint.raw(control.br3));
        try testing.expectEqual(Breakpoint.Condition.io, control.br3.condition);
    }

    test "debug status preserves raw polarity and context bits" {
        const raw: u64 = (1 << 63) | (1 << 16) | (1 << 14) | (1 << 11) | 0b0101;
        const status = DebugStatus.from(raw);

        try testing.expect(status.br0 and status.br2);
        try testing.expect(!status.br1 and !status.br3);
        try testing.expect(status.single_step);
        try testing.expect(!status.debug_register_access and !status.task_switch);
        try testing.expect(status.bus_lock_not_detected);
        try testing.expect(status.outside_rtm);
        try testing.expectEqual(raw, DebugStatus.raw(status));
    }

    test "breakpoint conditions retain all architectural encodings" {
        const conditions = [_]Breakpoint.Condition{ .execute, .write, .io, .read_write };

        for (conditions, 0..) |condition, encoding| {
            const breakpoint: Breakpoint.Word = .{ .condition = condition };

            try testing.expectEqual(@as(u4, @intCast(encoding)), Breakpoint.raw(breakpoint));
            try testing.expectEqual(condition, Breakpoint.from(@intCast(encoding)).condition);
        }
    }
};
