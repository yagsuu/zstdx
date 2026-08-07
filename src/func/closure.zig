//! Inline-state constructor for `Callback`. See `docs/specs/func/callback.md`.

const std = @import("std");

const callback = @import("callback.zig");
const validate = @import("validate.zig");

const Callback = callback.Callback;

const alignUp = @import("../mem/align.zig").alignUp;

/// A small-buffer closure with signature `Fn`. It holds `capacity_bytes` of
/// inline caller state aligned to `@alignOf(usize)` and one thunk pointer.
/// `init` bit-copies the state into storage. The resulting closure is trivially
/// copyable only when the state is trivially copyable.
///
/// A callback from `callback()` borrows the closure storage. Moving or copying
/// the `Closure` invalidates previously returned callbacks. A callback that
/// outlives its owning `Closure` violates the caller contract. The primitive
/// does not detect this violation.
pub fn Closure(comptime Fn: type, comptime capacity_bytes: usize) type {
    const CB = Callback(Fn);

    return struct {
        storage: [capacity_bytes]u8 align(alignment),
        invoke: *const CB.Invoke,

        pub const Signature: type = Fn;

        pub const capacity: usize = capacity_bytes;
        pub const alignment: usize = @alignOf(usize);

        const Self = @This();

        /// Bit-copy `state` into inline storage and store a thunk that casts the
        /// storage to `*State` before it calls `fn_ptr`. This compile-errors when
        /// `@sizeOf(State) > capacity` or `@alignOf(State) > alignment`.
        pub fn init(
            comptime State: type,
            state: State,
            comptime fn_ptr: anytype,
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

            comptime validate.bound(Fn, State, @TypeOf(fn_ptr), "Closure.init");

            const Args = CB.Args;
            const Return = CB.Return;

            const Thunk = struct {
                fn invoke(erased: ?*anyopaque, args: Args) Return {
                    const typed: *State = @ptrCast(@alignCast(erased.?));
                    return @call(.auto, fn_ptr, .{typed} ++ args);
                }
            };

            var self: Self = .{
                .storage = undefined,
                .invoke = &Thunk.invoke,
            };

            const dst: *State = @ptrCast(@alignCast(&self.storage));
            dst.* = state;
            return self;
        }

        /// Returns a `Callback(Fn)` that borrows this closure's storage. Keep the
        /// closure at a stable address until the returned callback is no longer used.
        pub fn callback(self: *Self) CB {
            return .{
                .context = @ptrCast(&self.storage),
                .invoke = self.invoke,
            };
        }

        comptime {
            const aligned_capacity = alignUp(usize, capacity_bytes, alignment) catch unreachable;
            std.debug.assert(@sizeOf(Self) == aligned_capacity + @sizeOf(usize));
        }
    };
}
