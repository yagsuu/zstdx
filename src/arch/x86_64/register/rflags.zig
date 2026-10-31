const std = @import("std");
const target = @import("../target.zig");

pub const RFLAGS = packed struct(u64) {
    carry: bool,
    fixed_one: bool,
    parity: bool,
    _reserved_3: bool,
    auxiliary_carry: bool,
    _reserved_5: bool,
    zero: bool,
    sign: bool,
    trap: bool,
    interrupt_enable: bool,
    direction: bool,
    overflow: bool,
    iopl: u2,
    nested_task: bool,
    _reserved_15: bool,
    resume_flag: bool,
    virtual_8086: bool,
    alignment_check: bool,
    virtual_interrupt: bool,
    virtual_interrupt_pending: bool,
    id: bool,
    _reserved_22: u42,

    const Self = @This();

    pub fn init() Self {
        return from(1 << 1);
    }

    pub fn from(value: u64) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u64 {
        return @bitCast(self);
    }

    pub fn read() Self {
        comptime target.require();
        return Self.from(asm volatile (
            \\pushfq
            \\popq %[ret]
            : [ret] "=r" (-> u64),
        ));
    }

    /// bits that the current CPL cannot modify remain unchanged.
    pub fn write(self: Self) void {
        comptime target.require();
        asm volatile (
            \\pushq %[v]
            \\popfq
            :
            : [v] "r" (self.raw()),
            : .{ .memory = true, .cc = true });
    }
};

pub const unit = struct {
    test "RFLAGS preserves raw bits and encodes architectural flags" {
        const testing = std.testing;
        const value = RFLAGS.from(0xa5f3_5ca9_3d7e_1c42);
        const interrupt = RFLAGS.from(1 << 9);

        try testing.expectEqual(@as(u64, 0xa5f3_5ca9_3d7e_1c42), value.raw());
        try testing.expect(interrupt.interrupt_enable);
        try testing.expectEqual(@as(u2, 3), RFLAGS.from(3 << 12).iopl);
    }
};
