//! x86_64 SVM ISA wrappers. See `docs/specs/arch/x86_64/svm.md`.

const std = @import("std");

const target = @import("target.zig");

/// Strong physical-address value type covering the full 64-bit
/// physical-address space. Distinct from `Vmx.PhysAddr`.
pub const PhysAddr = enum(u64) {
    _,

    pub fn fromInt(value: u64) PhysAddr {
        return @enumFromInt(value);
    }

    pub fn raw(self: PhysAddr) u64 {
        return @intFromEnum(self);
    }
};

/// 4 KiB VMCB region per AMD APM Vol.2 §15.5. Split at the
/// architectural boundary between the control area (0x000-0x3FF) and
/// the state save area (0x400-0xFFF); field layouts inside each area
/// are downstream policy.
pub const VMCB = extern struct {
    control: [1024]u8 align(4096),
    state: [3072]u8,

    pub const alignment: usize = 4096;

    comptime {
        std.debug.assert(@sizeOf(VMCB) == 4096);
        std.debug.assert(@alignOf(VMCB) == 4096);
        std.debug.assert(@offsetOf(VMCB, "control") == 0);
        std.debug.assert(@offsetOf(VMCB, "state") == 0x400);
    }
};

/// Effects: enters guest execution; returns after `#VMEXIT`.
/// Privilege: CPL 0.
/// Faults: may `#GP` or `#UD`.
/// Clobbers: `memory`.
pub fn vmrun(vmcb: PhysAddr) void {
    target.ensureSupported();
    asm volatile ("vmrun"
        :
        : [vmcb] "{rax}" (@intFromEnum(vmcb)),
        : .{ .memory = true });
}

/// Effects: loads FS/GS/TR/LDTR selectors and SYSCALL/SYSENTER MSRs.
/// Privilege: CPL 0.
/// Clobbers: `memory`.
pub fn vmload(vmcb: PhysAddr) void {
    target.ensureSupported();
    asm volatile ("vmload"
        :
        : [vmcb] "{rax}" (@intFromEnum(vmcb)),
        : .{ .memory = true });
}

/// Effects: saves the same processor-state subset that `vmload` restores.
/// Privilege: CPL 0.
/// Clobbers: `memory`.
pub fn vmsave(vmcb: PhysAddr) void {
    target.ensureSupported();
    asm volatile ("vmsave"
        :
        : [vmcb] "{rax}" (@intFromEnum(vmcb)),
        : .{ .memory = true });
}

/// Effects: sets the Global Interrupt Flag.
/// Privilege: CPL 0.
/// Requirements: `EFER.SVME = 1`.
/// Clobbers: `memory`.
pub fn stgi() void {
    target.ensureSupported();
    asm volatile ("stgi" ::: .{ .memory = true });
}

/// Effects: clears the Global Interrupt Flag, blocking maskable interrupts,
/// NMI, SMI, INIT, and #MC.
/// Privilege: CPL 0.
/// Requirements: `EFER.SVME = 1`.
/// Clobbers: `memory`.
pub fn clgi() void {
    target.ensureSupported();
    asm volatile ("clgi" ::: .{ .memory = true });
}

/// Effects: invalidates one TLB entry on the current logical processor.
/// Privilege: CPL 0.
/// Clobbers: `memory`.
pub fn invlpga(virt_addr: u64, asid: u32) void {
    target.ensureSupported();

    asm volatile ("invlpga"
        :
        : [addr] "{rax}" (virt_addr),
          [asid] "{ecx}" (asid),
        : .{ .memory = true });
}

/// Effects: clears processor state, measures the SL image, and transfers
/// control to that image (`noreturn`).
/// Privilege: CPL 0.
/// Clobbers: `memory`.
pub fn skinit(base: u32) noreturn {
    target.ensureSupported();

    asm volatile ("skinit"
        :
        : [base] "{eax}" (base),
        : .{ .memory = true });

    unreachable;
}
