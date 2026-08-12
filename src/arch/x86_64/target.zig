//! x86_64 target gate. See `docs/specs/arch/x86_64.md`.

const builtin = @import("builtin");

pub const supported: bool = builtin.cpu.arch == .x86_64;
pub const wrong_target_msg = "stdx.arch.x86_64: this operation requires an x86_64 target";

pub fn ensureSupported() void {
    if (!supported) @compileError(wrong_target_msg);
}
