//! x86_64 architecture extensions contract tests.
//! Spec: docs/specs/arch/x86_64/extensions.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const x86 = stdx.arch.x86_64;
const cpuid = x86.cpuid;
const register = x86.register;
const cpu = x86.cpu;

const testing = std.testing;

// Compile-time assertions pin the required layouts, enum tags, and namespace
// shape. Privileged operations stay signature-only in the host suite.

comptime {
    // cpu.tlb.INVPCIDDescriptor: exactly 16 bytes, 16-byte aligned, PCID at 0,
    // linear_address at 8. Spec §CPU.TLB.
    std.debug.assert(@sizeOf(cpu.tlb.INVPCIDDescriptor) == 16);
    std.debug.assert(@alignOf(cpu.tlb.INVPCIDDescriptor) == 16);
    std.debug.assert(@offsetOf(cpu.tlb.INVPCIDDescriptor, "pcid") == 0);
    std.debug.assert(@offsetOf(cpu.tlb.INVPCIDDescriptor, "linear_address") == 8);
    std.debug.assert(cpu.tlb.INVPCIDDescriptor.alignment == 16);

    // cpu.tlb.INVPCIDKind: four tags with backing values 0..3 in enum-declaration
    // order matching the spec table. Spec §CPU.TLB "INVPCIDKind values".
    const kind_info = @typeInfo(cpu.tlb.INVPCIDKind).@"enum";
    std.debug.assert(kind_info.fields.len == 4);
    std.debug.assert(kind_info.tag_type == u2);
    std.debug.assert(@intFromEnum(cpu.tlb.INVPCIDKind.individual_address) == 0);
    std.debug.assert(@intFromEnum(cpu.tlb.INVPCIDKind.single_context) == 1);
    std.debug.assert(@intFromEnum(cpu.tlb.INVPCIDKind.all_including_globals) == 2);
    std.debug.assert(@intFromEnum(cpu.tlb.INVPCIDKind.all_excluding_globals) == 3);

    // cpu.tsc.Reading: fields are exactly u64 (tsc) and u32 (aux). Spec
    // §Cpu.Tsc Reading.
    std.debug.assert(@FieldType(cpu.tsc.Reading, "tsc") == u64);
    std.debug.assert(@FieldType(cpu.tsc.Reading, "aux") == u32);

    // register.debug: eight sub-types dr0..dr7, each exposing read() and
    // write(u64). Spec §DebugRegister approved API. Rejected shapes:
    //   - Any `drN` where `N` is not one of 0..7 does not exist (the
    //     `register.debug` namespace only declares those eight);
    //   - Missing `read`/`write` on any `drN` — every slot uses the same
    //     `DebugRegSlot` factory in `src/arch/x86_64/register/debug.zig`.
    std.debug.assert(@TypeOf(register.debug.dr0.read) == fn () u64);
    std.debug.assert(@TypeOf(register.debug.dr1.read) == fn () u64);
    std.debug.assert(@TypeOf(register.debug.dr2.read) == fn () u64);
    std.debug.assert(@TypeOf(register.debug.dr3.read) == fn () u64);
    std.debug.assert(@TypeOf(register.debug.dr4.read) == fn () u64);
    std.debug.assert(@TypeOf(register.debug.dr5.read) == fn () u64);
    std.debug.assert(@TypeOf(register.debug.dr6.read) == fn () u64);
    std.debug.assert(@TypeOf(register.debug.dr7.read) == fn () u64);
    std.debug.assert(@TypeOf(register.debug.dr0.write) == fn (u64) void);
    std.debug.assert(@TypeOf(register.debug.dr7.write) == fn (u64) void);
}

// Compile-only instantiation tests validating the spec's "Compile-only"
// required-test bullets on x86_64 targets: every asm-emitting entry point
// exists with the exact signature. Bodies are not codegenned; privileged
// operations (dr*, invlpg, invpcid, lldt) are compile-only per spec —
// runtime coverage requires a kernel harness.

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

test "contract: register.debug dr0..dr7 read/write instantiate" {
    if (!x86.supported) return;
    expectFn(fn () u64, register.debug.dr0.read);
    expectFn(fn (u64) void, register.debug.dr0.write);
    expectFn(fn () u64, register.debug.dr1.read);
    expectFn(fn (u64) void, register.debug.dr1.write);
    expectFn(fn () u64, register.debug.dr2.read);
    expectFn(fn (u64) void, register.debug.dr2.write);
    expectFn(fn () u64, register.debug.dr3.read);
    expectFn(fn (u64) void, register.debug.dr3.write);
    expectFn(fn () u64, register.debug.dr4.read);
    expectFn(fn (u64) void, register.debug.dr4.write);
    expectFn(fn () u64, register.debug.dr5.read);
    expectFn(fn (u64) void, register.debug.dr5.write);
    expectFn(fn () u64, register.debug.dr6.read);
    expectFn(fn (u64) void, register.debug.dr6.write);
    expectFn(fn () u64, register.debug.dr7.read);
    expectFn(fn (u64) void, register.debug.dr7.write);
}

test "contract: register.descriptor.ldtr load/store instantiate" {
    if (!x86.supported) return;
    expectFn(fn (u16) void, register.descriptor.ldtr.load);
    expectFn(fn () u16, register.descriptor.ldtr.store);
    comptime {
        _ = &register.descriptor.ldtr.store;
        _ = &register.descriptor.ldtr.load;
    }
}

// Host runtime coverage stays limited to unprivileged, non-mutating
// instructions.

test "unit: cpu.tsc.read is monotonic across two calls" {
    if (builtin.cpu.arch != .x86_64) return;
    const before = cpu.tsc.read();
    const after = cpu.tsc.read();
    try testing.expect(after >= before);
}

test "unit: cpu.tsc.readSerializing.tsc is monotonic against a prior rdtsc" {
    if (builtin.cpu.arch != .x86_64) return;
    // Skip instead of triggering `#UD` on hosts without RDTSCP.
    if (cpuid.maxExtendedLeaf() < 0x8000_0001) return;
    if (!cpuid.extendedFeatures().edx.rdtscp) return;

    const previous = cpu.tsc.read();
    const reading = cpu.tsc.readSerializing();
    try testing.expect(reading.tsc >= previous);
    _ = reading.aux;
}
