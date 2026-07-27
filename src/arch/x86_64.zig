//! x86_64 architecture primitives. Spec: docs/specs/arch/x86_64/base.md.

pub const MSR = @import("x86_64/msr.zig").MSR;
pub const Port = @import("x86_64/port.zig").Port;

pub const cache = @import("x86_64/cache.zig");
pub const cpu = @import("x86_64/cpu.zig");
pub const cpuid = @import("x86_64/cpuid.zig");
pub const fence = @import("x86_64/fence.zig");
pub const interrupts = @import("x86_64/interrupts.zig");
pub const paging = @import("x86_64/paging.zig");
pub const privilege = @import("x86_64/privilege.zig");
pub const register = @import("x86_64/register.zig");
pub const supported = @import("x86_64/target.zig").supported;
pub const svm = @import("x86_64/svm.zig");
pub const vmx = @import("x86_64/vmx.zig");

pub const ioWait = @import("x86_64/port.zig").ioWait;
