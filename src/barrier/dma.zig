//! DMA paired fences. See `docs/specs/barrier/dma.md`. Each operation uses
//! `@compileError` on non-x86_64 targets.

const builtin = @import("builtin");

const x86_64 = @import("../arch/x86_64.zig");

const wrong_target = "stdx.barrier.dma: unsupported target; requires an arch spec beyond arch/x86_64";

/// Orders prior stores to caller memory before a following store that the
/// device observes through DMA. Emits `sfence` on x86_64 with a `memory`
/// clobber. Cache-maintenance sequences are not owned by this API.
pub inline fn release() void {
    if (builtin.cpu.arch != .x86_64) @compileError(wrong_target);
    x86_64.fence.sfence();
}

/// Orders a preceding load of DMA-written data before subsequent loads from
/// related caller memory. Emits `lfence` on x86_64 with a `memory` clobber.
pub inline fn acquire() void {
    if (builtin.cpu.arch != .x86_64) @compileError(wrong_target);
    x86_64.fence.lfence();
}

/// Orders prior DMA-visible stores before subsequent DMA-visible loads on the
/// same CPU. Emits `mfence` on x86_64 with a `memory` clobber.
pub inline fn releaseAcquire() void {
    if (builtin.cpu.arch != .x86_64) @compileError(wrong_target);
    x86_64.fence.mfence();
}
