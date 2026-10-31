const target = @import("target.zig");

/// does not ensure prior stores are globally visible.
pub fn lfence() void {
    comptime target.require();
    asm volatile ("lfence" ::: .{ .memory = true });
}

/// does not order loads.
pub fn sfence() void {
    comptime target.require();
    asm volatile ("sfence" ::: .{ .memory = true });
}

/// does not serialize the instruction stream.
pub fn mfence() void {
    comptime target.require();
    asm volatile ("mfence" ::: .{ .memory = true });
}
