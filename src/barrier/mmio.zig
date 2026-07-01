//! MMIO paired fences. See docs/specs/barrier/dma.md. Non-x86_64 targets
//! `@compileError` at every op.

const builtin = @import("builtin");

const x86_64 = @import("../arch/x86_64.zig");

const wrong_target = "stdx.barrier.mmio: unsupported target; requires an arch spec beyond arch/x86_64";

/// Order prior stores to caller memory before a following MMIO store reaches
/// the device. Emits `sfence` on x86_64 with a `memory` clobber. Not a
/// cross-CPU synchronization primitive beyond the ISA rules; does not flush
/// caches.
pub inline fn release() void {
    if (builtin.cpu.arch != .x86_64) @compileError(wrong_target);
    x86_64.Fence.sfence();
}

/// Order a preceding MMIO load before following memory reads. Emits `lfence`
/// on x86_64 with a `memory` clobber. Not a cross-CPU synchronization
/// primitive beyond the ISA rules.
pub inline fn acquire() void {
    if (builtin.cpu.arch != .x86_64) @compileError(wrong_target);
    x86_64.Fence.lfence();
}

/// Order prior stores and MMIO accesses before subsequent stores and loads on
/// the same CPU. Emits `mfence` on x86_64 with a `memory` clobber. Callers
/// who only need one direction use the cheaper `release` or `acquire`.
pub inline fn releaseAcquire() void {
    if (builtin.cpu.arch != .x86_64) @compileError(wrong_target);
    x86_64.Fence.mfence();
}
