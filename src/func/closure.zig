//! Inline-storage constructor for `Callback`. Spec:
//! docs/specs/func/callback.md.

const std = @import("std");

const callback = @import("callback.zig");
const validate = @import("validate.zig");

const Callback = callback.Callback;

const alignUp = @import("../mem/alignment.zig").alignUp;

/// Small-buffer closure over signature `Fn`. Holds `capacity_bytes` of
/// inline caller state aligned to `@alignOf(usize)`, plus one thunk
/// pointer. `init` bit-copies the captured state into storage; the
/// resulting closure is trivially copyable iff the state is.
///
/// Concurrency: value type. Callbacks derived through the type's own
/// `callback()` method borrow the closure's storage; moving or copying
/// the `Closure` invalidates any previously-returned `Callback`. A
/// `Callback` that outlives its owning `Closure` is a caller contract
/// violation and is not detected by the primitive.
pub fn Closure(comptime Fn: type, comptime capacity_bytes: usize) type {
    const CB = Callback(Fn);

    return struct {
        pub const Signature: type = Fn;
        pub const capacity: usize = capacity_bytes;
        pub const alignment: usize = @alignOf(usize);

        storage: [capacity_bytes]u8 align(alignment),
        invoke: *const CB.Invoke,

        const Self = @This();

        comptime {
            const aligned_capacity = alignUp(usize, capacity_bytes, alignment) catch unreachable;
            std.debug.assert(@sizeOf(Self) == aligned_capacity + @sizeOf(usize));
        }

        /// Bit-copy `state` into the closure's inline storage and store
        /// a thunk that re-casts storage to `*State` before delegating
        /// to `fn_ptr`. Compile-error when `@sizeOf(State) > capacity`
        /// or `@alignOf(State) > alignment`.
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

        /// Return a `Callback(Fn)` borrowing this closure's storage.
        /// The callback is valid only while the closure sits at a
        /// stable address; moving or copying the closure invalidates
        /// the returned callback.
        pub fn callback(self: *Self) CB {
            return .{
                .context = @ptrCast(&self.storage),
                .invoke = self.invoke,
            };
        }
    };
}
