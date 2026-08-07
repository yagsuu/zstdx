const std = @import("std");
const builtin = @import("builtin");
const x86 = @import("stdx").arch.x86_64;
const cpu = x86.cpu;
const cpuid = x86.cpuid;

const testing = std.testing;

comptime {
    std.debug.assert(@FieldType(cpu.tsc.Reading, "tsc") == u64);
    std.debug.assert(@FieldType(cpu.tsc.Reading, "aux") == u32);
}

test "contract: TSC accessors instantiate" {
    if (!x86.supported) return;
    comptime {
        testing.expectEqual(fn () u64, @TypeOf(cpu.tsc.read)) catch unreachable;
        testing.expectEqual(fn () cpu.tsc.Reading, @TypeOf(cpu.tsc.readSerializing)) catch unreachable;
    }
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
