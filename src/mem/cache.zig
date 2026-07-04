//! Memory cache-line alignment. Spec: docs/specs/mem/cache.md.

const std = @import("std");

const cache_line = std.atomic.cache_line;

/// Cache-line-aligned wrapper with trailing padding that isolates the
/// payload from adjacent memory. Two `CachePad(T)` values placed
/// adjacently occupy disjoint sets of cache lines.
pub fn CachePad(comptime T: type) type {
    validatePayload(T, "CachePad");
    const pad_bytes = paddingFor(T);
    return struct {
        value: T align(cache_line),
        _pad: [pad_bytes]u8 = [_]u8{0} ** pad_bytes,
    };
}

/// Cache-line-aligned wrapper without trailing padding. The payload
/// starts on a cache-line boundary; two adjacent values MAY share a
/// cache line when `@sizeOf(T) < cache_line`.
pub fn CacheAlign(comptime T: type) type {
    validatePayload(T, "CacheAlign");
    return struct {
        value: T align(cache_line),
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
