//! x86_64 privilege helpers. Spec: docs/specs/arch/x86_64/base.md.

const target = @import("target.zig");
const segment = @import("register/segment.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

/// Bits 0-1 of the `cs` segment selector hold the architectural RPL/CPL,
/// so truncating `cs` to `u2` extracts the current privilege level.
/// Privilege: unprivileged.
pub fn currentLevel() u2 {
    if (!supported) @compileError(wrong_target);
    return @truncate(segment.cs.read());
}
