//! DMA fence tests. Spec: docs/specs/barrier/dma.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const testing = std.testing;

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "unit: dma.release executes once without trapping on x86_64" {
    if (builtin.cpu.arch != .x86_64) return;
    stdx.barrier.dma.release();
}

test "unit: dma.acquire executes once without trapping on x86_64" {
    if (builtin.cpu.arch != .x86_64) return;
    stdx.barrier.dma.acquire();
}

test "unit: dma.releaseAcquire executes once without trapping on x86_64" {
    if (builtin.cpu.arch != .x86_64) return;
    stdx.barrier.dma.releaseAcquire();
}

test "compile: dma ops are all pub inline fn () void" {
    expectFn(fn () callconv(.@"inline") void, stdx.barrier.dma.release);
    expectFn(fn () callconv(.@"inline") void, stdx.barrier.dma.acquire);
    expectFn(fn () callconv(.@"inline") void, stdx.barrier.dma.releaseAcquire);
}
