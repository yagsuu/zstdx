const std = @import("std");

const bits = @import("bits");
const layout = @import("layout");
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

    /// Privilege: CPL 0 when CR4.UMIP = 1.
    pub fn read() Self {
        comptime target.require();
        var value: Self = undefined;
        asm volatile ("sgdt %[ptr]"
            : [ptr] "=m" (value),
            :
            : .{ .memory = true });

        return value;
    }

    /// Privilege: CPL 0.
    pub fn write(self: *const Self) void {
        comptime target.require();
        asm volatile ("lgdt (%[ptr])"
            :
            : [ptr] "r" (self),
            : .{ .memory = true });
    }

    comptime {
        layout.assertLayout(Self, .{
            .size = 10,
            .alignment = alignment,
            .offsets = .{ .limit = 0, .base = 2 },
        });
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

    /// Privilege: CPL 0 when CR4.UMIP = 1.
    pub fn read() Self {
        comptime target.require();
        var value: Self = undefined;
        asm volatile ("sidt %[ptr]"
            : [ptr] "=m" (value),
            :
            : .{ .memory = true });

        return value;
    }

    /// Privilege: CPL 0.
    pub fn write(self: *const Self) void {
        comptime target.require();
        asm volatile ("lidt (%[ptr])"
            :
            : [ptr] "r" (self),
            : .{ .memory = true });
    }

    comptime {
        layout.assertLayout(Self, .{
            .size = 10,
            .alignment = alignment,
            .offsets = .{ .limit = 0, .base = 2 },
        });
    }
};

pub const TR = Selector("tr");
pub const LDTR = Selector("ldt");

fn Selector(comptime register: []const u8) type {
    return struct {
        const Fields = bits.BitField(u16, .{
            .rpl = u2,
            .table = Table,
            .index = u13,
        });

        pub const __StdxBitField = Fields.Metadata;
        pub const Int = Fields.Int;
        pub const Word = Fields.Word;
        pub const masks = Fields.masks;

        pub const init = Fields.init;
        pub const from = Fields.from;
        pub const raw = Fields.raw;
        pub const replace = Fields.replace;
        pub const encode = Fields.encode;
        pub const mask = Fields.mask;

        /// Privilege: CPL 0 when CR4.UMIP = 1.
        pub fn read() Word {
            comptime target.require();
            return from(asm volatile ("s" ++ register ++ " %[ret]"
                : [ret] "=r" (-> u16),
            ));
        }

        /// Privilege: CPL 0.
        /// Inputs: Valid descriptor for the register.
        pub fn write(word: Word) void {
            comptime target.require();
            asm volatile ("l" ++ register ++ " %[sel]"
                :
                : [sel] "r" (raw(word)),
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
        try testing.expectEqual(@as(u16, 0xa5f7), TR.raw(value));
        const selector = LDTR.replace(LDTR.init(), .{
            .rpl = 3,
            .table = .ldt,
            .index = 0x14be,
        });
        try testing.expectEqual(@as(u16, 0xa5f7), LDTR.raw(selector));
    }
};
