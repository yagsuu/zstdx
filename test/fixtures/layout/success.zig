const assertLayout = @import("stdx").layout.assertLayout;

const Record = extern struct {
    first: u32,
    second: u32,
};

fn Generic(comptime T: type) type {
    return extern struct {
        value: T,
    };
}

export fn assertLayouts() void {
    assertLayout(Record, .{ .size = 8 });
    assertLayout(Record, .{ .alignment = @alignOf(Record) });
    assertLayout(Record, .{ .offsets = .{ .first = 0, .second = 4 } });
    assertLayout(Record, .{ .offsets = .{ .second = 4 } });
    assertLayout(Record, .{ .size = 8, .offsets = .{} });
    assertLayout(Record, .{ .size = null, .alignment = null, .offsets = .{ .first = null, .second = 4 } });
    assertLayout(u32, .{ .size = 4 });
    assertLayout(struct {}, .{ .size = 0, .alignment = 1 });
    assertLayout(Generic(u16), .{ .size = 2, .offsets = .{ .value = 0 } });
    assertLayout(Generic(u64), .{ .size = 8, .offsets = .{ .value = 0 } });
}
