const target = @import("target.zig");

/// Ordering: Load fence; no prior-store visibility guarantee.
pub fn lfence() void {
    comptime target.require();
    asm volatile ("lfence" ::: .{ .memory = true });
}

/// Ordering: Store fence; no load ordering.
pub fn sfence() void {
    comptime target.require();
    asm volatile ("sfence" ::: .{ .memory = true });
}

/// Ordering: Load/store fence; non-serializing.
pub fn mfence() void {
    comptime target.require();
    asm volatile ("mfence" ::: .{ .memory = true });
}
