//! x86_64 privilege helpers. Spec: docs/specs/arch/x86_64/base.md.

const target = @import("target.zig");
const segment = @import("register/segment.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

/// The `rpl` field of the current CS selector is the architectural CPL.
/// Privilege: unprivileged.
pub fn currentLevel() u2 {
    if (!supported) @compileError(wrong_target);
    return segment.cs.read().rpl;
}
