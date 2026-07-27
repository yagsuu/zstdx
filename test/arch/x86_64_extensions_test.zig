//! x86_64 architecture extensions contract tests.
//! Spec: docs/specs/arch/x86_64/extensions.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const x86 = stdx.arch.x86_64;
const cpuid = x86.cpuid;
const registers = x86.registers;
const cpu = x86.cpu;

const testing = std.testing;

comptime {
    std.debug.assert(@sizeOf(cpu.tlb.INVPCIDDescriptor) == 16);
    std.debug.assert(@alignOf(cpu.tlb.INVPCIDDescriptor) == 16);
    std.debug.assert(@offsetOf(cpu.tlb.INVPCIDDescriptor, "pcid") == 0);
    std.debug.assert(@offsetOf(cpu.tlb.INVPCIDDescriptor, "linear_address") == 8);
    std.debug.assert(cpu.tlb.INVPCIDDescriptor.alignment == 16);

    const kind_info = @typeInfo(cpu.tlb.INVPCIDKind).@"enum";
    std.debug.assert(kind_info.fields.len == 4);
    std.debug.assert(kind_info.tag_type == u2);
    std.debug.assert(@intFromEnum(cpu.tlb.INVPCIDKind.individual_address) == 0);
    std.debug.assert(@intFromEnum(cpu.tlb.INVPCIDKind.single_context) == 1);
    std.debug.assert(@intFromEnum(cpu.tlb.INVPCIDKind.all_including_globals) == 2);
    std.debug.assert(@intFromEnum(cpu.tlb.INVPCIDKind.all_excluding_globals) == 3);

    std.debug.assert(@FieldType(cpu.tsc.Reading, "tsc") == u64);
    std.debug.assert(@FieldType(cpu.tsc.Reading, "aux") == u32);

    for (.{
        registers.dr0.DR0,
        registers.dr1.DR1,
        registers.dr2.DR2,
        registers.dr3.DR3,
        registers.dr4.DR4,
        registers.dr5.DR5,
        registers.dr6.DR6,
        registers.dr7.DR7,
    }) |T| {
        std.debug.assert(@sizeOf(T) == 8);
    }
}

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "contract: cpu.tsc read/readSerializing instantiate" {
    if (!x86.supported) return;
    expectFn(fn () u64, cpu.tsc.read);
    expectFn(fn () cpu.tsc.Reading, cpu.tsc.readSerializing);
}

test "contract: cpu.tlb invalidatePage/invalidatePCID instantiate" {
    if (!x86.supported) return;
    expectFn(fn (usize) void, cpu.tlb.invalidatePage);
    expectFn(fn (cpu.tlb.INVPCIDKind, *const cpu.tlb.INVPCIDDescriptor) void, cpu.tlb.invalidatePCID);
}

test "contract: register debug dr0..dr7 read/write instantiate" {
    if (!x86.supported) return;
    expectFn(fn () registers.dr0.DR0, registers.dr0.read);
    expectFn(fn (registers.dr0.DR0) void, registers.dr0.write);
    expectFn(fn () registers.dr1.DR1, registers.dr1.read);
    expectFn(fn (registers.dr1.DR1) void, registers.dr1.write);
    expectFn(fn () registers.dr2.DR2, registers.dr2.read);
    expectFn(fn (registers.dr2.DR2) void, registers.dr2.write);
    expectFn(fn () registers.dr3.DR3, registers.dr3.read);
    expectFn(fn (registers.dr3.DR3) void, registers.dr3.write);
    expectFn(fn () registers.dr4.DR4, registers.dr4.read);
    expectFn(fn (registers.dr4.DR4) void, registers.dr4.write);
    expectFn(fn () registers.dr5.DR5, registers.dr5.read);
    expectFn(fn (registers.dr5.DR5) void, registers.dr5.write);
    expectFn(fn () registers.dr6.DR6, registers.dr6.read);
    expectFn(fn (registers.dr6.DR6) void, registers.dr6.write);
    expectFn(fn () registers.dr7.DR7, registers.dr7.read);
    expectFn(fn (registers.dr7.DR7) void, registers.dr7.write);
}

test "contract: register LDTR read/write instantiate" {
    if (!x86.supported) return;
    expectFn(fn (registers.ldtr.LDTR) void, registers.ldtr.write);
    expectFn(fn () registers.ldtr.LDTR, registers.ldtr.read);
}

test "unit: cpu.tsc.read is monotonic across two calls" {
    if (builtin.cpu.arch != .x86_64) return;
    const before = cpu.tsc.read();
    const after = cpu.tsc.read();
    try testing.expect(after >= before);
}

test "unit: cpu.tsc.readSerializing.tsc is monotonic against a prior rdtsc" {
    if (builtin.cpu.arch != .x86_64) return;
    if (cpuid.maxExtendedLeaf() < 0x8000_0001) return;
    if (!cpuid.extendedFeatures().edx.rdtscp) return;

    const previous = cpu.tsc.read();
    const reading = cpu.tsc.readSerializing();
    try testing.expect(reading.tsc >= previous);
    _ = reading.aux;
}
