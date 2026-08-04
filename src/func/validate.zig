//! Internal comptime signature validation for `Callback` and `Closure`.

const std = @import("std");

/// Reject a non-concrete function type and name the invalid property in a
/// `@compileError`.
pub fn signature(comptime Fn: type, comptime kind: []const u8) void {
    const info = switch (@typeInfo(Fn)) {
        .@"fn" => |f| f,
        else => @compileError(
            kind ++ ": " ++ @typeName(Fn) ++ " is not a function type",
        ),
    };

    if (info.is_generic) {
        @compileError(
            kind ++ ": " ++ @typeName(Fn) ++
                " is a generic function (has comptime or anytype parameters); use a concrete signature",
        );
    }

    if (info.is_var_args) {
        @compileError(
            kind ++ ": " ++ @typeName(Fn) ++
                " is variadic; variadics are not supported",
        );
    }

    if (info.return_type == null) {
        @compileError(
            kind ++ ": " ++ @typeName(Fn) ++
                " has no return type (naked function); not supported",
        );
    }

    inline for (info.params, 0..) |p, i| {
        if (p.type == null) {
            @compileError(std.fmt.comptimePrint(
                "{s}: {s} parameter {d} has no concrete type (anytype)",
                .{ kind, @typeName(Fn), i },
            ));
        }
    }
}

/// Requires `Ptr` to point to a function with signature `Fn` and `*Ctx` as its
/// first parameter.
pub fn bound(
    comptime Fn: type,
    comptime Ctx: type,
    comptime Ptr: type,
    comptime kind: []const u8,
) void {
    const ptr_info = switch (@typeInfo(Ptr)) {
        .pointer => |p| p,
        else => @compileError(
            kind ++ ": " ++ @typeName(Ptr) ++ " is not a function pointer",
        ),
    };
    const Callee = ptr_info.child;
    const callee_info = switch (@typeInfo(Callee)) {
        .@"fn" => |f| f,
        else => @compileError(
            kind ++ ": " ++ @typeName(Ptr) ++ " does not point to a function",
        ),
    };
    const fn_info = @typeInfo(Fn).@"fn";

    if (callee_info.is_generic) {
        @compileError(
            kind ++ ": " ++ @typeName(Callee) ++ " is generic; concrete signature required",
        );
    }

    if (callee_info.is_var_args) {
        @compileError(
            kind ++ ": " ++ @typeName(Callee) ++ " is variadic; not supported",
        );
    }

    if (callee_info.params.len != fn_info.params.len + 1) {
        @compileError(std.fmt.comptimePrint(
            "{s}: {s} has {d} parameters, expected {d} (context + signature)",
            .{ kind, @typeName(Callee), callee_info.params.len, fn_info.params.len + 1 },
        ));
    }

    const first = callee_info.params[0].type orelse
        @compileError(kind ++ ": " ++ @typeName(Callee) ++ " first parameter has no concrete type");
    if (first != *Ctx) {
        @compileError(
            kind ++ ": " ++ @typeName(Callee) ++ " first parameter is " ++
                @typeName(first) ++ ", expected *" ++ @typeName(Ctx),
        );
    }

    inline for (fn_info.params, 0..) |p, i| {
        const expected = p.type.?;
        const got = callee_info.params[i + 1].type orelse
            @compileError(std.fmt.comptimePrint(
                "{s}: {s} parameter {d} has no concrete type",
                .{ kind, @typeName(Callee), i + 1 },
            ));
        if (expected != got) {
            @compileError(std.fmt.comptimePrint(
                "{s}: {s} parameter {d} is {s}, expected {s}",
                .{ kind, @typeName(Callee), i + 1, @typeName(got), @typeName(expected) },
            ));
        }
    }

    const expected_ret = fn_info.return_type.?;
    const got_ret = callee_info.return_type orelse
        @compileError(kind ++ ": " ++ @typeName(Callee) ++ " has no return type");
    if (got_ret != expected_ret) {
        @compileError(
            kind ++ ": " ++ @typeName(Callee) ++ " returns " ++ @typeName(got_ret) ++
                ", expected " ++ @typeName(expected_ret),
        );
    }
}
