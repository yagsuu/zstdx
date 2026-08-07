const std = @import("std");
const x86 = @import("stdx").arch.x86_64;
const cache = x86.cache;

const testing = std.testing;

test "compile: cache line size instantiates" {
    if (!x86.supported) return;
    comptime testing.expectEqual(fn () usize, @TypeOf(cache.lineSize)) catch unreachable;
}
