//! x86_64 VMX ISA wrapper contract tests.
//! See `docs/specs/arch/x86_64/vmx.md`.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const vmx = stdx.arch.x86_64.vmx;

const testing = std.testing;

comptime {
    const err_info = @typeInfo(vmx.Error).error_set.?;
    std.debug.assert(err_info.len == 2);

    std.debug.assert(@sizeOf(vmx.VMXONRegion) == 4096);
    std.debug.assert(@alignOf(vmx.VMXONRegion) == 4096);
    std.debug.assert(vmx.VMXONRegion.alignment == 4096);
    std.debug.assert(@offsetOf(vmx.VMXONRegion, "revision_id") == 0);
    std.debug.assert(@offsetOf(vmx.VMXONRegion, "_reserved") == 4);

    std.debug.assert(@sizeOf(vmx.VMCS) == 4096);
    std.debug.assert(@alignOf(vmx.VMCS) == 4096);
    std.debug.assert(vmx.VMCS.alignment == 4096);
    std.debug.assert(@offsetOf(vmx.VMCS, "revision_id") == 0);
    std.debug.assert(@offsetOf(vmx.VMCS, "abort_indicator") == 4);
    std.debug.assert(@offsetOf(vmx.VMCS, "_reserved") == 8);

    std.debug.assert(@sizeOf(vmx.InveptDescriptor) == 16);
    std.debug.assert(@alignOf(vmx.InveptDescriptor) == 16);
    std.debug.assert(vmx.InveptDescriptor.alignment == 16);
    std.debug.assert(@offsetOf(vmx.InveptDescriptor, "eptp") == 0);
    std.debug.assert(@offsetOf(vmx.InveptDescriptor, "_reserved") == 8);

    std.debug.assert(@sizeOf(vmx.InvvpidDescriptor) == 16);
    std.debug.assert(@alignOf(vmx.InvvpidDescriptor) == 16);
    std.debug.assert(vmx.InvvpidDescriptor.alignment == 16);
    std.debug.assert(@offsetOf(vmx.InvvpidDescriptor, "vpid") == 0);
    std.debug.assert(@offsetOf(vmx.InvvpidDescriptor, "_reserved_low") == 2);
    std.debug.assert(@offsetOf(vmx.InvvpidDescriptor, "_reserved_high") == 4);
    std.debug.assert(@offsetOf(vmx.InvvpidDescriptor, "linear_address") == 8);

    const invept_info = @typeInfo(vmx.InveptKind).@"enum";
    std.debug.assert(invept_info.tag_type == u64);
    std.debug.assert(invept_info.is_exhaustive == false);
    std.debug.assert(@intFromEnum(vmx.InveptKind.single_context) == 1);
    std.debug.assert(@intFromEnum(vmx.InveptKind.global) == 2);

    const invvpid_info = @typeInfo(vmx.InvvpidKind).@"enum";
    std.debug.assert(invvpid_info.tag_type == u64);
    std.debug.assert(invvpid_info.is_exhaustive == false);
    std.debug.assert(@intFromEnum(vmx.InvvpidKind.individual_address) == 0);
    std.debug.assert(@intFromEnum(vmx.InvvpidKind.single_context) == 1);
    std.debug.assert(@intFromEnum(vmx.InvvpidKind.all_contexts) == 2);
    std.debug.assert(@intFromEnum(vmx.InvvpidKind.single_context_retaining_globals) == 3);
}

test "unit: vmx.Error names exactly VMfailInvalid and VMfailValid" {
    const invalid: vmx.Error = error.VMfailInvalid;
    const valid: vmx.Error = error.VMfailValid;
    try testing.expectEqual(@as(vmx.Error, error.VMfailInvalid), invalid);
    try testing.expectEqual(@as(vmx.Error, error.VMfailValid), valid);
}

test "unit: vmx.PhysAddr.fromInt/raw round-trip at boundaries" {
    try testing.expectEqual(@as(u64, 0), vmx.PhysAddr.fromInt(0).raw());
    try testing.expectEqual(
        @as(u64, 0x1234_5678_9abc_def0),
        vmx.PhysAddr.fromInt(0x1234_5678_9abc_def0).raw(),
    );
    try testing.expectEqual(
        std.math.maxInt(u64),
        vmx.PhysAddr.fromInt(std.math.maxInt(u64)).raw(),
    );
}

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "contract: vmx.vmxon/vmxoff instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn (*const vmx.PhysAddr) vmx.Error!void, vmx.vmxon);
    expectFn(fn () vmx.Error!void, vmx.vmxoff);
}

test "contract: vmx.vmclear/vmptrld/vmptrst instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn (*const vmx.PhysAddr) vmx.Error!void, vmx.vmclear);
    expectFn(fn (*const vmx.PhysAddr) vmx.Error!void, vmx.vmptrld);
    expectFn(fn (*vmx.PhysAddr) vmx.Error!void, vmx.vmptrst);
}

test "contract: vmx.vmlaunch/vmresume instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn () vmx.Error!noreturn, vmx.vmlaunch);
    expectFn(fn () vmx.Error!noreturn, vmx.vmresume);
}

test "contract: vmx.vmread/vmwrite instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn (u32) vmx.Error!u64, vmx.vmread);
    expectFn(fn (u32, u64) vmx.Error!void, vmx.vmwrite);
}

test "contract: vmx.invept/invvpid instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(
        fn (vmx.InveptKind, *const vmx.InveptDescriptor) vmx.Error!void,
        vmx.invept,
    );
    expectFn(
        fn (vmx.InvvpidKind, *const vmx.InvvpidDescriptor) vmx.Error!void,
        vmx.invvpid,
    );
}
