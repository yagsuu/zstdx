//! x86_64 RFLAGS access. Spec: docs/specs/arch/x86_64/register.md.

const target = @import("../target.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

/// Execute `pushfq; pop rNN` and return the value as `u64`.
/// Privilege: unprivileged.
pub fn read() u64 {
    if (!supported) @compileError(wrong_target);
    return asm volatile (
        \\pushfq
        \\popq %[ret]
        : [ret] "=r" (-> u64),
    );
}

/// Push `value` and execute `popfq`.
/// Privilege: unprivileged.
/// Notes: bits the caller cannot modify at the current CPL are silently ignored.
/// Clobbers: `memory`, `cc`.
pub fn write(value: u64) void {
    if (!supported) @compileError(wrong_target);
    asm volatile (
        \\pushq %[v]
        \\popfq
        :
        : [v] "r" (value),
        : .{ .memory = true, .cc = true });
}
