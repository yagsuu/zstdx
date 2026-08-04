//! x86_64 privilege helpers. See `docs/specs/arch/x86_64/base.md`.

const target = @import("target.zig");
const segment = @import("register/segment.zig");

/// The `rpl` field of the current CS selector is the architectural CPL.
/// Privilege: unprivileged.
pub fn currentLevel() u2 {
    target.ensureSupported();
    return segment.cs.read().rpl;
}
