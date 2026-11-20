const std = @import("std");

const target = @import("target.zig");

const RFLAGS = @import("register/rflags.zig").RFLAGS;

pub const Vector = enum(u8) {
    divide_error = 0,
    debug = 1,
    nmi = 2,
    breakpoint = 3,
    overflow = 4,
    bound_range = 5,
    invalid_opcode = 6,
    device_not_available = 7,
    double_fault = 8,
    coprocessor_segment_overrun = 9, // Legacy; reserved on current processors.
    invalid_tss = 10,
    segment_not_present = 11,
    stack_fault = 12,
    general_protection = 13,
    page_fault = 14,
    x87_floating_point = 16,
    alignment_check = 17,
    machine_check = 18,
    simd_floating_point = 19,
    virtualization = 20,
    control_protection = 21,
    hypervisor_injection = 28,
    vmm_communication = 29,
    security = 30,
    _,

    const Self = @This();

    pub fn from(value: u8) Self {
        return @fromBackingInt(value);
    }

    pub fn raw(self: Self) u8 {
        return @backingInt(self);
    }
};

/// Privilege: CPL 0.
/// Effects: One-instruction interrupt shadow when IF transitions 0 -> 1.
pub fn enable() void {
    comptime target.require();
    asm volatile ("sti" ::: .{ .memory = true });
}

/// Privilege: CPL 0.
pub fn disable() void {
    comptime target.require();
    asm volatile ("cli" ::: .{ .memory = true });
}

pub fn enabled() bool {
    comptime target.require();
    return RFLAGS.read().interrupt_enable;
}

pub const unit = struct {
    const testing = std.testing;

    test "unnamed vectors retain their numbers" {
        const unnamed = [_]u8{ 15, 22, 27, 31, 32, 128, 255 };

        for (unnamed) |number| {
            try testing.expectEqual(number, Vector.from(number).raw());
        }
    }
};
