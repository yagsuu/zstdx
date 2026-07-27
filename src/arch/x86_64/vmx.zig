//! x86_64 VMX ISA wrappers. Spec: docs/specs/arch/x86_64/vmx.md.

const std = @import("std");

const target = @import("target.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

/// RFLAGS-mapped error set common to every VMX wrapper per Intel SDM
/// Vol.3 §30.2.
pub const Error = error{ VMfailInvalid, VMfailValid };

/// Strong physical-address value type covering the full 64-bit
/// physical-address space. Distinct from `Svm.PhysAddr`.
pub const PhysAddr = enum(u64) {
    _,

    pub fn fromInt(value: u64) PhysAddr {
        return @enumFromInt(value);
    }

    pub fn raw(self: PhysAddr) u64 {
        return @intFromEnum(self);
    }
};

/// 4 KiB VMXON region per SDM Vol.3 §24.11. The `_reserved` byte array
/// is the VMXON body — CPU-implementation-defined and MUST NOT be
/// accessed through ordinary loads or stores.
pub const VMXONRegion = extern struct {
    revision_id: u32 align(4096) = 0,
    _reserved: [4092]u8 = @splat(0),

    pub const alignment: usize = 4096;

    comptime {
        std.debug.assert(@sizeOf(VMXONRegion) == 4096);
        std.debug.assert(@alignOf(VMXONRegion) == 4096);
        std.debug.assert(@offsetOf(VMXONRegion, "revision_id") == 0);
        std.debug.assert(@offsetOf(VMXONRegion, "_reserved") == 4);
    }
};

/// 4 KiB VMCS region per SDM Vol.3 §24.2 / §24.11. The `_reserved` byte
/// array is the VMCS data area — accessible only via `vmread`/`vmwrite`.
pub const VMCS = extern struct {
    revision_id: u32 align(4096) = 0,
    abort_indicator: u32 = 0,
    _reserved: [4088]u8 = @splat(0),

    pub const alignment: usize = 4096;

    comptime {
        std.debug.assert(@sizeOf(VMCS) == 4096);
        std.debug.assert(@alignOf(VMCS) == 4096);
        std.debug.assert(@offsetOf(VMCS, "revision_id") == 0);
        std.debug.assert(@offsetOf(VMCS, "abort_indicator") == 4);
        std.debug.assert(@offsetOf(VMCS, "_reserved") == 8);
    }
};

/// INVEPT invalidation kind per SDM Vol.3 §30.3. Open enum; reserved
/// values produce `VMfailInvalid`.
pub const InveptKind = enum(u64) {
    single_context = 1,
    global = 2,
    _,
};

/// 16-byte INVEPT descriptor per SDM Vol.3 §30.3.
pub const InveptDescriptor = extern struct {
    eptp: u64 align(16),
    _reserved: u64 = 0,

    pub const alignment: usize = 16;

    comptime {
        std.debug.assert(@sizeOf(InveptDescriptor) == 16);
        std.debug.assert(@alignOf(InveptDescriptor) == 16);
        std.debug.assert(@offsetOf(InveptDescriptor, "eptp") == 0);
        std.debug.assert(@offsetOf(InveptDescriptor, "_reserved") == 8);
    }
};

/// INVVPID invalidation kind per SDM Vol.3 §30.3. Open enum; reserved
/// values produce `VMfailInvalid`.
pub const InvvpidKind = enum(u64) {
    individual_address = 0,
    single_context = 1,
    all_contexts = 2,
    single_context_retaining_globals = 3,
    _,
};

/// 16-byte INVVPID descriptor per SDM Vol.3 §30.3.
pub const InvvpidDescriptor = extern struct {
    vpid: u16 align(16),
    _reserved_low: u16 = 0,
    _reserved_high: u32 = 0,
    linear_address: u64 = 0,

    pub const alignment: usize = 16;

    comptime {
        std.debug.assert(@sizeOf(InvvpidDescriptor) == 16);
        std.debug.assert(@alignOf(InvvpidDescriptor) == 16);
        std.debug.assert(@offsetOf(InvvpidDescriptor, "vpid") == 0);
        std.debug.assert(@offsetOf(InvvpidDescriptor, "_reserved_low") == 2);
        std.debug.assert(@offsetOf(InvvpidDescriptor, "_reserved_high") == 4);
        std.debug.assert(@offsetOf(InvvpidDescriptor, "linear_address") == 8);
    }
};

// Decode RFLAGS.CF/ZF per SDM Vol.3 §30.2. CF is bit 0, ZF is bit 6.
// `CF=1, ZF=1` is architecturally impossible but MUST be reported as
// `VMfailInvalid` per the wrapper contract.
inline fn mapRflags(rflags: u64) Error!void {
    if (rflags & 0x1 != 0) return Error.VMfailInvalid;
    if (rflags & 0x40 != 0) return Error.VMfailValid;
}

/// Execute `vmxon [region]`. `region` is a Zig pointer to a `PhysAddr`
/// value in host memory; the CPU dereferences it as m64 to obtain the
/// VMXON region's physical address.
/// Privilege: CPL 0.
/// Faults: may `#GP` or `#UD`.
/// Returns: `Error!void` mapped from RFLAGS.
pub fn vmxon(region: *const PhysAddr) Error!void {
    if (!supported) @compileError(wrong_target);
    var rflags: u64 = undefined;
    asm volatile (
        \\vmxon %[region]
        \\pushfq
        \\popq %[rflags]
        : [rflags] "=r" (rflags),
        : [region] "*m" (region),
        : .{ .memory = true, .cc = true });
    return mapRflags(rflags);
}

/// Execute `vmxoff`.
/// Privilege: CPL 0.
/// Requirements: VMX root operation.
/// Returns: `Error!void` mapped from RFLAGS.
pub fn vmxoff() Error!void {
    if (!supported) @compileError(wrong_target);
    var rflags: u64 = undefined;
    asm volatile (
        \\vmxoff
        \\pushfq
        \\popq %[rflags]
        : [rflags] "=r" (rflags),
        :
        : .{ .memory = true, .cc = true });
    return mapRflags(rflags);
}

/// Execute `vmclear [vmcs]`.
/// Effects: marks the VMCS inactive and clear on the logical processor.
/// Privilege: CPL 0.
/// Returns: `Error!void` mapped from RFLAGS.
pub fn vmclear(vmcs: *const PhysAddr) Error!void {
    if (!supported) @compileError(wrong_target);
    var rflags: u64 = undefined;
    asm volatile (
        \\vmclear %[vmcs]
        \\pushfq
        \\popq %[rflags]
        : [rflags] "=r" (rflags),
        : [vmcs] "*m" (vmcs),
        : .{ .memory = true, .cc = true });
    return mapRflags(rflags);
}

/// Execute `vmptrld [vmcs]`.
/// Effects: makes the referenced region the current VMCS.
/// Privilege: CPL 0.
/// Returns: `Error!void` mapped from RFLAGS.
pub fn vmptrld(vmcs: *const PhysAddr) Error!void {
    if (!supported) @compileError(wrong_target);
    var rflags: u64 = undefined;
    asm volatile (
        \\vmptrld %[vmcs]
        \\pushfq
        \\popq %[rflags]
        : [rflags] "=r" (rflags),
        : [vmcs] "*m" (vmcs),
        : .{ .memory = true, .cc = true });
    return mapRflags(rflags);
}

/// Execute `vmptrst [out]`.
/// Effects: writes the current VMCS pointer, or all-ones when no VMCS is current.
/// Privilege: CPL 0.
/// Returns: `Error!void` mapped from RFLAGS.
pub fn vmptrst(out: *PhysAddr) Error!void {
    if (!supported) @compileError(wrong_target);
    var rflags: u64 = undefined;
    asm volatile (
        \\vmptrst (%[out])
        \\pushfq
        \\popq %[rflags]
        : [rflags] "=r" (rflags),
        : [out] "r" (out),
        : .{ .memory = true, .cc = true });
    return mapRflags(rflags);
}

/// Execute `vmlaunch`.
/// Effects: on success, transfers control to the guest (`noreturn`).
/// Privilege: CPL 0.
/// Returns: only RFLAGS-visible failure paths return, as `Error`.
pub fn vmlaunch() Error!noreturn {
    if (!supported) @compileError(wrong_target);
    var rflags: u64 = undefined;
    asm volatile (
        \\vmlaunch
        \\pushfq
        \\popq %[rflags]
        : [rflags] "=r" (rflags),
        :
        : .{ .memory = true, .cc = true });
    try mapRflags(rflags);
    unreachable;
}

/// Execute `vmresume`.
/// Effects: on success, transfers control to the guest (`noreturn`).
/// Privilege: CPL 0.
/// Returns: only RFLAGS-visible failure paths return, as `Error`.
pub fn vmresume() Error!noreturn {
    if (!supported) @compileError(wrong_target);
    var rflags: u64 = undefined;
    asm volatile (
        \\vmresume
        \\pushfq
        \\popq %[rflags]
        : [rflags] "=r" (rflags),
        :
        : .{ .memory = true, .cc = true });
    try mapRflags(rflags);
    unreachable;
}

/// Execute `vmread encoding, value` (Intel operand order: `VMREAD r/m64, r64`).
/// Operands: `encoding` is the raw 32-bit VMCS field encoding.
/// Privilege: CPL 0.
/// Notes: on failure, the returned value is unspecified.
pub fn vmread(encoding: u32) Error!u64 {
    if (!supported) @compileError(wrong_target);
    var value: u64 = undefined;
    var rflags: u64 = undefined;
    asm volatile (
        \\vmread %[enc], %[val]
        \\pushfq
        \\popq %[rflags]
        : [val] "=r" (value),
          [rflags] "=r" (rflags),
        : [enc] "r" (@as(u64, encoding)),
        : .{ .memory = true, .cc = true });
    try mapRflags(rflags);
    return value;
}

/// Execute `vmwrite value, encoding` (Intel operand order: `VMWRITE r64, r/m64`).
/// Operands: fields narrower than 64 bits are still exchanged as `u64`.
/// Privilege: CPL 0.
pub fn vmwrite(encoding: u32, value: u64) Error!void {
    if (!supported) @compileError(wrong_target);
    var rflags: u64 = undefined;
    asm volatile (
        \\vmwrite %[val], %[enc]
        \\pushfq
        \\popq %[rflags]
        : [rflags] "=r" (rflags),
        : [enc] "r" (@as(u64, encoding)),
          [val] "r" (value),
        : .{ .memory = true, .cc = true });
    return mapRflags(rflags);
}

/// Execute `invept kind, [descriptor]` (Intel: `INVEPT r64, m128`).
/// Effects: invalidates EPT-derived mappings on the issuing logical processor.
/// Privilege: CPL 0.
/// Returns: `Error!void` mapped from RFLAGS.
pub fn invept(kind: InveptKind, descriptor: *const InveptDescriptor) Error!void {
    if (!supported) @compileError(wrong_target);
    var rflags: u64 = undefined;
    asm volatile (
        \\invept %[desc], %[kind]
        \\pushfq
        \\popq %[rflags]
        : [rflags] "=r" (rflags),
        : [kind] "r" (@as(u64, @intFromEnum(kind))),
          [desc] "*m" (descriptor),
        : .{ .memory = true, .cc = true });
    return mapRflags(rflags);
}

/// Execute `invvpid kind, [descriptor]` (Intel: `INVVPID r64, m128`).
/// Effects: invalidates VPID-tagged mappings on the issuing logical processor.
/// Privilege: CPL 0.
/// Returns: `Error!void` mapped from RFLAGS.
pub fn invvpid(kind: InvvpidKind, descriptor: *const InvvpidDescriptor) Error!void {
    if (!supported) @compileError(wrong_target);
    var rflags: u64 = undefined;
    asm volatile (
        \\invvpid %[desc], %[kind]
        \\pushfq
        \\popq %[rflags]
        : [rflags] "=r" (rflags),
        : [kind] "r" (@as(u64, @intFromEnum(kind))),
          [desc] "*m" (descriptor),
        : .{ .memory = true, .cc = true });
    return mapRflags(rflags);
}
