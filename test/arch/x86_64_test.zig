//! x86_64 architecture primitives contract tests.
//! Spec: docs/specs/arch/x86_64/base.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const x86 = stdx.arch.x86_64;
const cpuid = x86.cpuid;
const register = x86.register;
const interrupts = x86.interrupts;
const cpu = x86.cpu;
const fence = x86.fence;
const cache = x86.cache;
const privilege = x86.privilege;

const testing = std.testing;

test "unit: Port.fromInt and raw round-trip at boundaries" {
    try testing.expectEqual(@as(u16, 0), x86.Port.fromInt(0).raw());
    try testing.expectEqual(@as(u16, 0x3f8), x86.Port.fromInt(0x3f8).raw());
    try testing.expectEqual(@as(u16, 0xffff), x86.Port.fromInt(0xffff).raw());
}

test "unit: Port instances remain distinct across constructions" {
    const a = x86.Port.fromInt(0x60);
    const b = x86.Port.fromInt(0x64);
    const a_again = x86.Port.fromInt(0x60);
    try testing.expect(a != b);
    try testing.expect(a == a_again);
    try testing.expectEqual(a.raw(), a_again.raw());
    try testing.expect(a.raw() != b.raw());
}

test "unit: MSR.fromInt and raw round-trip at boundaries" {
    try testing.expectEqual(@as(u32, 0), x86.MSR.fromInt(0).raw());
    try testing.expectEqual(@as(u32, 0x1b), x86.MSR.fromInt(0x1b).raw());
    try testing.expectEqual(@as(u32, 0xffff_ffff), x86.MSR.fromInt(0xffff_ffff).raw());
}

test "unit: MSR named tags match architectural addresses" {
    try testing.expectEqual(@as(u32, 0x0000_0010), x86.MSR.tsc.raw());
    try testing.expectEqual(@as(u32, 0x0000_001b), x86.MSR.apic_base.raw());
    try testing.expectEqual(@as(u32, 0x0000_003a), x86.MSR.feature_control.raw());
    try testing.expectEqual(@as(u32, 0x0000_0277), x86.MSR.pat.raw());
    try testing.expectEqual(@as(u32, 0x0000_0480), x86.MSR.vmx_basic.raw());
    try testing.expectEqual(@as(u32, 0x0000_0481), x86.MSR.vmx_pinbased_ctls.raw());
    try testing.expectEqual(@as(u32, 0x0000_0482), x86.MSR.vmx_procbased_ctls.raw());
    try testing.expectEqual(@as(u32, 0x0000_0483), x86.MSR.vmx_exit_ctls.raw());
    try testing.expectEqual(@as(u32, 0x0000_0484), x86.MSR.vmx_entry_ctls.raw());
    try testing.expectEqual(@as(u32, 0xc000_0080), x86.MSR.efer.raw());
    try testing.expectEqual(@as(u32, 0xc000_0081), x86.MSR.star.raw());
    try testing.expectEqual(@as(u32, 0xc000_0082), x86.MSR.lstar.raw());
    try testing.expectEqual(@as(u32, 0xc000_0084), x86.MSR.fmask.raw());
    try testing.expectEqual(@as(u32, 0xc000_0100), x86.MSR.fs_base.raw());
    try testing.expectEqual(@as(u32, 0xc000_0101), x86.MSR.gs_base.raw());
    try testing.expectEqual(@as(u32, 0xc000_0102), x86.MSR.kernel_gs_base.raw());
    try testing.expectEqual(@as(u32, 0xc000_0103), x86.MSR.tsc_aux.raw());
    try testing.expectEqual(@as(u32, 0xc001_0117), x86.MSR.vm_hsave_pa.raw());
}

test "unit: supported matches the build target" {
    try testing.expectEqual(builtin.cpu.arch == .x86_64, x86.supported);
}

test "model: register.descriptor.Pointer is exactly 10 bytes with no inter-field padding" {
    try testing.expectEqual(@as(usize, 10), @sizeOf(register.descriptor.Pointer));
    try testing.expectEqual(@as(usize, 0), @offsetOf(register.descriptor.Pointer, "limit"));
    try testing.expectEqual(@as(usize, 2), @offsetOf(register.descriptor.Pointer, "base"));
}

// `@TypeOf` checks keep privileged wrappers compile-only: signatures are
// checked without codegen or host execution.

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "compile: Port scalar I/O instantiates for every width" {
    if (!x86.supported) return;
    expectFn(fn (x86.Port) u8, x86.Port.in8);
    expectFn(fn (x86.Port) u16, x86.Port.in16);
    expectFn(fn (x86.Port) u32, x86.Port.in32);
    expectFn(fn (x86.Port, u8) void, x86.Port.out8);
    expectFn(fn (x86.Port, u16) void, x86.Port.out16);
    expectFn(fn (x86.Port, u32) void, x86.Port.out32);
}

test "compile: Port slice I/O instantiates for every width" {
    if (!x86.supported) return;
    expectFn(fn (x86.Port, []u8) void, x86.Port.inSlice8);
    expectFn(fn (x86.Port, []u16) void, x86.Port.inSlice16);
    expectFn(fn (x86.Port, []u32) void, x86.Port.inSlice32);
    expectFn(fn (x86.Port, []const u8) void, x86.Port.outSlice8);
    expectFn(fn (x86.Port, []const u16) void, x86.Port.outSlice16);
    expectFn(fn (x86.Port, []const u32) void, x86.Port.outSlice32);
}

test "compile: cpuid family instantiates" {
    if (!x86.supported) return;
    expectFn(fn (cpuid.Leaf) cpuid.Result, cpuid.leaf);
    expectFn(fn (cpuid.Leaf, u32) cpuid.Result, cpuid.subleaf);
    expectFn(fn () u32, cpuid.maxBasicLeaf);
    expectFn(fn () u32, cpuid.maxExtendedLeaf);
}

test "compile: MSR read/write instantiate" {
    if (!x86.supported) return;
    expectFn(fn (x86.MSR) u64, x86.MSR.read);
    expectFn(fn (x86.MSR, u64) void, x86.MSR.write);
}

test "compile: register.control family instantiates" {
    if (!x86.supported) return;
    expectFn(fn () u64, register.control.cr0.read);
    expectFn(fn (u64) void, register.control.cr0.write);
    expectFn(fn () u64, register.control.cr2.read);
    expectFn(fn () u64, register.control.cr3.read);
    expectFn(fn (u64) void, register.control.cr3.write);
    expectFn(fn () u64, register.control.cr4.read);
    expectFn(fn (u64) void, register.control.cr4.write);
    expectFn(fn () u64, register.control.cr8.read);
    expectFn(fn (u64) void, register.control.cr8.write);
    expectFn(fn () u64, register.control.xcr0.read);
    expectFn(fn (u64) void, register.control.xcr0.write);
}

test "compile: register.rflags read/write instantiate" {
    if (!x86.supported) return;
    expectFn(fn () u64, register.rflags.read);
    expectFn(fn (u64) void, register.rflags.write);
}

test "compile: interrupts family instantiates" {
    if (!x86.supported) return;
    expectFn(fn () void, interrupts.enable);
    expectFn(fn () void, interrupts.disable);
    expectFn(fn () bool, interrupts.enabled);
}

test "compile: cpu one-shots instantiate" {
    if (!x86.supported) return;
    expectFn(fn () void, cpu.halt);
    expectFn(fn () void, cpu.pause);
    expectFn(fn () void, cpu.breakpoint);
}

test "compile: register.descriptor table family instantiates" {
    if (!x86.supported) return;
    expectFn(fn (*const register.descriptor.Pointer) void, register.descriptor.gdtr.load);
    expectFn(fn (*register.descriptor.Pointer) void, register.descriptor.gdtr.store);
    expectFn(fn (*const register.descriptor.Pointer) void, register.descriptor.idtr.load);
    expectFn(fn (*register.descriptor.Pointer) void, register.descriptor.idtr.store);
    expectFn(fn (u16) void, register.descriptor.tr.load);
    expectFn(fn () u16, register.descriptor.tr.store);
}

test "compile: register.segment family instantiates" {
    if (!x86.supported) return;
    expectFn(fn () u16, register.segment.cs.read);
    expectFn(fn (u16) void, register.segment.cs.writeFarReturn);
    expectFn(fn () u16, register.segment.ds.read);
    expectFn(fn (u16) void, register.segment.ds.write);
    expectFn(fn () u16, register.segment.es.read);
    expectFn(fn (u16) void, register.segment.es.write);
    expectFn(fn () u16, register.segment.fs.read);
    expectFn(fn (u16) void, register.segment.fs.write);
    expectFn(fn () u16, register.segment.gs.read);
    expectFn(fn (u16) void, register.segment.gs.write);
    expectFn(fn () u16, register.segment.ss.read);
    expectFn(fn (u16) void, register.segment.ss.write);
    expectFn(fn () u64, register.segment.fs_base.read);
    expectFn(fn (u64) void, register.segment.fs_base.write);
    expectFn(fn () u64, register.segment.gs_base.read);
    expectFn(fn (u64) void, register.segment.gs_base.write);
    expectFn(fn () void, register.segment.swapGs);
}

test "compile: fence family instantiates" {
    if (!x86.supported) return;
    expectFn(fn () void, fence.lfence);
    expectFn(fn () void, fence.sfence);
    expectFn(fn () void, fence.mfence);
}

test "compile: cache family instantiates" {
    if (!x86.supported) return;
    expectFn(fn () usize, cache.lineSize);
    expectFn(fn (usize) void, cache.flush);
    expectFn(fn (usize) void, cache.flushOptimized);
    expectFn(fn (usize) void, cache.writeBack);
    expectFn(fn ([*]const u8, usize) void, cache.flushRange);
    expectFn(fn ([*]const u8, usize) void, cache.writeBackRange);
    expectFn(fn () void, cache.writeBackInvalidate);
    expectFn(fn () void, cache.invalidate);
}

test "compile: privilege.currentLevel and ioWait instantiate" {
    if (!x86.supported) return;
    expectFn(fn () u2, privilege.currentLevel);
    expectFn(fn () void, x86.ioWait);
}

// Host runtime coverage stays limited to unprivileged, non-mutating
// instructions.

test "host: cpuid.maxBasicLeaf reports at least leaf 1" {
    if (!x86.supported) return;
    try testing.expect(cpuid.maxBasicLeaf() >= 1);
}

test "host: cpuid.maxExtendedLeaf reports at least 0x80000000" {
    if (!x86.supported) return;
    try testing.expect(cpuid.maxExtendedLeaf() >= 0x80000000);
}

test "host: cpu.pause executes once" {
    if (!x86.supported) return;
    cpu.pause();
}

test "host: fence.lfence/sfence/mfence each execute once" {
    if (!x86.supported) return;
    fence.lfence();
    fence.sfence();
    fence.mfence();
}

test "host: register.rflags.read returns a value with reserved bit 1 set" {
    if (!x86.supported) return;
    const flags = register.rflags.read();
    try testing.expect((flags & 0b10) != 0);
}

test "host: privilege.currentLevel returns the userspace CPL" {
    if (!x86.supported) return;
    try testing.expectEqual(@as(u2, 3), privilege.currentLevel());
}
