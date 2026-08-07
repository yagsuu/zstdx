//! x86_64 SVM ISA wrapper contract tests.
//! See `docs/specs/arch/x86_64/svm.md`.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const x86 = stdx.arch.x86_64;
const svm = x86.svm;

const testing = std.testing;

comptime {
    std.debug.assert(@sizeOf(svm.VMCB) == 4096);
    std.debug.assert(@alignOf(svm.VMCB) == 4096);
    std.debug.assert(svm.VMCB.alignment == 4096);
    std.debug.assert(@offsetOf(svm.VMCB, "control") == 0x000);
    std.debug.assert(@offsetOf(svm.VMCB, "state") == 0x400);
}

test "unit: svm.PhysAddr.fromInt/raw round-trip at boundaries" {
    try testing.expectEqual(@as(u64, 0), svm.PhysAddr.fromInt(0).raw());
    try testing.expectEqual(
        @as(u64, 0x0fed_cba9_8765_4321),
        svm.PhysAddr.fromInt(0x0fed_cba9_8765_4321).raw(),
    );
    try testing.expectEqual(
        std.math.maxInt(u64),
        svm.PhysAddr.fromInt(std.math.maxInt(u64)).raw(),
    );
}

test "unit: svm.PhysAddr is distinct from vmx.PhysAddr" {
    try testing.expect(svm.PhysAddr != x86.vmx.PhysAddr);
}

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "contract: svm.vmrun/vmload/vmsave instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn (svm.PhysAddr) void, svm.vmrun);
    expectFn(fn (svm.PhysAddr) void, svm.vmload);
    expectFn(fn (svm.PhysAddr) void, svm.vmsave);
}

test "contract: svm.stgi/clgi instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn () void, svm.stgi);
    expectFn(fn () void, svm.clgi);
}

test "contract: svm.invlpga instantiates" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn (u64, u32) void, svm.invlpga);
}

test "contract: svm.skinit instantiates as noreturn" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn (u32) noreturn, svm.skinit);
}
