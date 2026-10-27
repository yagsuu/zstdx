//! per-CPU storage

pub const per_cpu = @import("per_cpu.zig");

pub const PerCpu = per_cpu.PerCpu;

test {
    _ = per_cpu.unit;
}
