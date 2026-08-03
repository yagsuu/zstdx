//! x86_64 register access facade. Spec: docs/specs/arch/x86_64/register.md.

const control = @import("register/control.zig");
const efer_module = @import("register/efer.zig");
const rflags_module = @import("register/rflags.zig");
const segment = @import("register/segment.zig");
const descriptor = @import("register/descriptor.zig");
const debug = @import("register/debug.zig");

pub const cr0 = control.cr0;
pub const cr2 = control.cr2;
pub const cr3 = control.cr3;
pub const cr4 = control.cr4;
pub const cr8 = control.cr8;
pub const xcr0 = control.xcr0;
pub const rflags = rflags_module;
pub const efer = efer_module;
pub const cs = segment.cs;
pub const ds = segment.ds;
pub const es = segment.es;
pub const fs = segment.fs;
pub const gs = segment.gs;
pub const ss = segment.ss;
pub const fs_base = segment.fs_base;
pub const gs_base = segment.gs_base;
pub const gdtr = descriptor.gdtr;
pub const idtr = descriptor.idtr;
pub const tr = descriptor.tr;
pub const ldtr = descriptor.ldtr;
pub const dr0 = debug.dr0;
pub const dr1 = debug.dr1;
pub const dr2 = debug.dr2;
pub const dr3 = debug.dr3;
pub const dr4 = debug.dr4;
pub const dr5 = debug.dr5;
pub const dr6 = debug.dr6;
pub const dr7 = debug.dr7;
