//! Per-CPU storage primitives. See `docs/specs/cpu/per_cpu.md`.

pub const per_cpu = @import("per_cpu.zig");

pub const PerCPU = per_cpu.PerCPU;
