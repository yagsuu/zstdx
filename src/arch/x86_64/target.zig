//! x86_64 target gate. Spec: docs/specs/arch/x86_64/base.md.

const builtin = @import("builtin");

pub const supported: bool = builtin.cpu.arch == .x86_64;
pub const wrong_target_msg = "stdx.arch.x86_64: this operation requires an x86_64 target";

/// Fail compilation unless the target architecture is x86_64.
pub fn ensureSupported() void {
    if (!supported) @compileError(wrong_target_msg);
}
