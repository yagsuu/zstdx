//! x86_64 raw fence instructions. See `docs/specs/arch/x86_64.md`.

const target = @import("target.zig");

/// Privilege: unprivileged.
/// Ordering: architectural load fence.
/// Clobbers: `memory`.
pub fn lfence() void {
    comptime target.require();
    asm volatile ("lfence" ::: .{ .memory = true });
}

/// Privilege: unprivileged.
/// Ordering: architectural store fence.
/// Clobbers: `memory`.
pub fn sfence() void {
    comptime target.require();
    asm volatile ("sfence" ::: .{ .memory = true });
}

/// Privilege: unprivileged.
/// Ordering: architectural full memory fence.
/// Clobbers: `memory`.
pub fn mfence() void {
    comptime target.require();
    asm volatile ("mfence" ::: .{ .memory = true });
}
