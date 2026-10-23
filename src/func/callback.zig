//! signature-typed callbacks

const std = @import("std");

const Impl = @import("impl.zig");

pub fn Callback(comptime Fn: type) type {
    comptime Impl.requireSignature(Fn, "Callback(Fn)");

    return struct {
        context: ?*anyopaque,
        invoke: *const Invoke,

        pub const Signature: type = Fn;
        pub const Args: type = std.meta.ArgsTuple(Fn);
        pub const Return: type = @typeInfo(Fn).@"fn".return_type.?;
        pub const Invoke: type = fn (?*anyopaque, Args) Return;

        const Self = @This();

        /// the borrowed context must outlive the callback
        pub fn init(context: ?*anyopaque, invoke: *const Invoke) Self {
            return .{ .context = context, .invoke = invoke };
        }

        pub fn wrap(comptime function: *const Fn) Self {
            const Thunk = struct {
                fn invoke(_: ?*anyopaque, args: Args) Return {
                    return @call(.auto, function, args);
                }
            };
            return .{ .context = null, .invoke = &Thunk.invoke };
        }

        pub fn bind(
            comptime Context: type,
            context: *Context,
            comptime function: anytype,
        ) Self {
            const Thunk = Impl.Thunk(Self, Context, function, "Callback.bind");
            return .{
                .context = @ptrCast(context),
                .invoke = &Thunk.invoke,
            };
        }

        pub fn bindMethod(
            comptime Context: type,
            context: *Context,
            comptime method: []const u8,
        ) Self {
            if (!@hasDecl(Context, method)) {
                @compileError(
                    "Callback.bindMethod: " ++ @typeName(Context) ++
                        " has no pub decl named '" ++ method ++ "'",
                );
            }

            return bind(Context, context, &@field(Context, method));
        }

        pub const call = switch (@typeInfo(Fn).@"fn".params.len) {
            0 => struct {
                fn call(self: Self) Return {
                    return self.invoke(self.context, .{});
                }
            }.call,
            1 => struct {
                fn call(self: Self, value: @typeInfo(Fn).@"fn".params[0].type.?) Return {
                    return self.invoke(self.context, .{value});
                }
            }.call,
            else => callArgs,
        };

        pub fn callArgs(self: Self, args: Args) Return {
            return self.invoke(self.context, args);
        }

        pub fn eql(self: Self, other: Self) bool {
            return self.context == other.context and self.invoke == other.invoke;
        }

        comptime {
            std.debug.assert(@sizeOf(Self) == 2 * @sizeOf(usize));
        }
    };
}

pub const unit = struct {
    const testing = std.testing;

    test "zero-argument call forms share context progress" {
        const State = struct {
            calls: u32,

            pub fn tick(self: *@This()) void {
                self.calls += 1;
            }
        };

        var state: State = .{ .calls = 0 };
        const callback = Callback(fn () void).bind(State, &state, &State.tick);

        callback.call();
        callback.callArgs(.{});
        callback.call();

        try testing.expectEqual(@as(u32, 3), state.calls);
    }

    test "tuple-valued arguments stay distinct from multiple parameters" {
        const Pair = struct { u32, u32 };
        const State = struct {
            value: u32,

            pub fn pair(self: *@This(), value: Pair) u32 {
                self.value = self.value * value[0] + value[1];
                return self.value;
            }

            pub fn parts(self: *@This(), factor: u32, amount: u32) u32 {
                self.value = self.value * factor + amount;
                return self.value;
            }
        };

        var a: State = .{ .value = 1 };
        var b: State = .{ .value = 10 };

        const pair = Callback(fn (Pair) u32).bind(State, &a, &State.pair);
        const many = Callback(fn (u32, u32) u32).bind(State, &b, &State.parts);

        const pair_first = pair.call(.{ 2, 3 });
        const many_first = many.call(.{ 3, 4 });
        const pair_next = pair.callArgs(.{.{ 4, 1 }});
        const many_next = many.callArgs(.{ 2, 5 });

        try testing.expectEqual(@as(u32, 5), pair_first);
        try testing.expectEqual(@as(u32, 34), many_first);
        try testing.expectEqual(@as(u32, 21), pair_next);
        try testing.expectEqual(@as(u32, 73), many_next);
    }

    test "callback identity includes both context and function" {
        const State = struct {
            value: u32,

            pub fn add(self: *@This(), amount: u32) u32 {
                self.value += amount;
                return self.value;
            }

            pub fn replace(self: *@This(), value: u32) u32 {
                self.value = value;
                return self.value;
            }

            fn increment(value: u32) u32 {
                return value + 1;
            }
        };

        const CB = Callback(fn (u32) u32);

        var a: State = .{ .value = 1 };
        var b: State = .{ .value = 1 };

        const bound = CB.bind(State, &a, &State.add);
        const repeated = CB.bind(State, &a, &State.add);
        const method = CB.bindMethod(State, &a, "add");
        const other_context = CB.bind(State, &b, &State.add);
        const other_function = CB.bind(State, &a, &State.replace);
        const free = CB.wrap(&State.increment);
        const same_free = CB.wrap(&State.increment);

        try testing.expect(bound.eql(repeated));
        try testing.expect(bound.eql(method));
        try testing.expect(!bound.eql(other_context));
        try testing.expect(!bound.eql(other_function));
        try testing.expect(free.eql(same_free));
        try testing.expect(!bound.eql(free));
    }
};
