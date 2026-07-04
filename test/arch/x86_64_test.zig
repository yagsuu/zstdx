//! x86_64 architecture primitives contract tests.
//! Spec: docs/specs/arch/x86_64/base.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const x86 = stdx.arch.x86_64;

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

test "unit: Msr.fromInt and raw round-trip at boundaries" {
    try testing.expectEqual(@as(u32, 0), x86.Msr.fromInt(0).raw());
    try testing.expectEqual(@as(u32, 0x1b), x86.Msr.fromInt(0x1b).raw());
    try testing.expectEqual(@as(u32, 0xffff_ffff), x86.Msr.fromInt(0xffff_ffff).raw());
}

test "unit: supported matches the build target" {
    try testing.expectEqual(builtin.cpu.arch == .x86_64, x86.supported);
}

test "model: Descriptor.Pointer is exactly 10 bytes with no inter-field padding" {
    try testing.expectEqual(@as(usize, 10), @sizeOf(x86.Descriptor.Pointer));
    try testing.expectEqual(@as(usize, 0), @offsetOf(x86.Descriptor.Pointer, "limit"));
    try testing.expectEqual(@as(usize, 2), @offsetOf(x86.Descriptor.Pointer, "base"));
}

// ---------------- Compile-only instantiation tests ----------------
//
// Compile-only references via `@TypeOf` validate that every entry point
// exists with the documented signature and is reachable on x86_64. They do
// not codegen the bodies, which is the point: privileged or wrong-target
// uses must never run in the host suite. On non-x86_64 `supported` is
// comptime-false and the entire body is dead before any reference fires.

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

test "compile: Cpuid family instantiates" {
    if (!x86.supported) return;
    expectFn(fn (x86.Cpuid.Leaf) x86.Cpuid.Result, x86.Cpuid.leaf);
    expectFn(fn (x86.Cpuid.Leaf, u32) x86.Cpuid.Result, x86.Cpuid.subleaf);
    expectFn(fn () u32, x86.Cpuid.maxBasicLeaf);
    expectFn(fn () u32, x86.Cpuid.maxExtendedLeaf);
}

test "compile: Msr read/write instantiate" {
    if (!x86.supported) return;
    expectFn(fn (x86.Msr) u64, x86.Msr.read);
    expectFn(fn (x86.Msr, u64) void, x86.Msr.write);
}

test "compile: ControlRegister family instantiates" {
    if (!x86.supported) return;
    expectFn(fn () u64, x86.ControlRegister.Cr0.read);
    expectFn(fn (u64) void, x86.ControlRegister.Cr0.write);
    expectFn(fn () u64, x86.ControlRegister.Cr2.read);
    expectFn(fn () u64, x86.ControlRegister.Cr3.read);
    expectFn(fn (u64) void, x86.ControlRegister.Cr3.write);
    expectFn(fn () u64, x86.ControlRegister.Cr4.read);
    expectFn(fn (u64) void, x86.ControlRegister.Cr4.write);
    expectFn(fn () u64, x86.ControlRegister.Cr8.read);
    expectFn(fn (u64) void, x86.ControlRegister.Cr8.write);
    expectFn(fn () u64, x86.ControlRegister.Xcr0.read);
    expectFn(fn (u64) void, x86.ControlRegister.Xcr0.write);
}

test "compile: Rflags read/write instantiate" {
    if (!x86.supported) return;
    expectFn(fn () u64, x86.Rflags.read);
    expectFn(fn (u64) void, x86.Rflags.write);
}

test "compile: Interrupts family instantiates" {
    if (!x86.supported) return;
    expectFn(fn () void, x86.Interrupts.enable);
    expectFn(fn () void, x86.Interrupts.disable);
    expectFn(fn () bool, x86.Interrupts.enabled);
}

test "compile: Cpu one-shots instantiate" {
    if (!x86.supported) return;
    expectFn(fn () void, x86.Cpu.halt);
    expectFn(fn () void, x86.Cpu.pause);
    expectFn(fn () void, x86.Cpu.breakpoint);
}

test "compile: Descriptor table family instantiates" {
    if (!x86.supported) return;
    expectFn(fn (*const x86.Descriptor.Pointer) void, x86.Descriptor.Gdt.load);
    expectFn(fn () x86.Descriptor.Pointer, x86.Descriptor.Gdt.store);
    expectFn(fn (*const x86.Descriptor.Pointer) void, x86.Descriptor.Idt.load);
    expectFn(fn () x86.Descriptor.Pointer, x86.Descriptor.Idt.store);
    expectFn(fn (u16) void, x86.Descriptor.TaskRegister.load);
    expectFn(fn () u16, x86.Descriptor.TaskRegister.store);
}

test "compile: Segment register family instantiates" {
    if (!x86.supported) return;
    expectFn(fn () u16, x86.Segment.Cs.read);
    expectFn(fn (u16) void, x86.Segment.Cs.writeFarReturn);
    expectFn(fn () u16, x86.Segment.Ds.read);
    expectFn(fn (u16) void, x86.Segment.Ds.write);
    expectFn(fn () u16, x86.Segment.Es.read);
    expectFn(fn (u16) void, x86.Segment.Es.write);
    expectFn(fn () u16, x86.Segment.Fs.read);
    expectFn(fn (u16) void, x86.Segment.Fs.write);
    expectFn(fn () u16, x86.Segment.Gs.read);
    expectFn(fn (u16) void, x86.Segment.Gs.write);
    expectFn(fn () u16, x86.Segment.Ss.read);
    expectFn(fn (u16) void, x86.Segment.Ss.write);
    expectFn(fn () u64, x86.Segment.FsBase.read);
    expectFn(fn (u64) void, x86.Segment.FsBase.write);
    expectFn(fn () u64, x86.Segment.GsBase.read);
    expectFn(fn (u64) void, x86.Segment.GsBase.write);
    expectFn(fn () void, x86.Segment.swapGs);
}

test "compile: Fence family instantiates" {
    if (!x86.supported) return;
    expectFn(fn () void, x86.Fence.lfence);
    expectFn(fn () void, x86.Fence.sfence);
    expectFn(fn () void, x86.Fence.mfence);
}

test "compile: Cache family instantiates" {
    if (!x86.supported) return;
    expectFn(fn () usize, x86.Cache.lineSize);
    expectFn(fn (usize) void, x86.Cache.flush);
    expectFn(fn (usize) void, x86.Cache.flushOptimized);
    expectFn(fn (usize) void, x86.Cache.writeBack);
    expectFn(fn ([*]const u8, usize) void, x86.Cache.flushRange);
    expectFn(fn ([*]const u8, usize) void, x86.Cache.writeBackRange);
    expectFn(fn () void, x86.Cache.writeBackInvalidate);
    expectFn(fn () void, x86.Cache.invalidate);
}

test "compile: Privilege.currentLevel and ioWait instantiate" {
    if (!x86.supported) return;
    expectFn(fn () u2, x86.Privilege.currentLevel);
    expectFn(fn () void, x86.ioWait);
}

// ---------------- Host-safe runtime tests ----------------
//
// Only unprivileged instructions that do not modify global CPU state are
// exercised. The default host test suite must observe nothing privileged.

test "host: Cpuid.maxBasicLeaf reports at least leaf 1" {
    if (!x86.supported) return;
    try testing.expect(x86.Cpuid.maxBasicLeaf() >= 1);
}

test "host: Cpuid.maxExtendedLeaf reports at least 0x80000000" {
    if (!x86.supported) return;
    try testing.expect(x86.Cpuid.maxExtendedLeaf() >= 0x80000000);
}

test "host: Cpu.pause executes once" {
    if (!x86.supported) return;
    x86.Cpu.pause();
}

test "host: Fence.lfence/sfence/mfence each execute once" {
    if (!x86.supported) return;
    x86.Fence.lfence();
    x86.Fence.sfence();
    x86.Fence.mfence();
}

test "host: Rflags.read returns a value with reserved bit 1 set" {
    if (!x86.supported) return;
    const flags = x86.Rflags.read();
    try testing.expect((flags & 0b10) != 0);
}

test "host: Privilege.currentLevel returns the userspace CPL" {
    if (!x86.supported) return;
    // The default host test suite always runs in userspace at CPL 3.
    try testing.expectEqual(@as(u2, 3), x86.Privilege.currentLevel());
}
