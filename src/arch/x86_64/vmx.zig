const std = @import("std");
const addr = @import("addr");

const target = @import("target.zig");
const registers = @import("registers.zig");

/// reports instruction status from carry and zero flags; architectural faults remain exceptions.
pub const Error = error{ VMfailInvalid, VMfailValid };

/// the processor owns the data after VMXON; ordinary accesses must not modify it.
/// set header.revision_id to IA32_VMX_BASIC's revision identifier before use.
pub const Vmxon = extern struct {
    header: Header align(4096) = .{},
    data: [4092]u8 = @splat(0),

    pub const alignment: usize = 4096;

    pub const Header = packed struct(u32) {
        revision_id: u31 = 0,
        _reserved_31: u1 = 0,
    };

    comptime {
        std.debug.assert(@sizeOf(@This()) == 4096);
        std.debug.assert(@alignOf(@This()) == 4096);
        std.debug.assert(@offsetOf(@This(), "header") == 0);
        std.debug.assert(@offsetOf(@This(), "data") == 4);
    }
};

/// the data layout is processor-defined; do not access it directly.
/// access architectural fields through VMREAD and VMWRITE.
/// set header.revision_id to IA32_VMX_BASIC's revision identifier before use.
pub const VMCS = extern struct {
    header: Header align(4096) = .{},
    abort_indicator: u32 = 0,
    data: [4088]u8 = @splat(0),

    pub const alignment: usize = 4096;

    pub const Header = packed struct(u32) {
        revision_id: u31 = 0,
        shadow: bool = false,
    };

    comptime {
        std.debug.assert(@sizeOf(@This()) == 4096);
        std.debug.assert(@alignOf(@This()) == 4096);
        std.debug.assert(@offsetOf(@This(), "header") == 0);
        std.debug.assert(@offsetOf(@This(), "abort_indicator") == 4);
        std.debug.assert(@offsetOf(@This(), "data") == 8);
    }
};

pub const Invept = struct {
    pub const Scope = enum(u64) {
        context = 1,
        all = 2,
    };

    pub const Descriptor = extern struct {
        eptp: u64 align(16),
        _reserved_64: u64 = 0,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 16);
            std.debug.assert(@alignOf(@This()) == 16);
            std.debug.assert(@offsetOf(@This(), "eptp") == 0);
            std.debug.assert(@offsetOf(@This(), "_reserved_64") == 8);
        }
    };
};

pub const Invvpid = struct {
    /// address/context/all include global translations; context_non_global retains them.
    pub const Scope = enum(u64) {
        address = 0,
        context = 1,
        all = 2,
        context_non_global = 3,
    };

    pub const Descriptor = extern struct {
        vpid: u16 align(16),
        _reserved_16: u16 = 0,
        _reserved_32: u32 = 0,
        address: addr.VirtAddr = .zero(),

        comptime {
            std.debug.assert(@sizeOf(@This()) == 16);
            std.debug.assert(@alignOf(@This()) == 16);
            std.debug.assert(@offsetOf(@This(), "vpid") == 0);
            std.debug.assert(@offsetOf(@This(), "_reserved_16") == 2);
            std.debug.assert(@offsetOf(@This(), "_reserved_32") == 4);
            std.debug.assert(@offsetOf(@This(), "address") == 8);
        }
    };
};

/// requires CPL 0 and VMX support; the region must meet VMX physical-width and 4-KiB alignment rules.
/// region points to the physical address, not the VMXON body.
pub fn vmxon(region: *const addr.PhysAddr) Error!void {
    comptime target.require();

    var flags: u64 = undefined;
    asm volatile (
        \\vmxon (%[region])
        \\pushfq
        \\popq %[flags]
        : [flags] "=r" (flags),
        : [region] "r" (region),
        : .{ .memory = true, .cc = true });

    return Impl.checkStatus(registers.RFLAGS.from(flags));
}

/// requires CPL 0 and VMX root operation.
pub fn vmxoff() Error!void {
    comptime target.require();

    var flags: u64 = undefined;
    asm volatile (
        \\vmxoff
        \\pushfq
        \\popq %[flags]
        : [flags] "=r" (flags),
        :
        : .{ .memory = true, .cc = true });

    return Impl.checkStatus(registers.RFLAGS.from(flags));
}

/// requires CPL 0 and VMX operation; the VMCS physical address must be supported and 4-KiB aligned.
pub fn vmclear(vmcs: *const addr.PhysAddr) Error!void {
    comptime target.require();

    var flags: u64 = undefined;
    asm volatile (
        \\vmclear (%[vmcs])
        \\pushfq
        \\popq %[flags]
        : [flags] "=r" (flags),
        : [vmcs] "r" (vmcs),
        : .{ .memory = true, .cc = true });

    return Impl.checkStatus(registers.RFLAGS.from(flags));
}

/// requires CPL 0 and VMX operation; the VMCS physical address must be supported and 4-KiB aligned.
pub fn vmptrld(vmcs: *const addr.PhysAddr) Error!void {
    comptime target.require();

    var flags: u64 = undefined;
    asm volatile (
        \\vmptrld (%[vmcs])
        \\pushfq
        \\popq %[flags]
        : [flags] "=r" (flags),
        : [vmcs] "r" (vmcs),
        : .{ .memory = true, .cc = true });

    return Impl.checkStatus(registers.RFLAGS.from(flags));
}

/// requires CPL 0 and VMX root operation; stores all ones when no VMCS is current.
pub fn vmptrst(out: *addr.PhysAddr) void {
    comptime target.require();

    asm volatile ("vmptrst (%[out])"
        :
        : [out] "r" (out),
        : .{ .memory = true, .cc = true });
}

/// requires CPL 0 and VMX root operation.
/// the caller must configure VMCS host state and continuation; successful entry does not return here.
pub fn vmlaunch() Error {
    comptime target.require();

    var flags: u64 = undefined;
    asm volatile (
        \\vmlaunch
        \\pushfq
        \\popq %[flags]
        : [flags] "=r" (flags),
        :
        : .{ .memory = true, .cc = true });

    Impl.checkStatus(registers.RFLAGS.from(flags)) catch |err| return err;
    unreachable;
}

/// requires CPL 0 and VMX root operation.
/// the caller must configure VMCS host state and continuation; successful entry does not return here.
pub fn vmresume() Error {
    comptime target.require();

    var flags: u64 = undefined;
    asm volatile (
        \\vmresume
        \\pushfq
        \\popq %[flags]
        : [flags] "=r" (flags),
        :
        : .{ .memory = true, .cc = true });

    Impl.checkStatus(registers.RFLAGS.from(flags)) catch |err| return err;
    unreachable;
}

/// requires CPL 0; field is a raw VMCS field encoding.
pub fn vmread(field: u32) Error!u64 {
    comptime target.require();

    var value: u64 = undefined;
    var flags: u64 = undefined;
    asm volatile (
        \\vmread %[field], %[value]
        \\pushfq
        \\popq %[flags]
        : [value] "=r" (value),
          [flags] "=r" (flags),
        : [field] "r" (@as(u64, field)),
        : .{ .memory = true, .cc = true });

    try Impl.checkStatus(registers.RFLAGS.from(flags));
    return value;
}

/// requires CPL 0; narrow VMCS fields still use a 64-bit operand.
pub fn vmwrite(field: u32, value: u64) Error!void {
    comptime target.require();

    var flags: u64 = undefined;
    asm volatile (
        \\vmwrite %[value], %[field]
        \\pushfq
        \\popq %[flags]
        : [flags] "=r" (flags),
        : [field] "r" (@as(u64, field)),
          [value] "r" (value),
        : .{ .memory = true, .cc = true });

    return Impl.checkStatus(registers.RFLAGS.from(flags));
}

/// requires CPL 0, VMX operation, and support for the requested INVEPT scope.
pub fn invept(scope: Invept.Scope, descriptor: *const Invept.Descriptor) Error!void {
    comptime target.require();

    var flags: u64 = undefined;
    asm volatile (
        \\invept (%[descriptor]), %[scope]
        \\pushfq
        \\popq %[flags]
        : [flags] "=r" (flags),
        : [scope] "r" (@intFromEnum(scope)),
          [descriptor] "r" (descriptor),
        : .{ .memory = true, .cc = true });

    return Impl.checkStatus(registers.RFLAGS.from(flags));
}

/// requires CPL 0, VMX operation, and support for the requested INVVPID scope.
/// address scope requires a canonical address; address/context/context_non_global require a nonzero VPID.
pub fn invvpid(scope: Invvpid.Scope, descriptor: *const Invvpid.Descriptor) Error!void {
    comptime target.require();

    var flags: u64 = undefined;
    asm volatile (
        \\invvpid (%[descriptor]), %[scope]
        \\pushfq
        \\popq %[flags]
        : [flags] "=r" (flags),
        : [scope] "r" (@intFromEnum(scope)),
          [descriptor] "r" (descriptor),
        : .{ .memory = true, .cc = true });

    return Impl.checkStatus(registers.RFLAGS.from(flags));
}

const Impl = struct {
    fn checkStatus(flags: registers.RFLAGS) Error!void {
        if (flags.carry) {
            return error.VMfailInvalid;
        }

        if (flags.zero) {
            return error.VMfailValid;
        }
    }
};

pub const unit = struct {
    test "VMX status distinguishes success and failures with carry precedence" {
        const testing = std.testing;

        try Impl.checkStatus(registers.RFLAGS.from(0x2));
        try testing.expectError(error.VMfailInvalid, Impl.checkStatus(registers.RFLAGS.from(0x3)));
        try testing.expectError(error.VMfailValid, Impl.checkStatus(registers.RFLAGS.from(0x42)));
        try testing.expectError(error.VMfailInvalid, Impl.checkStatus(registers.RFLAGS.from(0x43)));
    }
};
