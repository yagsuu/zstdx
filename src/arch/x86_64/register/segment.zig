const std = @import("std");
const target = @import("../target.zig");

pub const Table = enum(u1) { gdt, ldt };

pub const CS = packed struct(u16) {
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

    pub fn read() Self {
        comptime target.require();
        return from(asm volatile ("mov %%cs, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// the selector must reference a valid code segment for the far return.
    pub fn writeFarReturn(self: Self) void {
        comptime target.require();
        _ = asm volatile (
            \\pushq %[sel]
            \\leaq 1f(%%rip), %[tmp]
            \\pushq %[tmp]
            \\lretq
            \\1:
            : [tmp] "=&r" (-> u64),
            : [sel] "r" (@as(u64, self.raw())),
            : .{ .memory = true });
    }
};

pub const DS = Selector("ds");
pub const ES = Selector("es");
pub const FS = Selector("fs");
pub const GS = Selector("gs");
pub const SS = Selector("ss");

/// requires FSGSBASE support and CR4.fsgsbase_enable for read and write.
pub const FsBase = enum(u64) {
    _,

    const Self = @This();

    pub fn init() Self {
        return from(0);
    }

    pub fn from(value: u64) Self {
        return @enumFromInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @intFromEnum(self);
    }

    pub fn read() Self {
        comptime target.require();
        return from(asm volatile ("rdfsbase %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    pub fn write(self: Self) void {
        comptime target.require();
        asm volatile ("wrfsbase %[v]"
            :
            : [v] "r" (self.raw()),
            : .{ .memory = true });
    }
};

/// requires FSGSBASE support and CR4.fsgsbase_enable for read and write.
pub const GsBase = enum(u64) {
    _,

    const Self = @This();

    pub fn init() Self {
        return from(0);
    }

    pub fn from(value: u64) Self {
        return @enumFromInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @intFromEnum(self);
    }

    pub fn read() Self {
        comptime target.require();
        return from(asm volatile ("rdgsbase %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    pub fn write(self: Self) void {
        comptime target.require();
        asm volatile ("wrgsbase %[v]"
            :
            : [v] "r" (self.raw()),
            : .{ .memory = true });
    }

    /// requires CPL 0; exchanges the GS base with IA32_KERNEL_GS_BASE.
    pub fn swap() void {
        comptime target.require();
        asm volatile ("swapgs" ::: .{ .memory = true });
    }
};

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

        pub fn read() Self {
            comptime target.require();
            return from(asm volatile ("mov %%" ++ register ++ ", %[ret]"
                : [ret] "=r" (-> u16),
            ));
        }

        /// the selector must satisfy the segment's architectural access rules.
        pub fn write(self: Self) void {
            comptime target.require();
            asm volatile ("mov %[v], %%" ++ register
                :
                : [v] "r" (self.raw()),
                : .{ .memory = true });
        }
    };
}

pub const unit = struct {
    test "segment selectors decode fields and encode an LDT selector" {
        const testing = std.testing;
        const code = CS.from(0xa5f3);
        var data = DS.from(0);
        data.rpl = 3;
        data.table = .ldt;
        data.index = 0x1fff;

        try testing.expectEqual(@as(u2, 3), code.rpl);
        try testing.expectEqual(.gdt, code.table);
        try testing.expectEqual(@as(u13, 0x14be), code.index);
        try testing.expectEqual(@as(u16, 0xffff), data.raw());
    }
};
