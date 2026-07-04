//! x86_64 architecture extensions contract tests.
//! Spec: docs/specs/arch/x86_64/extensions.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const x86 = stdx.arch.x86_64;

const testing = std.testing;

// Compile-only structural tests pinning the layout, tag set, and namespace
// shape spelled out in the spec's "Required tests" section. `comptime
// std.debug.assert` matches the convention used by `test/tags/tag_test.zig`
// for compile-time-negative probes: positive shapes are asserted here; the
// trailing comments enumerate the shapes the source's `@compileError`
// gates reject.

comptime {
    // InvpcidDescriptor: exactly 16 bytes, 16-byte aligned, pcid at 0,
    // linear_address at 8. Spec §Cpu.Tlb.
    std.debug.assert(@sizeOf(x86.Cpu.Tlb.InvpcidDescriptor) == 16);
    std.debug.assert(@alignOf(x86.Cpu.Tlb.InvpcidDescriptor) == 16);
    std.debug.assert(@offsetOf(x86.Cpu.Tlb.InvpcidDescriptor, "pcid") == 0);
    std.debug.assert(@offsetOf(x86.Cpu.Tlb.InvpcidDescriptor, "linear_address") == 8);
    std.debug.assert(x86.Cpu.Tlb.InvpcidDescriptor.alignment == 16);

    // InvpcidKind: four tags with backing values 0..3 in enum-declaration
    // order matching the spec table. Spec §Cpu.Tlb "InvpcidKind values".
    const kind_info = @typeInfo(x86.Cpu.Tlb.InvpcidKind).@"enum";
    std.debug.assert(kind_info.fields.len == 4);
    std.debug.assert(kind_info.tag_type == u2);
    std.debug.assert(@intFromEnum(x86.Cpu.Tlb.InvpcidKind.individual_address) == 0);
    std.debug.assert(@intFromEnum(x86.Cpu.Tlb.InvpcidKind.single_context) == 1);
    std.debug.assert(@intFromEnum(x86.Cpu.Tlb.InvpcidKind.all_including_globals) == 2);
    std.debug.assert(@intFromEnum(x86.Cpu.Tlb.InvpcidKind.all_excluding_globals) == 3);

    // Cpu.Tsc.Reading: fields are exactly u64 (tsc) and u32 (aux). Spec
    // §Cpu.Tsc Reading.
    std.debug.assert(@FieldType(x86.Cpu.Tsc.Reading, "tsc") == u64);
    std.debug.assert(@FieldType(x86.Cpu.Tsc.Reading, "aux") == u32);

    // DebugRegister: eight sub-types Dr0..Dr7, each exposing read() and
    // write(u64). Spec §DebugRegister approved API. Rejected shapes:
    //   - Any `DrN` where `N` is not one of 0..7 does not exist (the
    //     `DebugRegister` namespace only declares those eight);
    //   - Missing `read`/`write` on any `DrN` — every slot uses the same
    //     `DebugRegSlot` factory in `src/arch/x86_64.zig`.
    std.debug.assert(@TypeOf(x86.DebugRegister.Dr0.read) == fn () u64);
    std.debug.assert(@TypeOf(x86.DebugRegister.Dr1.read) == fn () u64);
    std.debug.assert(@TypeOf(x86.DebugRegister.Dr2.read) == fn () u64);
    std.debug.assert(@TypeOf(x86.DebugRegister.Dr3.read) == fn () u64);
    std.debug.assert(@TypeOf(x86.DebugRegister.Dr4.read) == fn () u64);
    std.debug.assert(@TypeOf(x86.DebugRegister.Dr5.read) == fn () u64);
    std.debug.assert(@TypeOf(x86.DebugRegister.Dr6.read) == fn () u64);
    std.debug.assert(@TypeOf(x86.DebugRegister.Dr7.read) == fn () u64);
    std.debug.assert(@TypeOf(x86.DebugRegister.Dr0.write) == fn (u64) void);
    std.debug.assert(@TypeOf(x86.DebugRegister.Dr7.write) == fn (u64) void);
}

// Compile-only instantiation tests validating the spec's "Compile-only"
// required-test bullets on x86_64 targets: every asm-emitting entry point
// exists with the exact signature. Bodies are not codegenned; privileged
// operations (Dr*, invlpg, invpcid, lldt) are compile-only per spec —
// runtime coverage requires a kernel harness.

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "contract: Cpu.Tsc read/readSerializing instantiate" {
    if (!x86.supported) return;
    expectFn(fn () u64, x86.Cpu.Tsc.read);
    expectFn(fn () x86.Cpu.Tsc.Reading, x86.Cpu.Tsc.readSerializing);
}

test "contract: Cpu.Tlb invalidatePage/invalidatePcid instantiate" {
    if (!x86.supported) return;
    // Privileged (CPL 0); runtime coverage requires a kernel harness —
    // spec: extensions.md §"Trap and privilege behavior".
    expectFn(fn (usize) void, x86.Cpu.Tlb.invalidatePage);
    expectFn(fn (x86.Cpu.Tlb.InvpcidKind, *const x86.Cpu.Tlb.InvpcidDescriptor) void, x86.Cpu.Tlb.invalidatePcid);
}

test "contract: DebugRegister Dr0..Dr7 read/write instantiate" {
    if (!x86.supported) return;
    // Privileged (CPL 0); runtime coverage requires a kernel harness —
    // spec: extensions.md §"Trap and privilege behavior".
    expectFn(fn () u64, x86.DebugRegister.Dr0.read);
    expectFn(fn (u64) void, x86.DebugRegister.Dr0.write);
    expectFn(fn () u64, x86.DebugRegister.Dr1.read);
    expectFn(fn (u64) void, x86.DebugRegister.Dr1.write);
    expectFn(fn () u64, x86.DebugRegister.Dr2.read);
    expectFn(fn (u64) void, x86.DebugRegister.Dr2.write);
    expectFn(fn () u64, x86.DebugRegister.Dr3.read);
    expectFn(fn (u64) void, x86.DebugRegister.Dr3.write);
    expectFn(fn () u64, x86.DebugRegister.Dr4.read);
    expectFn(fn (u64) void, x86.DebugRegister.Dr4.write);
    expectFn(fn () u64, x86.DebugRegister.Dr5.read);
    expectFn(fn (u64) void, x86.DebugRegister.Dr5.write);
    expectFn(fn () u64, x86.DebugRegister.Dr6.read);
    expectFn(fn (u64) void, x86.DebugRegister.Dr6.write);
    expectFn(fn () u64, x86.DebugRegister.Dr7.read);
    expectFn(fn (u64) void, x86.DebugRegister.Dr7.write);
}

test "contract: Descriptor.Ldtr load/store instantiate" {
    if (!x86.supported) return;
    // Privileged (CPL 0) for `lldt`; runtime coverage requires a kernel
    // harness — spec: extensions.md §"Trap and privilege behavior".
    expectFn(fn (u16) void, x86.Descriptor.Ldtr.load);
    expectFn(fn () u16, x86.Descriptor.Ldtr.store);
    comptime {
        _ = &x86.Descriptor.Ldtr.store;
        _ = &x86.Descriptor.Ldtr.load;
    }
}

// Host-safe runtime tests: only unprivileged instructions that do not modify
// global CPU state are exercised. Non-x86 hosts early-return so the suite
// still compiles.

test "unit: Cpu.Tsc.read is monotonic across two calls" {
    if (builtin.cpu.arch != .x86_64) return;
    const before = x86.Cpu.Tsc.read();
    const after = x86.Cpu.Tsc.read();
    try testing.expect(after >= before);
}

test "unit: Cpu.Tsc.readSerializing.tsc is monotonic against a prior rdtsc" {
    if (builtin.cpu.arch != .x86_64) return;
    // `rdtscp` requires CPUID leaf 0x80000001 EDX[27]; on modern x86_64
    // hosts this is always true, but skip if the CPU somehow lacks it
    // rather than trigger `#UD`.
    if (x86.Cpuid.maxExtendedLeaf() < 0x8000_0001) return;
    if (!x86.Cpuid.extendedFeatures().edx.rdtscp) return;

    const previous = x86.Cpu.Tsc.read();
    const reading = x86.Cpu.Tsc.readSerializing();
    try testing.expect(reading.tsc >= previous);
    // `aux` is whatever the OS programmed into IA32_TSC_AUX; any u32 is
    // legal. Reference it so the compiler cannot discard the read.
    _ = reading.aux;
}
