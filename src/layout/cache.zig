//! Memory cache-line alignment. See `docs/specs/mem/cache.md`.

const std = @import("std");

const cache_line = std.atomic.cache_line;

pub fn CacheAlign(comptime T: type) type {
    validateT(T, "CacheAlign");
    return struct {
        value: T align(cache_line),
    };
}

/// Isolates adjacent values in disjoint cache lines.
pub fn CachePad(comptime T: type) type {
    validateT(T, "CachePad");

    const remainder = @sizeOf(T) % cache_line;
    const pad = if (remainder == 0) 0 else cache_line - remainder;

    return struct {
        value: T align(cache_line),
        _pad: [pad]u8 = [_]u8{0} ** pad,
    };
}

fn validateT(comptime T: type, comptime factory: []const u8) void {
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

pub const unit = struct {
    const testing = std.testing;

    test "unit: CacheAlign payload alignment" {
        const Aligned = CacheAlign(u32);
        var values: [2]Aligned = undefined;

        try testing.expectEqual(cache_line, @alignOf(Aligned));
        try testing.expectEqual(@as(usize, 0), @offsetOf(Aligned, "value"));

        for (&values) |*value| {
            try testing.expectEqual(@as(usize, 0), @intFromPtr(&value.value) % cache_line);
        }
    }

    test "unit: CachePad isolates adjacent payloads" {
        const Padded = CachePad(u32);
        var values: [2]Padded = undefined;

        const first = @intFromPtr(&values[0].value);
        const second = @intFromPtr(&values[1].value);

        try testing.expectEqual(cache_line, @alignOf(Padded));
        try testing.expectEqual(@as(usize, 0), @offsetOf(Padded, "value"));
        try testing.expectEqual(@as(usize, 0), first % cache_line);
        try testing.expectEqual(@as(usize, 0), second % cache_line);
        try testing.expect(second - first >= cache_line);
    }
};
