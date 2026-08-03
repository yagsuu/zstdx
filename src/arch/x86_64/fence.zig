//! x86_64 raw fence instructions. Spec: docs/specs/arch/x86_64/base.md.

const target = @import("target.zig");

/// Execute `lfence`.
/// Privilege: unprivileged.
/// Ordering: architectural load fence.
/// Clobbers: `memory`.
pub fn lfence() void {
    target.ensureSupported();
    asm volatile ("lfence" ::: .{ .memory = true });
}

/// Execute `sfence`.
/// Privilege: unprivileged.
/// Ordering: architectural store fence.
/// Clobbers: `memory`.
pub fn sfence() void {
    target.ensureSupported();
    asm volatile ("sfence" ::: .{ .memory = true });
}

/// Execute `mfence`.
/// Privilege: unprivileged.
/// Ordering: architectural full memory fence.
/// Clobbers: `memory`.
pub fn mfence() void {
    target.ensureSupported();
    asm volatile ("mfence" ::: .{ .memory = true });
}
