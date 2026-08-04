//! Random byte access contract tests. See `docs/specs/bytes/access.md`.

const std = @import("std");

const stdx = @import("stdx");
const bytes = stdx.bytes;
const Le = stdx.layout.Le;

const testing = std.testing;

test "unit: typed load and store round-trip at start and last valid offset" {
    var buf = [_]u8{0} ** 8;
    try bytes.store(u32, &buf, 0, 0x11223344);
    try testing.expectEqual(@as(u32, 0x11223344), try bytes.load(u32, &buf, 0));
    try bytes.store(u32, &buf, 4, 0xaabbccdd);
    try testing.expectEqual(@as(u32, 0xaabbccdd), try bytes.load(u32, &buf, 4));
}

test "unit: typed access reports EndOfStream without mutating destination" {
    var buf = [_]u8{ 1, 2, 3, 4 };
    const before = buf;
    try testing.expectError(error.EndOfStream, bytes.load(u32, &buf, 1));
    try testing.expectError(error.EndOfStream, bytes.load(u32, &buf, std.math.maxInt(usize)));
    try testing.expectError(error.EndOfStream, bytes.store(u32, &buf, buf.len, 0));
    try testing.expectEqualSlices(u8, &before, &buf);
}

test "unit: loadSlice returns borrowed full and empty windows" {
    const buf = [_]u8{ 1, 2, 3, 4 };
    try testing.expectEqualSlices(u8, &buf, try bytes.loadSlice(&buf, 0, buf.len));
    try testing.expectEqual(@as(usize, 0), (try bytes.loadSlice(&buf, buf.len, 0)).len);
    try testing.expectError(error.EndOfStream, bytes.loadSlice(&buf, buf.len + 1, 0));
    try testing.expectError(error.EndOfStream, bytes.loadSlice(&buf, 2, 3));
}

test "unit: storeSlice copies after successful bounds check only" {
    var buf = [_]u8{ 1, 2, 3, 4 };
    try bytes.storeSlice(&buf, 1, &.{ 9, 8 });
    try testing.expectEqualSlices(u8, &.{ 1, 9, 8, 4 }, &buf);
    try bytes.storeSlice(&buf, buf.len, &.{});
    const before = buf;
    try testing.expectError(error.EndOfStream, bytes.storeSlice(&buf, 3, &.{ 7, 6 }));
    try testing.expectEqualSlices(u8, &before, &buf);
}

test "unit: storeSlice has defined overlapping copy behavior" {
    var forward = [_]u8{ 1, 2, 3, 4, 5 };
    try bytes.storeSlice(&forward, 1, forward[0..3]);
    try testing.expectEqualSlices(u8, &.{ 1, 1, 2, 3, 5 }, &forward);

    var backward = [_]u8{ 1, 2, 3, 4, 5 };
    try bytes.storeSlice(&backward, 0, backward[1..4]);
    try testing.expectEqualSlices(u8, &.{ 2, 3, 4, 4, 5 }, &backward);
}

test "unit: loadTail returns borrowed tail and empty tail" {
    const buf = [_]u8{ 1, 2, 3, 4 };
    try testing.expectEqualSlices(u8, &.{ 3, 4 }, try bytes.loadTail(&buf, 2));
    try testing.expectEqual(@as(usize, 0), (try bytes.loadTail(&buf, buf.len)).len);
    try testing.expectError(error.EndOfStream, bytes.loadTail(&buf, buf.len + 1));
}

test "unit: access composes with endian layout wrappers" {
    const Le32 = Le(u32);
    var buf = [_]u8{0} ** 8;
    try bytes.store(Le32, &buf, 2, Le32.fromNative(0x12345678));
    try testing.expectEqualSlices(u8, &.{ 0x78, 0x56, 0x34, 0x12 }, buf[2..6]);
    try testing.expectEqual(@as(u32, 0x12345678), (try bytes.load(Le32, &buf, 2)).native());
}
