//! Random byte access contract tests. See `docs/specs/bytes/access.md`.

const std = @import("std");

const stdx = @import("stdx");
const bytes = stdx.bytes;

const testing = std.testing;

test "unit: loadSlice returns borrowed full and empty windows" {
    const buf = [_]u8{ 1, 2, 3, 4 };
    try testing.expectEqualSlices(u8, &buf, try bytes.loadSlice(&buf, 0, buf.len));
    try testing.expectEqual(@as(usize, 0), (try bytes.loadSlice(&buf, buf.len, 0)).len);
    try testing.expectError(error.EndOfStream, bytes.loadSlice(&buf, buf.len + 1, 0));
    try testing.expectError(error.EndOfStream, bytes.loadSlice(&buf, 2, 3));
    try testing.expectError(
        error.EndOfStream,
        bytes.loadSlice(&buf, std.math.maxInt(usize), 1),
    );
}

test "unit: storeSlice copies after successful bounds check only" {
    var buf = [_]u8{ 1, 2, 3, 4 };
    try bytes.storeSlice(&buf, 1, &.{ 9, 8 });
    try testing.expectEqualSlices(u8, &.{ 1, 9, 8, 4 }, &buf);
    try bytes.storeSlice(&buf, buf.len, &.{});
    const before = buf;
    try testing.expectError(error.EndOfStream, bytes.storeSlice(&buf, 3, &.{ 7, 6 }));
    try testing.expectEqualSlices(u8, &before, &buf);
    try testing.expectError(
        error.EndOfStream,
        bytes.storeSlice(&buf, std.math.maxInt(usize), &.{1}),
    );
}

test "unit: storeSlice has defined overlapping copy behavior" {
    var forward = [_]u8{ 1, 2, 3, 4, 5 };
    try bytes.storeSlice(&forward, 1, forward[0..3]);
    try testing.expectEqualSlices(u8, &.{ 1, 1, 2, 3, 5 }, &forward);

    var backward = [_]u8{ 1, 2, 3, 4, 5 };
    try bytes.storeSlice(&backward, 0, backward[1..4]);
    try testing.expectEqualSlices(u8, &.{ 2, 3, 4, 4, 5 }, &backward);
}
