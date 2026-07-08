//! x86_64 register access facade. Spec: docs/specs/arch/x86_64/register.md.

pub const control = @import("register/control.zig");
pub const debug = @import("register/debug.zig");
pub const descriptor = @import("register/descriptor.zig");
pub const rflags = @import("register/rflags.zig");
pub const segment = @import("register/segment.zig");
