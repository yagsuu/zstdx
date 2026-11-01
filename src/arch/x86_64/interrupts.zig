const target = @import("target.zig");
const RFLAGS = @import("register/rflags.zig").RFLAGS;

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
