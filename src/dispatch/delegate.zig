//! Signature-typed delegates.

const std = @import("std");
const layout = @import("layout");

const Impl = @import("thunk.zig");

pub fn Delegate(comptime Fn: type) type {
    const signature = Impl.functionInfo(Fn, "Delegate(Fn)");

    return struct {
        context: ?*anyopaque,
        invoke: *const Invoke,

        pub const Signature: type = Fn;
        pub const Args: type = std.meta.ArgsTuple(Fn);
        pub const Return: type = signature.return_type.?;
        pub const Invoke: type = fn (?*anyopaque, Args) Return;

        const Self = @This();

        /// the borrowed context must outlive the delegate
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
            const Thunk = Impl.Thunk(Self, Context, function, "Delegate.bind");
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
                    "Delegate.bindMethod: " ++ @typeName(Context) ++
                        " has no pub decl named '" ++ method ++ "'",
                );
            }

            return bind(Context, context, &@field(Context, method));
        }

        pub const call = switch (signature.param_types.len) {
            0 => struct {
                fn call(self: Self) Return {
                    return self.invoke(self.context, .{});
                }
            }.call,
            1 => struct {
                fn call(self: Self, value: signature.param_types[0].?) Return {
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
            layout.assertLayout(Self, .{ .size = 2 * @sizeOf(usize) });
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
        const delegate = Delegate(fn () void).bind(State, &state, &State.tick);

        delegate.call();
        delegate.callArgs(.{});
        delegate.call();

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

        const pair = Delegate(fn (Pair) u32).bind(State, &a, &State.pair);
        const many = Delegate(fn (u32, u32) u32).bind(State, &b, &State.parts);

        const pair_first = pair.call(.{ 2, 3 });
        const many_first = many.call(.{ 3, 4 });
        const pair_next = pair.callArgs(.{.{ 4, 1 }});
        const many_next = many.callArgs(.{ 2, 5 });

        try testing.expectEqual(@as(u32, 5), pair_first);
        try testing.expectEqual(@as(u32, 34), many_first);
        try testing.expectEqual(@as(u32, 21), pair_next);
        try testing.expectEqual(@as(u32, 73), many_next);
    }

    test "delegate identity includes both context and function" {
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

        const AddDelegate = Delegate(fn (u32) u32);

        var a: State = .{ .value = 1 };
        var b: State = .{ .value = 1 };

        const bound = AddDelegate.bind(State, &a, &State.add);
        const repeated = AddDelegate.bind(State, &a, &State.add);
        const method = AddDelegate.bindMethod(State, &a, "add");
        const other_context = AddDelegate.bind(State, &b, &State.add);
        const other_function = AddDelegate.bind(State, &a, &State.replace);
        const free = AddDelegate.wrap(&State.increment);
        const same_free = AddDelegate.wrap(&State.increment);

        try testing.expect(bound.eql(repeated));
        try testing.expect(bound.eql(method));
        try testing.expect(!bound.eql(other_context));
        try testing.expect(!bound.eql(other_function));
        try testing.expect(free.eql(same_free));
        try testing.expect(!bound.eql(free));
    }
};
