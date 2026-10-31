const std = @import("std");
const target = @import("../target.zig");
const Table = @import("segment.zig").Table;

pub const GDTR = extern struct {
    limit: u16,
    base: u64 align(2),

    pub const alignment: usize = 2;

    const Self = @This();

    pub fn init() Self {
        return .{ .limit = 0, .base = 0 };
    }

    /// requires CPL 0 when CR4.umip is set.
    pub fn read() Self {
        comptime target.require();
        var value: Self = undefined;
        asm volatile ("sgdt %[ptr]"
            : [ptr] "=m" (value),
            :
            : .{ .memory = true });

        return value;
    }

    /// requires CPL 0.
    pub fn write(self: *const Self) void {
        comptime target.require();
        asm volatile ("lgdt (%[ptr])"
            :
            : [ptr] "r" (self),
            : .{ .memory = true });
    }

    comptime {
        std.debug.assert(@sizeOf(Self) == 10);
        std.debug.assert(@alignOf(Self) == alignment);
        std.debug.assert(@offsetOf(Self, "limit") == 0);
        std.debug.assert(@offsetOf(Self, "base") == 2);
    }
};

pub const IDTR = extern struct {
    limit: u16,
    base: u64 align(2),

    pub const alignment: usize = 2;

    const Self = @This();

    pub fn init() Self {
        return .{ .limit = 0, .base = 0 };
    }

    /// requires CPL 0 when CR4.umip is set.
    pub fn read() Self {
        comptime target.require();
        var value: Self = undefined;
        asm volatile ("sidt %[ptr]"
            : [ptr] "=m" (value),
            :
            : .{ .memory = true });

        return value;
    }

    /// requires CPL 0.
    pub fn write(self: *const Self) void {
        comptime target.require();
        asm volatile ("lidt (%[ptr])"
            :
            : [ptr] "r" (self),
            : .{ .memory = true });
    }

    comptime {
        std.debug.assert(@sizeOf(Self) == 10);
        std.debug.assert(@alignOf(Self) == alignment);
        std.debug.assert(@offsetOf(Self, "limit") == 0);
        std.debug.assert(@offsetOf(Self, "base") == 2);
    }
};

pub const TR = Selector("tr");
pub const LDTR = Selector("ldt");

fn Selector(comptime register: []const u8) type {
    return packed struct(u16) {
        rpl: u2,
        table: Table,
        index: u13,

        const Self = @This();

        pub fn init() Self {
            return from(0);
        }

        pub fn from(value: u16) Self {
            return @bitCast(value);
        }

        pub fn raw(self: Self) u16 {
            return @bitCast(self);
        }

        /// requires CPL 0 when CR4.umip is set.
        pub fn read() Self {
            comptime target.require();
            return from(asm volatile ("s" ++ register ++ " %[ret]"
                : [ret] "=r" (-> u16),
            ));
        }

        /// requires CPL 0 and a valid descriptor for the register.
        pub fn write(self: Self) void {
            comptime target.require();
            asm volatile ("l" ++ register ++ " %[sel]"
                :
                : [sel] "r" (self.raw()),
                : .{ .memory = true });
        }
    };
}

pub const unit = struct {
    test "task selector decodes privilege, table, and index" {
        const testing = std.testing;
        const value = TR.from(0xa5f7);

        try testing.expectEqual(@as(u2, 3), value.rpl);
        try testing.expectEqual(.ldt, value.table);
        try testing.expectEqual(@as(u13, 0x14be), value.index);
    }
};
