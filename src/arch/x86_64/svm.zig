const std = @import("std");
const addr = @import("addr");

const target = @import("target.zig");

pub const VMCB = extern struct {
    control: [1024]u8 align(4096),
    save: [3072]u8,

    pub const alignment: usize = 4096;

    comptime {
        std.debug.assert(@sizeOf(@This()) == 4096);
        std.debug.assert(@alignOf(@This()) == 4096);
        std.debug.assert(@offsetOf(@This(), "control") == 0);
        std.debug.assert(@offsetOf(@This(), "save") == 0x400);
    }
};

/// requires CPL 0 and EFER.SVME; returns after VMEXIT.
/// entry/exit assembly must preserve compiler-live registers; this wrapper does not save guest GPR/SIMD state.
/// the VMCB physical address must be supported and 4-KiB aligned.
pub fn vmrun(vmcb: addr.PhysAddr) void {
    comptime target.require();
    asm volatile ("vmrun"
        :
        : [vmcb] "{rax}" (vmcb.raw()),
        : .{ .memory = true });
}

/// requires CPL 0 and EFER.SVME; loads the VMCB's additional host or guest state.
/// the VMCB physical address must be supported and 4-KiB aligned.
pub fn vmload(vmcb: addr.PhysAddr) void {
    comptime target.require();
    asm volatile ("vmload"
        :
        : [vmcb] "{rax}" (vmcb.raw()),
        : .{ .memory = true });
}

/// requires CPL 0 and EFER.SVME; saves the state subset restored by VMLOAD.
/// the VMCB physical address must be supported and 4-KiB aligned.
pub fn vmsave(vmcb: addr.PhysAddr) void {
    comptime target.require();
    asm volatile ("vmsave"
        :
        : [vmcb] "{rax}" (vmcb.raw()),
        : .{ .memory = true });
}

/// requires CPL 0 and EFER.SVME.
pub fn stgi() void {
    comptime target.require();
    asm volatile ("stgi" ::: .{ .memory = true });
}

/// requires CPL 0 and EFER.SVME.
pub fn clgi() void {
    comptime target.require();
    asm volatile ("clgi" ::: .{ .memory = true });
}

/// requires CPL 0 and EFER.SVME.
pub fn invlpga(address: addr.VirtAddr, asid: u32) void {
    comptime target.require();

    asm volatile ("invlpga"
        :
        : [address] "{rax}" (address.raw()),
          [asid] "{ecx}" (asid),
        : .{ .memory = true });
}

/// requires CPL 0; transfers control to the measured secure loader image.
/// address is a 64-KiB-aligned physical address below 4 GiB.
pub fn skinit(address: u32) noreturn {
    comptime target.require();

    asm volatile ("skinit"
        :
        : [address] "{eax}" (address),
        : .{ .memory = true });

    unreachable;
}
