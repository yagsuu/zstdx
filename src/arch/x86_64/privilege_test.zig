const std = @import("std");
const x86 = @import("target.zig");
const privilege = @import("privilege.zig");

const testing = std.testing;

test "host: current privilege level is readable" {
    if (!x86.supported) return;
    try testing.expectEqual(@as(u2, 3), privilege.currentLevel());
}
