//! Compiler reorder barrier tests. See `docs/specs/barrier/dma.md`.

const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "unit: compiler executes once without trapping" {
    stdx.barrier.compiler();
}

test "compile: stdx.barrier.compiler is pub inline fn () void" {
    expectFn(fn () callconv(.@"inline") void, stdx.barrier.compiler);
}
