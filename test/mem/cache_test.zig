//! CachePad / CacheAlign contract tests. See `docs/specs/mem/cache.md`.

const std = @import("std");

const stdx = @import("stdx");

const CachePad = stdx.mem.CachePad;
const CacheAlign = stdx.mem.CacheAlign;

const cache_line = std.atomic.cache_line;
const testing = std.testing;

const AtomicUsize = std.atomic.Value(usize);

test "contract: CachePad @alignOf equals std.atomic.cache_line for u32" {
    try testing.expectEqual(cache_line, @alignOf(CachePad(u32)));
}

test "contract: CachePad @alignOf equals std.atomic.cache_line for usize" {
    try testing.expectEqual(cache_line, @alignOf(CachePad(usize)));
}

test "contract: CachePad @alignOf equals std.atomic.cache_line for atomic usize" {
    try testing.expectEqual(cache_line, @alignOf(CachePad(AtomicUsize)));
}

test "contract: CacheAlign @alignOf equals std.atomic.cache_line for u32" {
    try testing.expectEqual(cache_line, @alignOf(CacheAlign(u32)));
}

test "contract: CacheAlign @alignOf equals std.atomic.cache_line for usize" {
    try testing.expectEqual(cache_line, @alignOf(CacheAlign(usize)));
}

test "contract: CacheAlign @alignOf equals std.atomic.cache_line for atomic usize" {
    try testing.expectEqual(cache_line, @alignOf(CacheAlign(AtomicUsize)));
}

test "contract: CachePad value field sits at offset zero" {
    try testing.expectEqual(@as(usize, 0), @offsetOf(CachePad(u32), "value"));
    try testing.expectEqual(@as(usize, 0), @offsetOf(CachePad(usize), "value"));
    try testing.expectEqual(@as(usize, 0), @offsetOf(CachePad(AtomicUsize), "value"));
}

test "contract: CacheAlign value field sits at offset zero" {
    try testing.expectEqual(@as(usize, 0), @offsetOf(CacheAlign(u32), "value"));
    try testing.expectEqual(@as(usize, 0), @offsetOf(CacheAlign(usize), "value"));
    try testing.expectEqual(@as(usize, 0), @offsetOf(CacheAlign(AtomicUsize), "value"));
}

test "contract: CachePad _pad follows value at @sizeOf(T)-rounded-up-to-@alignOf(T)" {
    // `@sizeOf(T)` is already a whole multiple of `@alignOf(T)` for any Zig
    // type, so the spec's "round up" simplifies to `@sizeOf(T)` here. The
    // `_pad` field has element alignment 1 and therefore introduces no
    // extra gap after `value`.
    inline for (.{ u32, usize, AtomicUsize }) |T| {
        const expected = std.mem.alignForward(usize, @sizeOf(T), @alignOf(T));
        try testing.expectEqual(expected, @offsetOf(CachePad(T), "_pad"));
    }
}

test "contract: CachePad exposes the _pad field regardless of pad_bytes" {
    inline for (.{ u32, usize, AtomicUsize }) |T| {
        try testing.expect(@hasField(CachePad(T), "_pad"));
    }
}

test "contract: CachePad @sizeOf is a whole multiple of cache_line for u32" {
    try testing.expectEqual(@as(usize, 0), @sizeOf(CachePad(u32)) % cache_line);
}

test "contract: CachePad @sizeOf is a whole multiple of cache_line for usize" {
    try testing.expectEqual(@as(usize, 0), @sizeOf(CachePad(usize)) % cache_line);
}

test "contract: CachePad @sizeOf is a whole multiple of cache_line for atomic usize" {
    try testing.expectEqual(@as(usize, 0), @sizeOf(CachePad(AtomicUsize)) % cache_line);
}

test "contract: CachePad @sizeOf >= cache_line for sub-cache_line payload" {
    try testing.expect(@sizeOf(CachePad(u32)) >= cache_line);
    try testing.expect(@sizeOf(CachePad(usize)) >= cache_line);
    try testing.expect(@sizeOf(CachePad(AtomicUsize)) >= cache_line);
}

test "contract: [N]CachePad(T) places each element on a distinct cache line" {
    inline for (.{ u32, usize, AtomicUsize }) |T| {
        const N = 4;
        var arr: [N]CachePad(T) = undefined;
        var i: usize = 0;
        while (i + 1 < N) : (i += 1) {
            const lo = @intFromPtr(&arr[i]);
            const hi = @intFromPtr(&arr[i + 1]);
            const stride = hi - lo;
            try testing.expect(stride >= cache_line);
            try testing.expectEqual(@as(usize, 0), stride % cache_line);
        }
    }
}

test "contract: CacheAlign @sizeOf matches natural aligned-field struct size" {
    inline for (.{ u32, usize, AtomicUsize }) |T| {
        const Natural = struct { value: T align(cache_line) };
        try testing.expectEqual(@sizeOf(Natural), @sizeOf(CacheAlign(T)));
    }
}

test "contract: adjacent CacheAlign(u32) values share stride at least @sizeOf(T)" {
    // For payloads smaller than `cache_line`, `CacheAlign` guarantees
    // leading alignment only; the spec explicitly permits adjacent
    // elements in an array to sit inside the same cache line. Assert the
    // observed stride behaviour rather than treating this as isolation.
    var arr: [2]CacheAlign(u32) = undefined;
    const stride = @intFromPtr(&arr[1]) - @intFromPtr(&arr[0]);
    try testing.expect(stride >= @sizeOf(u32));
    // Array stride is `@sizeOf(CacheAlign(u32))`, and because
    // `@sizeOf(T) < cache_line`, the returned struct's size is
    // `cache_line` (the aligned field forces trailing pad in a plain
    // struct to satisfy its own alignment). Two adjacent elements
    // therefore may sit on adjacent cache lines but each element still
    // starts on a cache-line boundary; assert only what the spec asserts.
    try testing.expectEqual(@as(usize, 0), @intFromPtr(&arr[0]) % cache_line);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(&arr[1]) % cache_line);
}

test "unit: CachePad(u32) round-trips via value" {
    var padded: CachePad(u32) = .{ .value = 0xDEADBEEF };
    try testing.expectEqual(@as(u32, 0xDEADBEEF), padded.value);
    padded.value = 0x1234_5678;
    try testing.expectEqual(@as(u32, 0x1234_5678), padded.value);
}

test "unit: CachePad(usize) round-trips via value" {
    var padded: CachePad(usize) = .{ .value = 0 };
    padded.value = std.math.maxInt(usize);
    try testing.expectEqual(std.math.maxInt(usize), padded.value);
}

test "unit: CacheAlign(u32) round-trips via value" {
    var aligned: CacheAlign(u32) = .{ .value = 7 };
    try testing.expectEqual(@as(u32, 7), aligned.value);
    aligned.value = 42;
    try testing.expectEqual(@as(u32, 42), aligned.value);
}

test "unit: CacheAlign(usize) round-trips via value" {
    var aligned: CacheAlign(usize) = .{ .value = 0 };
    aligned.value = 12345;
    try testing.expectEqual(@as(usize, 12345), aligned.value);
}

test "unit: CachePad composes with std.atomic.Value fetchAdd" {
    var padded: CachePad(AtomicUsize) = .{ .value = AtomicUsize.init(0) };
    padded.value.store(10, .monotonic);
    const prior = padded.value.fetchAdd(1, .monotonic);
    try testing.expectEqual(@as(usize, 10), prior);
    try testing.expectEqual(@as(usize, 11), padded.value.load(.monotonic));
}

test "unit: CacheAlign composes with std.atomic.Value fetchAdd" {
    var aligned: CacheAlign(AtomicUsize) = .{ .value = AtomicUsize.init(0) };
    aligned.value.store(3, .monotonic);
    const prior = aligned.value.fetchAdd(4, .monotonic);
    try testing.expectEqual(@as(usize, 3), prior);
    try testing.expectEqual(@as(usize, 7), aligned.value.load(.monotonic));
}

test "unit: comptime alignment/size assertions on legal payloads" {
    comptime {
        std.debug.assert(@alignOf(CachePad(u32)) == cache_line);
        std.debug.assert(@sizeOf(CachePad(u32)) % cache_line == 0);
        std.debug.assert(@alignOf(CacheAlign(u32)) == cache_line);

        std.debug.assert(@alignOf(CachePad(usize)) == cache_line);
        std.debug.assert(@sizeOf(CachePad(usize)) % cache_line == 0);
        std.debug.assert(@alignOf(CacheAlign(usize)) == cache_line);

        std.debug.assert(@alignOf(CachePad(AtomicUsize)) == cache_line);
        std.debug.assert(@sizeOf(CachePad(AtomicUsize)) % cache_line == 0);
        std.debug.assert(@alignOf(CacheAlign(AtomicUsize)) == cache_line);

        std.debug.assert(@offsetOf(CachePad(u32), "value") == 0);
        std.debug.assert(@offsetOf(CacheAlign(u32), "value") == 0);
    }
}

// Compile-error cases — rejected shapes guarded by `@compileError` in
// `src/mem/cache.zig` (`validatePayload`), which Zig cannot exercise at
// runtime:
//   - `CachePad(void)` / `CacheAlign(void)`                — "must not be void"
//   - `CachePad(struct {})` / `CacheAlign(struct {})`      — "@sizeOf(T) > 0"
//   - `CachePad(struct { x: u8 align(std.atomic.cache_line * 2) })`
//   - `CacheAlign(struct { x: u8 align(std.atomic.cache_line * 2) })`
//                                                          — "natural @alignOf(T) exceeds std.atomic.cache_line"
