//! x86_64 raw fence instructions. Spec: docs/specs/arch/x86_64/base.md.

const target = @import("target.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

/// Execute `lfence`.
/// Privilege: unprivileged.
/// Ordering: architectural load fence.
/// Clobbers: `memory`.
pub fn lfence() void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("lfence" ::: .{ .memory = true });
}

/// Execute `sfence`.
/// Privilege: unprivileged.
/// Ordering: architectural store fence.
/// Clobbers: `memory`.
pub fn sfence() void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("sfence" ::: .{ .memory = true });
}

/// Execute `mfence`.
/// Privilege: unprivileged.
/// Ordering: architectural full memory fence.
/// Clobbers: `memory`.
pub fn mfence() void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("mfence" ::: .{ .memory = true });
}
