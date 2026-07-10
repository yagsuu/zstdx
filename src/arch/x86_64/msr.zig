//! x86_64 MSR primitive. Spec: docs/specs/arch/x86_64/base.md.

const target = @import("target.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

pub const Msr = enum(u32) {
    /// IA32_TSC, time-stamp counter.
    tsc = 0x0000_0010,
    /// IA32_APIC_BASE, local APIC base and enable state.
    apic_base = 0x0000_001b,
    /// IA32_FEATURE_CONTROL, VMX/SMX feature lock and enable bits.
    feature_control = 0x0000_003a,
    /// IA32_PAT, page attribute table.
    pat = 0x0000_0277,
    /// IA32_VMX_BASIC, VMX capability summary.
    vmx_basic = 0x0000_0480,
    /// IA32_VMX_PINBASED_CTLS, VMX pin-based control constraints.
    vmx_pinbased_ctls = 0x0000_0481,
    /// IA32_VMX_PROCBASED_CTLS, VMX primary processor-control constraints.
    vmx_procbased_ctls = 0x0000_0482,
    /// IA32_VMX_EXIT_CTLS, VMX exit-control constraints.
    vmx_exit_ctls = 0x0000_0483,
    /// IA32_VMX_ENTRY_CTLS, VMX entry-control constraints.
    vmx_entry_ctls = 0x0000_0484,
    /// IA32_EFER, extended feature enable register.
    efer = 0xc000_0080,
    /// IA32_STAR, syscall/sysret segment selectors and target state.
    star = 0xc000_0081,
    /// IA32_LSTAR, 64-bit syscall entry point.
    lstar = 0xc000_0082,
    /// IA32_FMASK, syscall RFLAGS mask.
    fmask = 0xc000_0084,
    /// IA32_FS_BASE, FS segment base.
    fs_base = 0xc000_0100,
    /// IA32_GS_BASE, GS segment base.
    gs_base = 0xc000_0101,
    /// IA32_KERNEL_GS_BASE, swapgs kernel GS base.
    kernel_gs_base = 0xc000_0102,
    /// IA32_TSC_AUX, auxiliary value returned by rdtscp.
    tsc_aux = 0xc000_0103,
    /// VM_HSAVE_PA, AMD host-save physical address.
    vm_hsave_pa = 0xc001_0117,

    _,

    pub fn fromInt(value: u32) Msr {
        return @enumFromInt(value);
    }

    pub fn raw(self: Msr) u32 {
        return @intFromEnum(self);
    }

    /// Execute `rdmsr` against `self` and return the combined `edx:eax` as `u64`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` on unimplemented MSRs.
    /// Clobbers: `memory`.
    pub fn read(self: Msr) u64 {
        if (!supported) @compileError(wrong_target);
        var lo: u32 = undefined;
        var hi: u32 = undefined;
        asm volatile ("rdmsr"
            : [lo] "={eax}" (lo),
              [hi] "={edx}" (hi),
            : [idx] "{ecx}" (@intFromEnum(self)),
            : .{ .memory = true });
        return (@as(u64, hi) << 32) | @as(u64, lo);
    }

    /// Execute `wrmsr` against `self` with `edx:eax` split from `value`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` on unimplemented MSRs or reserved-bit violations.
    /// Clobbers: `memory`.
    pub fn write(self: Msr, value: u64) void {
        if (!supported) @compileError(wrong_target);
        const lo: u32 = @truncate(value);
        const hi: u32 = @truncate(value >> 32);
        asm volatile ("wrmsr"
            :
            : [idx] "{ecx}" (@intFromEnum(self)),
              [lo] "{eax}" (lo),
              [hi] "{edx}" (hi),
            : .{ .memory = true });
    }
};
