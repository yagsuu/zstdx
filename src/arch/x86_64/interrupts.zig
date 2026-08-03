//! x86_64 interrupt flag helpers. Spec: docs/specs/arch/x86_64/base.md.

const target = @import("target.zig");
const rflags = @import("register/rflags.zig");

/// Execute `sti`.
/// Privilege: CPL 0.
/// Faults: `#GP` at CPL > 0.
/// Clobbers: `memory`.
pub fn enable() void {
    target.ensureSupported();
    asm volatile ("sti" ::: .{ .memory = true });
}

/// Execute `cli`.
/// Privilege: CPL 0.
/// Faults: `#GP` at CPL > 0.
/// Clobbers: `memory`.
pub fn disable() void {
    target.ensureSupported();
    asm volatile ("cli" ::: .{ .memory = true });
}

/// Return whether the `IF` bit in `RFLAGS` is set.
/// Privilege: unprivileged.
pub fn enabled() bool {
    target.ensureSupported();
    return (rflags.read() & (1 << 9)) != 0;
}
