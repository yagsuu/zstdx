const assertLayout = @import("stdx").layout.assertLayout;

const Record = extern struct { value: u32 };

export fn rejectOffset() void {
    assertLayout(Record, .{ .offsets = .{ .value = 1 } });
}
