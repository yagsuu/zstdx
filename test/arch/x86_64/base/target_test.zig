const std = @import("std");
const builtin = @import("builtin");
const x86 = @import("stdx").arch.x86_64;

const testing = std.testing;

test "unit: supported matches the build target" {
    try testing.expectEqual(builtin.cpu.arch == .x86_64, x86.supported);
}
