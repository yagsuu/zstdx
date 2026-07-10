//! x86_64 debug-register access. Spec: docs/specs/arch/x86_64/register.md.

const target = @import("../target.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

fn DebugRegSlot(comptime name: []const u8) type {
    return struct {
        /// Execute `mov rNN, drN` and return the raw `u64`.
        /// Privilege: CPL 0.
        /// Faults: `#GP` at CPL > 0.
        /// Clobbers: registers only.
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%" ++ name ++ ", %[ret]"
                : [ret] "=r" (-> u64),
            );
        }

        /// Execute `mov drN, rNN` writing `value`.
        /// Privilege: CPL 0.
        /// Faults: `#GP` at CPL > 0.
        /// Clobbers: `memory`.
        pub fn write(value: u64) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%" ++ name
                :
                : [v] "r" (value),
                : .{ .memory = true });
        }
    };
}

pub const dr0 = DebugRegSlot("dr0");
pub const dr1 = DebugRegSlot("dr1");
pub const dr2 = DebugRegSlot("dr2");
pub const dr3 = DebugRegSlot("dr3");
pub const dr4 = DebugRegSlot("dr4");
pub const dr5 = DebugRegSlot("dr5");
pub const dr6 = DebugRegSlot("dr6");
pub const dr7 = DebugRegSlot("dr7");
