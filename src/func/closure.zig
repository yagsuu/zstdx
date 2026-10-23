//! callbacks with inline state

const std = @import("std");

const callback = @import("callback.zig");

const Impl = @import("impl.zig");
const Callback = callback.Callback;

const alignUp = @import("layout").alignment.alignUp;

/// referenced resources remain caller-managed
/// keep the closure alive and at a fixed address while callbacks borrow its state
pub fn Closure(comptime Fn: type, comptime capacity_bytes: usize) type {
    const CB = Callback(Fn);

    return struct {
        bytes: [capacity_bytes]u8 align(alignment),
        invoke: *const CB.Invoke,

        pub const Signature: type = Fn;

        pub const capacity: usize = capacity_bytes;
        pub const alignment: usize = @alignOf(usize);

        const Self = @This();

        pub fn init(
            comptime State: type,
            state: State,
            comptime function: anytype,
        ) Self {
            if (@sizeOf(State) > capacity_bytes) {
                @compileError(std.fmt.comptimePrint(
                    "Closure(Fn, {d}).init: @sizeOf({s}) = {d} exceeds capacity {d}",
                    .{ capacity_bytes, @typeName(State), @sizeOf(State), capacity_bytes },
                ));
            }

            if (@alignOf(State) > alignment) {
                @compileError(std.fmt.comptimePrint(
                    "Closure(Fn, {d}).init: @alignOf({s}) = {d} exceeds closure alignment {d}",
                    .{ capacity_bytes, @typeName(State), @alignOf(State), alignment },
                ));
            }

            const Thunk = Impl.Thunk(CB, State, function, "Closure.init");
            var self: Self = .{
                .bytes = undefined,
                .invoke = &Thunk.invoke,
            };

            const dst: *State = @ptrCast(@alignCast(&self.bytes));
            dst.* = state;
            return self;
        }

        pub fn callbackMut(self: *Self) CB {
            return .{
                .context = @ptrCast(&self.bytes),
                .invoke = self.invoke,
            };
        }

        comptime {
            const aligned_capacity = alignUp(usize, capacity_bytes, alignment) catch unreachable;
            std.debug.assert(@sizeOf(Self) == aligned_capacity + @sizeOf(usize));
        }
    };
}

pub const unit = struct {
    const testing = std.testing;

    test "borrowed callbacks share owned state without aliasing the seed" {
        const State = struct {
            value: usize,

            pub fn add(self: *@This(), amount: usize) usize {
                self.value += amount;
                return self.value;
            }
        };

        const C = Closure(fn (usize) usize, @sizeOf(State));

        var seed: State = .{ .value = 4 };
        var owner = C.init(State, seed, &State.add);

        const borrowed = owner.callbackMut();
        const other_view = owner.callbackMut();

        seed.value = 100;

        const first = borrowed.call(3);
        const second = other_view.call(2);
        const resumed = borrowed.call(1);

        try testing.expectEqual(@as(usize, 7), first);
        try testing.expectEqual(@as(usize, 9), second);
        try testing.expectEqual(@as(usize, 10), resumed);
    }
};
