//! Unaligned byte-window loads and stores. Pure byte copies; no endian
//! conversion and no typed pointer reinterpretation. See
//! docs/specs/bytes/unaligned.md.

const std = @import("std");

/// Copy `@sizeOf(T)` bytes from `bytes` into a fresh `T`. The window length
/// is exact, so no bounds check happens here. Unsupported categories — slice,
/// pointer, optional, error union/set, union, function, zero-sized,
/// comptime-only — are compile errors.
pub fn loadUnaligned(comptime T: type, bytes: *const [@sizeOf(T)]u8) T {
    validateType(T);
    var value: T = undefined;
    @memcpy(std.mem.asBytes(&value), bytes);
    return value;
}

/// Copy `@sizeOf(T)` bytes from `value` into `bytes`. Same type restrictions
/// and zero-conversion guarantees as `loadUnaligned`.
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
