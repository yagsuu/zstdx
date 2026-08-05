//! x86_64 interrupt flag helpers. See `docs/specs/arch/x86_64.md`.

const target = @import("target.zig");
const rflags = @import("register/rflags.zig");

/// Executes `sti`.
/// Privilege: CPL 0.
/// Faults: `#GP` at CPL > 0.
/// Clobbers: `memory`.
pub fn enable() void {
    target.ensureSupported();
    asm volatile ("sti" ::: .{ .memory = true });
}

/// Executes `cli`.
/// Privilege: CPL 0.
/// Faults: `#GP` at CPL > 0.
/// Clobbers: `memory`.
pub fn disable() void {
    target.ensureSupported();
    asm volatile ("cli" ::: .{ .memory = true });
}

/// Returns whether the `IF` bit in `RFLAGS` is set.
/// Privilege: unprivileged.
pub fn enabled() bool {
    target.ensureSupported();
    return (rflags.read() & (1 << 9)) != 0;
}
