//! x86_64 RFLAGS access. Spec: docs/specs/arch/x86_64/register.md.

const std = @import("std");

pub const RFLAGS = packed struct(u64) {
    carry: bool,
    fixed_one: bool,
    parity: bool,
    _reserved0: bool,
    auxiliary_carry: bool,
    _reserved1: bool,
    zero: bool,
    sign: bool,
    trap: bool,
    interrupt_enable: bool,
    direction: bool,
    overflow: bool,
    iopl: u2,
    nested_task: bool,
    _reserved2: bool,
    resume_flag: bool,
    virtual_8086: bool,
    alignment_check: bool,
    virtual_interrupt: bool,
    virtual_interrupt_pending: bool,
    id: bool,
    _reserved3: u42,

    const Self = @This();

    pub fn init() Self {
        return fromInt(1 << 1);
    }

    pub fn fromInt(value: u64) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u64 {
        return @bitCast(self);
    }

    comptime {
        std.debug.assert(@bitSizeOf(Self) == 64);
        std.debug.assert(@sizeOf(Self) == 8);
    }
};

const target = @import("../target.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

/// Execute `pushfq; pop rNN` and return RFLAGS.
/// Privilege: unprivileged.
pub fn read() RFLAGS {
    if (!supported) @compileError(wrong_target);
    return RFLAGS.fromInt(asm volatile (
        \\pushfq
        \\popq %[ret]
        : [ret] "=r" (-> u64),
    ));
}

/// Push `value.raw()` and execute `popfq`.
/// Privilege: unprivileged.
/// Notes: bits the caller cannot modify at the current CPL are silently ignored.
/// Clobbers: `memory`, `cc`.
pub fn write(value: RFLAGS) void {
    if (!supported) @compileError(wrong_target);
    asm volatile (
        \\pushq %[v]
        \\popfq
        :
        : [v] "r" (value.raw()),
        : .{ .memory = true, .cc = true });
}
