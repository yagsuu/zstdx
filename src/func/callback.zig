//! Runtime-erased single-function callback. Spec: docs/specs/func/callback.md.

const std = @import("std");

const validate = @import("validate.zig");

/// Signature-typed `{context, invoke}` callback. `Fn` is the caller-visible
/// function signature; the underlying thunk type prepends a
/// `?*anyopaque` context slot so every factory (`wrap`, `bind`,
/// `bindMethod`) produces a uniform shape.
///
/// `Fn` must be a concrete function type: no generic (`comptime` /
/// `anytype`) parameters, no variadics, no naked returns.
///
/// Context lifetime: `context` is a borrowed pointer. `Callback` never
/// takes ownership, never allocates, and never frees. A callback that
/// outlives its context is a caller contract violation and is not
/// detected by the primitive.
///
/// Concurrency: value type. `call` performs one indirect call and one
/// context load with no synchronization. Callers who share a `Callback`
/// across threads publish it themselves.
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

        /// Wrap an already-erased `{context, invoke}` pair verbatim.
        /// Reserved for callers who synthesize their own thunk; `wrap`,
        /// `bind`, and `bindMethod` are the ordinary paths.
        pub fn init(context: ?*anyopaque, invoke: *const Invoke) Self {
            return .{ .context = context, .invoke = invoke };
        }

        /// Adapt a free function with the exact signature `Fn` into a
        /// context-less callback. The thunk ignores the context slot.
        pub fn wrap(comptime fn_ptr: *const Fn) Self {
            const Thunk = struct {
                fn invoke(_: ?*anyopaque, args: Args) Return {
                    return @call(.auto, fn_ptr, args);
                }
            };
            return .{ .context = null, .invoke = &Thunk.invoke };
        }

        /// Adapt a free function of signature `fn (*Ctx, ...) Return`
        /// into a callback that carries `ctx` in the context slot. The
        /// bound signature is validated structurally at compile time.
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

        /// Adapt a method `ctx.<method_name>(...)` into a callback. The
        /// method must have signature `fn (*Ctx, ...) Return` matching
        /// `Fn` with `*Ctx` prepended.
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

        /// Invoke the callback with `args`, a positional tuple matching
        /// `Fn`'s parameters. Zero-argument callbacks pass `.{}`.
        pub fn call(self: Self, args: Args) Return {
            return self.invoke(self.context, args);
        }

        /// True iff `self.context` and `self.invoke` are field-identical
        /// to `other`. Two callbacks constructed by identical
        /// `wrap`/`bind`/`bindMethod` calls compare equal because they
        /// share the same synthesized thunk instance.
        pub fn eql(self: Self, other: Self) bool {
            return self.context == other.context and self.invoke == other.invoke;
        }
    };
}

fn returnType(comptime Fn: type) type {
    return @typeInfo(Fn).@"fn".return_type orelse
        @compileError("Callback: function signature has no return type");
}
