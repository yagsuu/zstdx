//! x86_64 module index.

pub const cache = @import("x86_64/cache.zig");
pub const cpu = @import("x86_64/cpu.zig");
pub const cpuid = @import("x86_64/cpuid.zig");
pub const descriptors = @import("x86_64/descriptors.zig");
pub const fence = @import("x86_64/fence.zig");
pub const io = @import("x86_64/io.zig");
pub const irq = @import("x86_64/irq.zig");
pub const msr = @import("x86_64/msr.zig");
pub const paging = @import("x86_64/paging.zig");
pub const privilege = @import("x86_64/privilege.zig");
pub const registers = @import("x86_64/registers.zig");
pub const svm = @import("x86_64/svm.zig");
pub const vmx = @import("x86_64/vmx.zig");

pub const supported = @import("x86_64/target.zig").supported;
