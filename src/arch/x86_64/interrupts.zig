const target = @import("target.zig");
const RFLAGS = @import("register/rflags.zig").RFLAGS;

/// requires CPL 0; when IF was clear, interrupt recognition waits through the next instruction.
pub fn enable() void {
    comptime target.require();
    asm volatile ("sti" ::: .{ .memory = true });
}

/// requires CPL 0.
pub fn disable() void {
    comptime target.require();
    asm volatile ("cli" ::: .{ .memory = true });
}

pub fn enabled() bool {
    comptime target.require();
    return RFLAGS.read().interrupt_enable;
}
