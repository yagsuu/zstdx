//! x86_64 interrupt flag helpers. Spec: docs/specs/arch/x86_64/base.md.

const target = @import("target.zig");
const rflags = @import("register/rflags.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

/// Execute `sti`.
/// Privilege: CPL 0.
/// Faults: `#GP` at CPL > 0.
/// Clobbers: `memory`.
pub fn enable() void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("sti" ::: .{ .memory = true });
}

/// Execute `cli`.
/// Privilege: CPL 0.
/// Faults: `#GP` at CPL > 0.
/// Clobbers: `memory`.
pub fn disable() void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("cli" ::: .{ .memory = true });
}

/// Whether the `IF` bit in `RFLAGS` is set.
/// Privilege: unprivileged.
pub fn enabled() bool {
    if (!supported) @compileError(wrong_target);
    return (rflags.read() & (1 << 9)) != 0;
}
