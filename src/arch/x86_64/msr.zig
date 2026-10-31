const target = @import("target.zig");

pub const MSR = enum(u32) {
    IA32_TSC = 0x0000_0010,
    IA32_APIC_BASE = 0x0000_001b,
    IA32_FEATURE_CONTROL = 0x0000_003a,
    IA32_PAT = 0x0000_0277,
    IA32_VMX_BASIC = 0x0000_0480,
    IA32_VMX_PINBASED_CTLS = 0x0000_0481,
    IA32_VMX_PROCBASED_CTLS = 0x0000_0482,
    IA32_VMX_EXIT_CTLS = 0x0000_0483,
    IA32_VMX_ENTRY_CTLS = 0x0000_0484,
    IA32_EFER = 0xc000_0080,
    IA32_STAR = 0xc000_0081,
    IA32_LSTAR = 0xc000_0082,
    IA32_FMASK = 0xc000_0084,
    IA32_FS_BASE = 0xc000_0100,
    IA32_GS_BASE = 0xc000_0101,
    IA32_KERNEL_GS_BASE = 0xc000_0102,
    IA32_TSC_AUX = 0xc000_0103,
    VM_HSAVE_PA = 0xc001_0117,
    _,

    const Self = @This();

    pub fn from(value: u32) Self {
        return @enumFromInt(value);
    }

    pub fn raw(self: Self) u32 {
        return @intFromEnum(self);
    }
};

/// requires CPL 0; unsupported registers can cause #GP.
pub fn read(register: MSR) u64 {
    comptime target.require();

    var lo: u32 = undefined;
    var hi: u32 = undefined;
    asm volatile ("rdmsr"
        : [lo] "={eax}" (lo),
          [hi] "={edx}" (hi),
        : [idx] "{ecx}" (register.raw()),
        : .{ .memory = true });

    return (@as(u64, hi) << 32) | @as(u64, lo);
}

/// requires CPL 0; unsupported registers or invalid values can cause #GP.
pub fn write(register: MSR, value: u64) void {
    comptime target.require();

    const lo: u32 = @truncate(value);
    const hi: u32 = @truncate(value >> 32);
    asm volatile ("wrmsr"
        :
        : [idx] "{ecx}" (register.raw()),
          [lo] "{eax}" (lo),
          [hi] "{edx}" (hi),
        : .{ .memory = true });
}
