//! Per-CPU storage primitives. See docs/specs/cpu/per-cpu.md.

pub const per_cpu = @import("cpu/per_cpu.zig");

pub const PerCpu = per_cpu.PerCpu;
