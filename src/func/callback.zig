//! Runtime-erased single-function callbacks. See `docs/specs/func/callback.md`.

const std = @import("std");

const validate = @import("validate.zig");

/// A signature-typed `{context, invoke}` callback. `Fn` is the caller-visible
/// function signature. The thunk prepends a `?*anyopaque` context slot so
/// `wrap`, `bind`, and `bindMethod` produce one representation.
///
/// `Fn` must be a concrete function type. It cannot have generic (`comptime`
/// or `anytype`) parameters, variadics, or a naked return.
///
/// The `context` pointer is borrowed. `Callback` does not allocate, take
/// ownership, or free it. A callback that outlives its context violates the
/// caller contract. The primitive does not detect this violation.
///
/// `call` performs one indirect call and one context load without
/// synchronization. Callers must publish a shared `Callback` themselves.
pub fn Callback(comptime Fn: type) type {
    comptime validate.signature(Fn, "Callback(Fn)");

    return struct {
        pub const Signature: type = Fn;
        pub const Args: type = std.meta.ArgsTuple(Fn);
        pub const Return: type = returnType(Fn);
        pub const Invoke: type = fn (?*anyopaque, Args) Return;

        context: ?*anyopaque,
        invoke: *const Invoke,

        const Self = @This();

        comptime {
            std.debug.assert(@sizeOf(Self) == 2 * @sizeOf(usize));
        }

        /// Constructs a callback from an already-erased `{context, invoke}` pair.
        /// Use `wrap`, `bind`, or `bindMethod` unless the caller supplies a thunk.
        pub fn init(context: ?*anyopaque, invoke: *const Invoke) Self {
            return .{ .context = context, .invoke = invoke };
        }

        /// Adapts a free function with signature `Fn` to a context-less callback.
        pub fn wrap(comptime fn_ptr: *const Fn) Self {
            const Thunk = struct {
                fn invoke(_: ?*anyopaque, args: Args) Return {
                    return @call(.auto, fn_ptr, args);
                }
            };
            return .{ .context = null, .invoke = &Thunk.invoke };
        }

        /// Adapts `fn (*Ctx, ...) Return` to a callback with `ctx` in its context
        /// slot. The function signature is validated structurally at compile time.
        pub fn bind(
            comptime Ctx: type,
            ctx: *Ctx,
            comptime fn_ptr: anytype,
        ) Self {
            comptime validate.bound(Fn, Ctx, @TypeOf(fn_ptr), "Callback.bind");

            const Thunk = struct {
                fn invoke(erased: ?*anyopaque, args: Args) Return {
                    const typed: *Ctx = @ptrCast(@alignCast(erased.?));
                    return @call(.auto, fn_ptr, .{typed} ++ args);
                }
            };
            return .{ .context = @ptrCast(ctx), .invoke = &Thunk.invoke };
        }

        /// Adapts `ctx.<method_name>(...)` to a callback. The method must have
        /// signature `fn (*Ctx, ...) Return`, where `Fn` omits `*Ctx`.
        pub fn bindMethod(
            comptime Ctx: type,
            ctx: *Ctx,
            comptime method_name: []const u8,
        ) Self {
            if (!@hasDecl(Ctx, method_name)) {
                @compileError(
                    "Callback.bindMethod: " ++ @typeName(Ctx) ++
                        " has no pub decl named '" ++ method_name ++ "'",
                );
            }
            return bind(Ctx, ctx, &@field(Ctx, method_name));
        }

        /// Invoke the callback with an `Args` tuple. Use `.{}` when `Fn` has no
        /// parameters.
        pub fn call(self: Self, args: Args) Return {
            return self.invoke(self.context, args);
        }

        /// Returns true when both callback fields equal the fields in `other`.
        /// Identical `wrap`, `bind`, or `bindMethod` calls share a thunk instance.
        pub fn eql(self: Self, other: Self) bool {
            return self.context == other.context and self.invoke == other.invoke;
        }
    };
}

fn returnType(comptime Fn: type) type {
    return @typeInfo(Fn).@"fn".return_type orelse
        @compileError("Callback: function signature has no return type");
}
