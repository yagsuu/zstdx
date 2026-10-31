//! compile-time x86_64 target requirement.

const builtin = @import("builtin");

pub const supported: bool = builtin.cpu.arch == .x86_64;

pub fn require() void {
    if (!supported) {
        @compileError("stdx.arch.x86_64: this operation requires an x86_64 target");
    }
}
