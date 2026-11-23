//! AMD SVM operations.

const layout = @import("layout");
const addr = @import("addr");

const target = @import("target.zig");

pub const VMCB = extern struct {
    control: [1024]u8 align(4096),
    save: [3072]u8,

    pub const alignment: usize = 4096;

    comptime {
        layout.assertLayout(@This(), .{
            .size = 4096,
            .alignment = 4096,
            .offsets = .{ .control = 0, .save = 0x400 },
        });
    }
};

/// Requires:
/// - EFER.SVME.
/// - Entry/exit assembly must preserve compiler-live registers.
/// Privilege: CPL 0.
/// Inputs: VMCB address 4-KiB aligned; bits 63:MAXPHYADDR = 0.
/// Effects:
/// - Returns after VMEXIT.
/// - This wrapper does not save guest GPR/SIMD state.
pub fn vmrun(vmcb: addr.PhysAddr) void {
    comptime target.require();
    asm volatile ("vmrun"
        :
        : [vmcb] "{rax}" (vmcb.raw()),
        : .{ .memory = true });
}

/// Requires: EFER.SVME.
/// Privilege: CPL 0.
/// Inputs: VMCB address 4-KiB aligned; bits 63:MAXPHYADDR = 0.
/// Effects: Loads the VMCB's additional host or guest state.
pub fn vmload(vmcb: addr.PhysAddr) void {
    comptime target.require();
    asm volatile ("vmload"
        :
        : [vmcb] "{rax}" (vmcb.raw()),
        : .{ .memory = true });
}

/// Requires: EFER.SVME.
/// Privilege: CPL 0.
/// Inputs: VMCB address 4-KiB aligned; bits 63:MAXPHYADDR = 0.
/// Effects: Saves the state subset restored by VMLOAD.
pub fn vmsave(vmcb: addr.PhysAddr) void {
    comptime target.require();
    asm volatile ("vmsave"
        :
        : [vmcb] "{rax}" (vmcb.raw()),
        : .{ .memory = true });
}

/// Requires: EFER.SVME.
/// Privilege: CPL 0.
pub fn stgi() void {
    comptime target.require();
    asm volatile ("stgi" ::: .{ .memory = true });
}

/// Requires: EFER.SVME.
/// Privilege: CPL 0.
pub fn clgi() void {
    comptime target.require();
    asm volatile ("clgi" ::: .{ .memory = true });
}

/// Requires: EFER.SVME.
/// Privilege: CPL 0.
pub fn invlpga(address: addr.VirtAddr, asid: u32) void {
    comptime target.require();

    asm volatile ("invlpga"
        :
        : [address] "{rax}" (address.raw()),
          [asid] "{ecx}" (asid),
        : .{ .memory = true });
}

/// Privilege: CPL 0.
/// Inputs: address is a 64-KiB-aligned physical address below 4 GiB.
/// Effects: Transfers control to the measured secure loader image.
pub fn skinit(address: u32) noreturn {
    comptime target.require();

    asm volatile ("skinit"
        :
        : [address] "{eax}" (address),
        : .{ .memory = true });

    unreachable;
}
