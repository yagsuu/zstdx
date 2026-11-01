const assertLayout = @import("stdx").layout.assertLayout;

export fn rejectSize() void {
    assertLayout(u32, .{ .size = 3 });
}
