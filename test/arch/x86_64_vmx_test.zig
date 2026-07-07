//! x86_64 VMX ISA wrapper contract tests.
//! Spec: docs/specs/arch/x86_64/vmx.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const Vmx = stdx.arch.x86_64.Vmx;

const testing = std.testing;

comptime {
    const err_info = @typeInfo(Vmx.Error).error_set.?;
    std.debug.assert(err_info.len == 2);

    std.debug.assert(@sizeOf(Vmx.VmxonRegion) == 4096);
    std.debug.assert(@alignOf(Vmx.VmxonRegion) == 4096);
    std.debug.assert(Vmx.VmxonRegion.alignment == 4096);
    std.debug.assert(@offsetOf(Vmx.VmxonRegion, "revision_id") == 0);
    std.debug.assert(@offsetOf(Vmx.VmxonRegion, "_reserved") == 4);

    std.debug.assert(@sizeOf(Vmx.Vmcs) == 4096);
    std.debug.assert(@alignOf(Vmx.Vmcs) == 4096);
    std.debug.assert(Vmx.Vmcs.alignment == 4096);
    std.debug.assert(@offsetOf(Vmx.Vmcs, "revision_id") == 0);
    std.debug.assert(@offsetOf(Vmx.Vmcs, "abort_indicator") == 4);
    std.debug.assert(@offsetOf(Vmx.Vmcs, "_reserved") == 8);

    std.debug.assert(@sizeOf(Vmx.InveptDescriptor) == 16);
    std.debug.assert(@alignOf(Vmx.InveptDescriptor) == 16);
    std.debug.assert(Vmx.InveptDescriptor.alignment == 16);
    std.debug.assert(@offsetOf(Vmx.InveptDescriptor, "eptp") == 0);
    std.debug.assert(@offsetOf(Vmx.InveptDescriptor, "_reserved") == 8);

    std.debug.assert(@sizeOf(Vmx.InvvpidDescriptor) == 16);
    std.debug.assert(@alignOf(Vmx.InvvpidDescriptor) == 16);
    std.debug.assert(Vmx.InvvpidDescriptor.alignment == 16);
    std.debug.assert(@offsetOf(Vmx.InvvpidDescriptor, "vpid") == 0);
    std.debug.assert(@offsetOf(Vmx.InvvpidDescriptor, "_reserved_low") == 2);
    std.debug.assert(@offsetOf(Vmx.InvvpidDescriptor, "_reserved_high") == 4);
    std.debug.assert(@offsetOf(Vmx.InvvpidDescriptor, "linear_address") == 8);

    const invept_info = @typeInfo(Vmx.InveptKind).@"enum";
    std.debug.assert(invept_info.tag_type == u64);
    std.debug.assert(invept_info.is_exhaustive == false);
    std.debug.assert(@intFromEnum(Vmx.InveptKind.single_context) == 1);
    std.debug.assert(@intFromEnum(Vmx.InveptKind.global) == 2);

    const invvpid_info = @typeInfo(Vmx.InvvpidKind).@"enum";
    std.debug.assert(invvpid_info.tag_type == u64);
    std.debug.assert(invvpid_info.is_exhaustive == false);
    std.debug.assert(@intFromEnum(Vmx.InvvpidKind.individual_address) == 0);
    std.debug.assert(@intFromEnum(Vmx.InvvpidKind.single_context) == 1);
    std.debug.assert(@intFromEnum(Vmx.InvvpidKind.all_contexts) == 2);
    std.debug.assert(@intFromEnum(Vmx.InvvpidKind.single_context_retaining_globals) == 3);
}

test "unit: Vmx.Error names exactly VMfailInvalid and VMfailValid" {
    const invalid: Vmx.Error = error.VMfailInvalid;
    const valid: Vmx.Error = error.VMfailValid;
    try testing.expectEqual(@as(Vmx.Error, error.VMfailInvalid), invalid);
    try testing.expectEqual(@as(Vmx.Error, error.VMfailValid), valid);
}

test "unit: Vmx.PhysAddr.fromInt/raw round-trip at boundaries" {
    try testing.expectEqual(@as(u64, 0), Vmx.PhysAddr.fromInt(0).raw());
    try testing.expectEqual(
        @as(u64, 0x1234_5678_9abc_def0),
        Vmx.PhysAddr.fromInt(0x1234_5678_9abc_def0).raw(),
    );
    try testing.expectEqual(
        std.math.maxInt(u64),
        Vmx.PhysAddr.fromInt(std.math.maxInt(u64)).raw(),
    );
}

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "contract: Vmx.vmxon/vmxoff instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn (*const Vmx.PhysAddr) Vmx.Error!void, Vmx.vmxon);
    expectFn(fn () Vmx.Error!void, Vmx.vmxoff);
}

test "contract: Vmx.vmclear/vmptrld/vmptrst instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn (*const Vmx.PhysAddr) Vmx.Error!void, Vmx.vmclear);
    expectFn(fn (*const Vmx.PhysAddr) Vmx.Error!void, Vmx.vmptrld);
    expectFn(fn (*Vmx.PhysAddr) Vmx.Error!void, Vmx.vmptrst);
}

test "contract: Vmx.vmlaunch/vmresume instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn () Vmx.Error!noreturn, Vmx.vmlaunch);
    expectFn(fn () Vmx.Error!noreturn, Vmx.vmresume);
}

test "contract: Vmx.vmread/vmwrite instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn (u32) Vmx.Error!u64, Vmx.vmread);
    expectFn(fn (u32, u64) Vmx.Error!void, Vmx.vmwrite);
}

test "contract: Vmx.invept/invvpid instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(
        fn (Vmx.InveptKind, *const Vmx.InveptDescriptor) Vmx.Error!void,
        Vmx.invept,
    );
    expectFn(
        fn (Vmx.InvvpidKind, *const Vmx.InvvpidDescriptor) Vmx.Error!void,
        Vmx.invvpid,
    );
}
