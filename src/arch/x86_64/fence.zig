//! x86_64 raw fence instructions. See `docs/specs/arch/x86_64/base.md`.

const target = @import("target.zig");

/// Executes `lfence`.
/// Privilege: unprivileged.
/// Ordering: architectural load fence.
/// Clobbers: `memory`.
pub fn lfence() void {
    target.ensureSupported();
    asm volatile ("lfence" ::: .{ .memory = true });
}

/// Executes `sfence`.
/// Privilege: unprivileged.
/// Ordering: architectural store fence.
/// Clobbers: `memory`.
pub fn sfence() void {
    target.ensureSupported();
    asm volatile ("sfence" ::: .{ .memory = true });
}

/// Executes `mfence`.
/// Privilege: unprivileged.
/// Ordering: architectural full memory fence.
/// Clobbers: `memory`.
pub fn mfence() void {
    target.ensureSupported();
    asm volatile ("mfence" ::: .{ .memory = true });
}
