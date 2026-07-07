//! x86_64 SVM ISA wrapper contract tests.
//! Spec: docs/specs/arch/x86_64/svm.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const x86 = stdx.arch.x86_64;
const Svm = x86.Svm;

const testing = std.testing;

comptime {
    std.debug.assert(@sizeOf(Svm.Vmcb) == 4096);
    std.debug.assert(@alignOf(Svm.Vmcb) == 4096);
    std.debug.assert(Svm.Vmcb.alignment == 4096);
    std.debug.assert(@offsetOf(Svm.Vmcb, "control") == 0x000);
    std.debug.assert(@offsetOf(Svm.Vmcb, "state") == 0x400);
}

test "unit: Svm.PhysAddr.fromInt/raw round-trip at boundaries" {
    try testing.expectEqual(@as(u64, 0), Svm.PhysAddr.fromInt(0).raw());
    try testing.expectEqual(
        @as(u64, 0x0fed_cba9_8765_4321),
        Svm.PhysAddr.fromInt(0x0fed_cba9_8765_4321).raw(),
    );
    try testing.expectEqual(
        std.math.maxInt(u64),
        Svm.PhysAddr.fromInt(std.math.maxInt(u64)).raw(),
    );
}

test "unit: Svm.PhysAddr is distinct from Vmx.PhysAddr" {
    try testing.expect(Svm.PhysAddr != x86.Vmx.PhysAddr);
}

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "contract: Svm.vmrun/vmload/vmsave instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn (Svm.PhysAddr) void, Svm.vmrun);
    expectFn(fn (Svm.PhysAddr) void, Svm.vmload);
    expectFn(fn (Svm.PhysAddr) void, Svm.vmsave);
}

test "contract: Svm.stgi/clgi instantiate" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn () void, Svm.stgi);
    expectFn(fn () void, Svm.clgi);
}

test "contract: Svm.invlpga instantiates" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn (u64, u32) void, Svm.invlpga);
}

test "contract: Svm.skinit instantiates as noreturn" {
    if (builtin.cpu.arch != .x86_64) return;
    expectFn(fn (u32) noreturn, Svm.skinit);
}
