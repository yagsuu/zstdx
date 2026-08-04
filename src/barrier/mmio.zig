//! MMIO paired fences. See `docs/specs/barrier/dma.md`. Each operation uses
//! `@compileError` on non-x86_64 targets.

const builtin = @import("builtin");

const x86_64 = @import("../arch/x86_64.zig");

const wrong_target = "stdx.barrier.mmio: unsupported target; requires an arch spec beyond arch/x86_64";

/// Orders prior stores to caller memory before a following MMIO store reaches
/// the device. Emits `sfence` on x86_64 with a `memory` clobber. It does not
/// synchronize across CPUs beyond the ISA rules or flush caches.
pub inline fn release() void {
    if (builtin.cpu.arch != .x86_64) @compileError(wrong_target);
    x86_64.fence.sfence();
}

/// Orders a preceding MMIO load before following memory reads. Emits `lfence`
/// on x86_64 with a `memory` clobber. It does not synchronize across CPUs
/// beyond the ISA rules.
pub inline fn acquire() void {
    if (builtin.cpu.arch != .x86_64) @compileError(wrong_target);
    x86_64.fence.lfence();
}

/// Orders prior stores and MMIO accesses before subsequent stores and loads on
/// the same CPU. Emits `mfence` on x86_64 with a `memory` clobber. Use the
/// cheaper `release` or `acquire` when only one direction is necessary.
pub inline fn releaseAcquire() void {
    if (builtin.cpu.arch != .x86_64) @compileError(wrong_target);
    x86_64.fence.mfence();
}
