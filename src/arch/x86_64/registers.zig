const control = @import("register/control.zig");
const segment = @import("register/segment.zig");
const descriptor = @import("register/descriptor.zig");
const debug = @import("register/debug.zig");

pub const CR0 = control.CR0;
pub const CR2 = control.CR2;
pub const CR3 = control.CR3;
pub const CR4 = control.CR4;
pub const CR8 = control.CR8;
pub const XCR0 = control.XCR0;
pub const RFLAGS = @import("register/rflags.zig").RFLAGS;
pub const EFER = @import("register/efer.zig").EFER;

pub const Table = segment.Table;
pub const CS = segment.CS;
pub const DS = segment.DS;
pub const ES = segment.ES;
pub const FS = segment.FS;
pub const GS = segment.GS;
pub const SS = segment.SS;
pub const FsBase = segment.FsBase;
pub const GsBase = segment.GsBase;

pub const GDTR = descriptor.GDTR;
pub const IDTR = descriptor.IDTR;
pub const TR = descriptor.TR;
pub const LDTR = descriptor.LDTR;

pub const DR0 = debug.DR0;
pub const DR1 = debug.DR1;
pub const DR2 = debug.DR2;
pub const DR3 = debug.DR3;
pub const DR4 = debug.DR4;
pub const DR5 = debug.DR5;
pub const DR6 = debug.DR6;
pub const DR7 = debug.DR7;
