const std = @import("std");
const x86 = @import("stdx").arch.x86_64;
const fence = x86.fence;

const testing = std.testing;

test "compile: fence wrappers instantiate" {
    if (!x86.supported) return;
    comptime testing.expectEqual(fn () void, @TypeOf(fence.lfence)) catch unreachable;
}

test "host: fences execute once" {
    if (!x86.supported) return;
    fence.lfence();
    fence.sfence();
    fence.mfence();
}
