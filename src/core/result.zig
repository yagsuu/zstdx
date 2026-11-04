pub fn Result(comptime Value: type, comptime Error: type) type {
    return union(enum) {
        ok: Value,
        err: Error,

        const Self = @This();

        pub fn unwrap(self: Self) Error!Value {
            return switch (self) {
                .ok => |value| value,
                .err => |err| err,
            };
        }
    };
}

pub fn ResultExt(comptime Value: type, comptime Error: type, comptime Context: type) type {
    return union(enum) {
        ok: Value,
        err: struct {
            err: Error,
            context: Context,
        },

        const Self = @This();

        pub fn unwrap(self: Self) Error!Value {
            return switch (self) {
                .ok => |value| value,
                .err => |failure| failure.err,
            };
        }

        pub fn unwrapWith(self: Self, context: *Context) Error!Value {
            return switch (self) {
                .ok => |value| value,
                .err => |failure| {
                    context.* = failure.context;
                    return failure.err;
                },
            };
        }
    };
}

pub const unit = struct {
    const testing = @import("std").testing;

    test "result unwrap preserves values and propagates errors" {
        const R = Result(u32, error{Denied});
        const success: R = .{ .ok = 42 };
        const failure: R = .{ .err = error.Denied };

        try testing.expectEqual(@as(u32, 42), try success.unwrap());
        try testing.expectError(error.Denied, failure.unwrap());
    }

    test "extended result supplies failure context without changing it on success" {
        const Context = struct { offset: usize };
        const R = ResultExt(u32, error{Truncated}, Context);
        const success: R = .{ .ok = 7 };
        const failure: R = .{ .err = .{
            .err = error.Truncated,
            .context = .{ .offset = 12 },
        } };
        var context: Context = .{ .offset = 99 };

        try testing.expectEqual(@as(u32, 7), try success.unwrap());
        try testing.expectError(error.Truncated, failure.unwrap());
        try testing.expectEqual(@as(u32, 7), try success.unwrapWith(&context));
        try testing.expectEqual(@as(usize, 99), context.offset);
        try testing.expectError(error.Truncated, failure.unwrapWith(&context));
        try testing.expectEqual(@as(usize, 12), context.offset);
    }
};
