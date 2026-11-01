const assertLayout = @import("stdx").layout.assertLayout;

export fn rejectAlignment() void {
    assertLayout([4]u8, .{ .alignment = 3 });
}
