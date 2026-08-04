//! Unaligned byte-window loads and stores.
//! Operations copy bytes without byte-order conversion or typed-pointer
//! reinterpretation. See `docs/specs/bytes/unaligned.md`.

const std = @import("std");

/// Copies `@sizeOf(T)` bytes from `bytes` into a new `T` value without byte-order
/// conversion. `bytes` has an exact length, so this function does no bounds check.
/// `loadUnaligned` rejects slice, pointer, optional, error union, error set, union,
/// function, zero-sized, and comptime-only types at compile time.
pub fn loadUnaligned(comptime T: type, bytes: *const [@sizeOf(T)]u8) T {
    validateType(T);
    var value: T = undefined;
    @memcpy(std.mem.asBytes(&value), bytes);
    return value;
}

/// Copies `@sizeOf(T)` bytes from `value` into `bytes` without byte-order
/// conversion. `storeUnaligned` uses the same type restrictions as `loadUnaligned`.
pub fn storeUnaligned(comptime T: type, bytes: *[@sizeOf(T)]u8, value: T) void {
    validateType(T);
    @memcpy(bytes, std.mem.asBytes(&value));
}

fn validateType(comptime T: type) void {
    if (@sizeOf(T) == 0) @compileError("unsupported zero-sized unaligned type");

    switch (@typeInfo(T)) {
        .pointer,
        .optional,
        .error_union,
        .error_set,
        .@"union",
        .@"fn",
        .comptime_int,
        .comptime_float,
        .noreturn,
        .undefined,
        .null,
        .type,
        .void,
        => @compileError("unsupported unaligned type"),
        else => {},
    }
}
