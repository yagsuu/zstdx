//! signature validation and invocation thunks

const std = @import("std");

pub fn Thunk(
    comptime CB: type,
    comptime Context: type,
    comptime function: anytype,
    comptime label: []const u8,
) type {
    comptime requireBound(CB.Signature, Context, @TypeOf(function), label);

    return struct {
        pub fn invoke(erased: ?*anyopaque, args: CB.Args) CB.Return {
            const context: *Context = @ptrCast(@alignCast(erased.?));
            return @call(.auto, function, .{context} ++ args);
        }
    };
}

pub fn requireSignature(comptime Fn: type, comptime label: []const u8) void {
    const info = switch (@typeInfo(Fn)) {
        .@"fn" => |f| f,
        else => @compileError(
            label ++ ": " ++ @typeName(Fn) ++ " is not a function type",
        ),
    };

    if (info.is_generic) {
        @compileError(
            label ++ ": " ++ @typeName(Fn) ++
                " is a generic function (has comptime or anytype parameters); use a concrete signature",
        );
    }

    if (info.is_var_args) {
        @compileError(
            label ++ ": " ++ @typeName(Fn) ++
                " is variadic; variadics are not supported",
        );
    }

    if (info.return_type == null) {
        @compileError(
            label ++ ": " ++ @typeName(Fn) ++
                " has no return type (naked function); not supported",
        );
    }

    inline for (info.params, 0..) |p, i| {
        if (p.type == null) {
            @compileError(std.fmt.comptimePrint(
                "{s}: {s} parameter {d} has no concrete type (anytype)",
                .{ label, @typeName(Fn), i },
            ));
        }
    }
}

fn requireBound(
    comptime Fn: type,
    comptime Context: type,
    comptime Ptr: type,
    comptime label: []const u8,
) void {
    const ptr_info = switch (@typeInfo(Ptr)) {
        .pointer => |p| p,
        else => @compileError(
            label ++ ": " ++ @typeName(Ptr) ++ " is not a function pointer",
        ),
    };

    const Callee = ptr_info.child;

    const callee_info = switch (@typeInfo(Callee)) {
        .@"fn" => |f| f,
        else => @compileError(
            label ++ ": " ++ @typeName(Ptr) ++ " does not point to a function",
        ),
    };
    const fn_info = @typeInfo(Fn).@"fn";

    if (callee_info.is_generic) {
        @compileError(
            label ++ ": " ++ @typeName(Callee) ++ " is generic; concrete signature required",
        );
    }

    if (callee_info.is_var_args) {
        @compileError(
            label ++ ": " ++ @typeName(Callee) ++ " is variadic; not supported",
        );
    }

    if (callee_info.params.len != fn_info.params.len + 1) {
        @compileError(std.fmt.comptimePrint(
            "{s}: {s} has {d} parameters, expected {d} (context + signature)",
            .{ label, @typeName(Callee), callee_info.params.len, fn_info.params.len + 1 },
        ));
    }

    const first = callee_info.params[0].type orelse
        @compileError(label ++ ": " ++ @typeName(Callee) ++ " first parameter has no concrete type");

    if (first != *Context) {
        @compileError(
            label ++ ": " ++ @typeName(Callee) ++ " first parameter is " ++
                @typeName(first) ++ ", expected *" ++ @typeName(Context),
        );
    }

    inline for (fn_info.params, 0..) |p, i| {
        const expected = p.type.?;
        const got = callee_info.params[i + 1].type orelse
            @compileError(std.fmt.comptimePrint(
                "{s}: {s} parameter {d} has no concrete type",
                .{ label, @typeName(Callee), i + 1 },
            ));

        if (expected != got) {
            @compileError(std.fmt.comptimePrint(
                "{s}: {s} parameter {d} is {s}, expected {s}",
                .{ label, @typeName(Callee), i + 1, @typeName(got), @typeName(expected) },
            ));
        }
    }

    const expected_ret = fn_info.return_type.?;
    const got_ret = callee_info.return_type orelse
        @compileError(label ++ ": " ++ @typeName(Callee) ++ " has no return type");

    if (got_ret != expected_ret) {
        @compileError(
            label ++ ": " ++ @typeName(Callee) ++ " returns " ++ @typeName(got_ret) ++
                ", expected " ++ @typeName(expected_ret),
        );
    }
}

pub const unit = struct {
    const testing = std.testing;

    const Callback = @import("callback.zig").Callback;

    test "bound invocation preserves argument order and isolates contexts" {
        const State = struct {
            value: u32,

            pub fn update(self: *@This(), factor: u32, amount: u32) u32 {
                self.value = self.value * factor + amount;
                return self.value;
            }
        };

        const CB = Callback(fn (u32, u32) u32);
        const Bound = Thunk(CB, State, &State.update, "unit");

        var a: State = .{ .value = 2 };
        var b: State = .{ .value = 9 };

        const first = Bound.invoke(@ptrCast(&a), .{ 3, 4 });
        const second = Bound.invoke(@ptrCast(&b), .{ 2, 1 });
        const resumed = Bound.invoke(@ptrCast(&a), .{ 4, 2 });

        try testing.expectEqual(@as(u32, 10), first);
        try testing.expectEqual(@as(u32, 19), second);
        try testing.expectEqual(@as(u32, 42), resumed);
        try testing.expectEqual(@as(u32, 19), b.value);
    }

    test "bound invocations preserve context progress across an error" {
        const State = struct {
            remaining: u32,
            attempts: u32,

            pub fn spend(self: *@This(), amount: u32) error{Insufficient}!u32 {
                self.attempts += 1;
                if (amount > self.remaining) {
                    return error.Insufficient;
                }
                self.remaining -= amount;
                return self.remaining;
            }
        };

        const CB = Callback(fn (u32) error{Insufficient}!u32);
        const Bound = Thunk(CB, State, &State.spend, "unit");

        var state: State = .{ .remaining = 9, .attempts = 0 };

        try testing.expectError(error.Insufficient, Bound.invoke(@ptrCast(&state), .{12}));
        const remaining = try Bound.invoke(@ptrCast(&state), .{3});

        try testing.expectEqual(@as(u32, 6), remaining);
        try testing.expectEqual(@as(u32, 2), state.attempts);
    }

    test "zero-argument void invocations retain context progress" {
        const State = struct {
            calls: u32,

            pub fn tick(self: *@This()) void {
                self.calls += 1;
            }
        };

        const CB = Callback(fn () void);
        const Bound = Thunk(CB, State, &State.tick, "unit");

        var state: State = .{ .calls = 0 };

        Bound.invoke(@ptrCast(&state), .{});
        Bound.invoke(@ptrCast(&state), .{});
        Bound.invoke(@ptrCast(&state), .{});

        try testing.expectEqual(@as(u32, 3), state.calls);
    }
};
