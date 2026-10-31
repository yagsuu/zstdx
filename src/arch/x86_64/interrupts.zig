//! x86_64 interrupt flag helpers. See `docs/specs/arch/x86_64.md`.

const target = @import("target.zig");
const rflags = @import("register/rflags.zig");

/// Privilege: CPL 0.
/// Faults: `#GP` at CPL > 0.
/// Clobbers: `memory`.
pub fn enable() void {
    comptime target.require();
    asm volatile ("sti" ::: .{ .memory = true });
}

/// Privilege: CPL 0.
/// Faults: `#GP` at CPL > 0.
/// Clobbers: `memory`.
pub fn disable() void {
    comptime target.require();
    asm volatile ("cli" ::: .{ .memory = true });
}

/// Returns whether the `IF` bit in `RFLAGS` is set.
/// Privilege: unprivileged.
pub fn enabled() bool {
    comptime target.require();
    return (rflags.read() & (1 << 9)) != 0;
}
