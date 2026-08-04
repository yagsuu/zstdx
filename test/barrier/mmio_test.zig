//! MMIO fence tests. See `docs/specs/barrier/dma.md`.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const testing = std.testing;

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "unit: mmio.release executes once without trapping on x86_64" {
    if (builtin.cpu.arch != .x86_64) return;
    stdx.barrier.mmio.release();
}

test "unit: mmio.acquire executes once without trapping on x86_64" {
    if (builtin.cpu.arch != .x86_64) return;
    stdx.barrier.mmio.acquire();
}

test "unit: mmio.releaseAcquire executes once without trapping on x86_64" {
    if (builtin.cpu.arch != .x86_64) return;
    stdx.barrier.mmio.releaseAcquire();
}

test "compile: mmio ops are all pub inline fn () void" {
    expectFn(fn () callconv(.@"inline") void, stdx.barrier.mmio.release);
    expectFn(fn () callconv(.@"inline") void, stdx.barrier.mmio.acquire);
    expectFn(fn () callconv(.@"inline") void, stdx.barrier.mmio.releaseAcquire);
}
