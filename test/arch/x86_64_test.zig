//! x86_64 architecture primitives contract tests.
//! Specs: docs/specs/arch/x86_64/base.md and register.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const x86 = stdx.arch.x86_64;
const cpuid = x86.cpuid;
const registers = x86.registers;
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

test "unit: MSR named tags match architectural addresses" {
    try testing.expectEqual(@as(u32, 0x0000_0010), x86.MSR.tsc.raw());
    try testing.expectEqual(@as(u32, 0x0000_001b), x86.MSR.apic_base.raw());
    try testing.expectEqual(@as(u32, 0xc000_0080), x86.MSR.efer.raw());
    try testing.expectEqual(@as(u32, 0xc000_0100), x86.MSR.fs_base.raw());
    try testing.expectEqual(@as(u32, 0xc001_0117), x86.MSR.vm_hsave_pa.raw());
}

test "unit: supported matches the build target" {
    try testing.expectEqual(builtin.cpu.arch == .x86_64, x86.supported);
}

test "model: register scalar representations preserve every bit" {
    const scalar_types = [_]type{
        registers.cr0.CR0,        registers.cr2.CR2,   registers.cr3.CR3,       registers.cr4.CR4,
        registers.cr8.CR8,        registers.xcr0.XCR0, registers.rflags.RFLAGS, registers.fs_base.FSBase,
        registers.gs_base.GSBase, registers.dr0.DR0,   registers.dr1.DR1,       registers.dr2.DR2,
        registers.dr3.DR3,        registers.dr4.DR4,   registers.dr5.DR5,       registers.dr6.DR6,
        registers.dr7.DR7,
    };

    inline for (scalar_types) |T| {
        try testing.expectEqual(@as(usize, 8), @sizeOf(T));
        try testing.expectEqual(@as(u64, 0xa5f3_5ca9_3d7e_1c42), T.fromInt(0xa5f3_5ca9_3d7e_1c42).raw());
    }
}

test "model: selector representations preserve every bit" {
    const selector_types = [_]type{ registers.cs.CS, registers.ds.DS, registers.es.ES, registers.fs.FS, registers.gs.GS, registers.ss.SS, registers.tr.TR, registers.ldtr.LDTR };

    inline for (selector_types) |T| {
        try testing.expectEqual(@as(usize, 2), @sizeOf(T));
        try testing.expectEqual(@as(u16, 0xa5f3), T.fromInt(0xa5f3).raw());
    }
}

test "model: pseudo-descriptors have the specified layout" {
    inline for (.{ registers.gdtr.GDTR, registers.idtr.IDTR }) |T| {
        try testing.expectEqual(@as(usize, 10), @sizeOf(T));
        try testing.expectEqual(@as(usize, 2), @alignOf(T));
        try testing.expectEqual(@as(usize, 0), @offsetOf(T, "limit"));
        try testing.expectEqual(@as(usize, 2), @offsetOf(T, "base"));
    }
}

test "model: register initialization sets canonical defaults" {
    try testing.expectEqual(@as(u64, 1 << 4), registers.cr0.CR0.init().raw());
    try testing.expectEqual(@as(u64, 0), registers.cr2.CR2.init().raw());
    try testing.expectEqual(@as(u64, 0), registers.cr3.CR3.init().raw());
    try testing.expectEqual(@as(u64, 0), registers.cr4.CR4.init().raw());
    try testing.expectEqual(@as(u64, 0), registers.cr8.CR8.init().raw());
    try testing.expectEqual(@as(u64, 1), registers.xcr0.XCR0.init().raw());
    try testing.expectEqual(@as(u64, 0b10), registers.rflags.RFLAGS.init().raw());
    try testing.expectEqual(@as(u64, 1 << 10), registers.dr7.DR7.init().raw());
    try testing.expectEqual(@as(u16, 0), registers.cs.CS.init().raw());
    try testing.expectEqual(@as(u64, 0), registers.fs_base.FSBase.init().raw());
    try testing.expectEqual(@as(u16, 0), registers.gdtr.GDTR.init().limit);
    try testing.expectEqual(@as(u64, 0), registers.gdtr.GDTR.init().base);
}

test "model: CR0 and CR4 fields match architectural bit positions" {
    try testing.expect(registers.cr0.CR0.fromInt(1 << 0).protection_enable);
    try testing.expect(registers.cr0.CR0.fromInt(1 << 31).paging);
    try testing.expect(registers.cr4.CR4.fromInt(1 << 5).physical_address_extension);
    try testing.expect(registers.cr4.CR4.fromInt(1 << 18).osxsave);
}

test "model: RFLAGS and DR6 fields match architectural bit positions" {
    try testing.expect(registers.rflags.RFLAGS.fromInt(1 << 9).interrupt_enable);
    try testing.expect(registers.dr6.DR6.fromInt(1 << 15).task_switch);
    try testing.expectEqual(@as(u2, 3), registers.dr7.DR7.fromInt(3 << 16).br0.condition);
    try testing.expectEqual(@as(u2, 3), registers.dr7.DR7.fromInt(3 << 18).br0.length);
}

test "model: selector fields and types remain distinct" {
    const cs = registers.cs.CS.fromInt(0xffff);
    try testing.expectEqual(@as(u2, 3), cs.rpl);
    try testing.expectEqual(.ldt, cs.table);
    try testing.expectEqual(@as(u13, 0x1fff), cs.index);

    comptime {
        testing.expect(registers.cs.CS != registers.ds.DS) catch unreachable;
        testing.expect(registers.gdtr.GDTR != registers.idtr.IDTR) catch unreachable;
        testing.expect(registers.dr0.DR0 != registers.dr1.DR1) catch unreachable;
    }
}

test "model: CR8 and XCR0 fields match architectural bit positions" {
    try testing.expectEqual(@as(u4, 0xf), registers.cr8.CR8.fromInt(0xf).task_priority);
    try testing.expect(registers.xcr0.XCR0.fromInt(1 << 7).hi16_zmm);
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

test "compile: cpuid and MSR families instantiate" {
    if (!x86.supported) return;
    expectFn(fn (cpuid.Leaf) cpuid.Result, cpuid.leaf);
    expectFn(fn (cpuid.Leaf, u32) cpuid.Result, cpuid.subleaf);
    expectFn(fn (x86.MSR) u64, x86.MSR.read);
    expectFn(fn (x86.MSR, u64) void, x86.MSR.write);
}

test "compile: register control family instantiates" {
    if (!x86.supported) return;
    expectFn(fn () registers.cr0.CR0, registers.cr0.read);
    expectFn(fn (registers.cr0.CR0) void, registers.cr0.write);
    expectFn(fn () registers.cr2.CR2, registers.cr2.read);
    expectFn(fn (registers.cr2.CR2) void, registers.cr2.write);
    expectFn(fn () registers.cr3.CR3, registers.cr3.read);
    expectFn(fn (registers.cr3.CR3) void, registers.cr3.write);
    expectFn(fn () registers.cr4.CR4, registers.cr4.read);
    expectFn(fn (registers.cr4.CR4) void, registers.cr4.write);
    expectFn(fn () registers.cr8.CR8, registers.cr8.read);
    expectFn(fn (registers.cr8.CR8) void, registers.cr8.write);
    expectFn(fn () registers.xcr0.XCR0, registers.xcr0.read);
    expectFn(fn (registers.xcr0.XCR0) void, registers.xcr0.write);
}

test "compile: register flags and segment families instantiate" {
    if (!x86.supported) return;
    expectFn(fn () registers.rflags.RFLAGS, registers.rflags.read);
    expectFn(fn (registers.rflags.RFLAGS) void, registers.rflags.write);
    expectFn(fn () registers.cs.CS, registers.cs.read);
    expectFn(fn (registers.cs.CS) void, registers.cs.writeFarReturn);
    expectFn(fn () registers.ds.DS, registers.ds.read);
    expectFn(fn (registers.ds.DS) void, registers.ds.write);
    expectFn(fn () registers.es.ES, registers.es.read);
    expectFn(fn (registers.es.ES) void, registers.es.write);
    expectFn(fn () registers.fs.FS, registers.fs.read);
    expectFn(fn (registers.fs.FS) void, registers.fs.write);
    expectFn(fn () registers.gs.GS, registers.gs.read);
    expectFn(fn (registers.gs.GS) void, registers.gs.write);
    expectFn(fn () registers.ss.SS, registers.ss.read);
    expectFn(fn (registers.ss.SS) void, registers.ss.write);
    expectFn(fn () registers.fs_base.FSBase, registers.fs_base.read);
    expectFn(fn (registers.fs_base.FSBase) void, registers.fs_base.write);
    expectFn(fn () registers.gs_base.GSBase, registers.gs_base.read);
    expectFn(fn (registers.gs_base.GSBase) void, registers.gs_base.write);
    expectFn(fn () void, registers.gs_base.swap);
}

test "compile: register descriptor and debug families instantiate" {
    if (!x86.supported) return;
    expectFn(fn (registers.gdtr.GDTR) void, registers.gdtr.write);
    expectFn(fn () registers.gdtr.GDTR, registers.gdtr.read);
    expectFn(fn (registers.idtr.IDTR) void, registers.idtr.write);
    expectFn(fn () registers.idtr.IDTR, registers.idtr.read);
    expectFn(fn (registers.tr.TR) void, registers.tr.write);
    expectFn(fn () registers.tr.TR, registers.tr.read);
    expectFn(fn (registers.ldtr.LDTR) void, registers.ldtr.write);
    expectFn(fn () registers.ldtr.LDTR, registers.ldtr.read);
    expectFn(fn () registers.dr0.DR0, registers.dr0.read);
    expectFn(fn (registers.dr0.DR0) void, registers.dr0.write);
    expectFn(fn () registers.dr7.DR7, registers.dr7.read);
    expectFn(fn (registers.dr7.DR7) void, registers.dr7.write);
}

test "compile: remaining x86 families instantiate" {
    if (!x86.supported) return;
    expectFn(fn () void, interrupts.enable);
    expectFn(fn () void, interrupts.disable);
    expectFn(fn () bool, interrupts.enabled);
    expectFn(fn () void, cpu.halt);
    expectFn(fn () void, cpu.pause);
    expectFn(fn () void, fence.lfence);
    expectFn(fn () usize, cache.lineSize);
    expectFn(fn () u2, privilege.currentLevel);
}

test "host: cpuid.maxBasicLeaf reports at least leaf 1" {
    if (!x86.supported) return;
    try testing.expect(cpuid.maxBasicLeaf() >= 1);
}

test "host: cpu.pause and fences execute once" {
    if (!x86.supported) return;
    cpu.pause();
    fence.lfence();
    fence.sfence();
    fence.mfence();
}

test "host: register RFLAGS and current privilege level are readable" {
    if (!x86.supported) return;
    try testing.expect(registers.rflags.read().fixed_one);
    try testing.expectEqual(@as(u2, 3), privilege.currentLevel());
}
