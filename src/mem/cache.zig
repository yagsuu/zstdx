//! Memory cache-line alignment. See `docs/specs/mem/cache.md`.

const std = @import("std");

const cache_line = std.atomic.cache_line;

/// Aligns `value` to a cache line. Adjacent values can share a cache line.
pub fn CacheAlign(comptime T: type) type {
    validatePayload(T, "CacheAlign");
    return struct {
        value: T align(cache_line),
    };
}

/// Isolates adjacent values in disjoint cache lines.
pub fn CachePad(comptime T: type) type {
    validatePayload(T, "CachePad");

    const pad_bytes = paddingFor(T);
    return struct {
        value: T align(cache_line),
        _pad: [pad_bytes]u8 = [_]u8{0} ** pad_bytes,
    };
}

fn validatePayload(comptime T: type, comptime factory: []const u8) void {
    if (T == void) {
        @compileError(factory ++ ": payload type must not be void");
    }

    if (@sizeOf(T) == 0) {
        @compileError(factory ++ ": payload type must have @sizeOf(T) > 0");
    }

    if (@alignOf(T) > cache_line) {
        @compileError(factory ++ ": payload natural @alignOf(T) exceeds std.atomic.cache_line");
    }
}

fn paddingFor(comptime T: type) comptime_int {
    const raw = @sizeOf(T);
    const remainder = raw % cache_line;
    return if (remainder == 0) 0 else cache_line - remainder;
}
