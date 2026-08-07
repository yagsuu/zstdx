const std = @import("std");
const x86 = @import("stdx").arch.x86_64;
const privilege = x86.privilege;

const testing = std.testing;

test "compile: current privilege level instantiates" {
    if (!x86.supported) return;
    comptime testing.expectEqual(fn () u2, @TypeOf(privilege.currentLevel)) catch unreachable;
}

test "host: current privilege level is readable" {
    if (!x86.supported) return;
    try testing.expectEqual(@as(u2, 3), privilege.currentLevel());
}
