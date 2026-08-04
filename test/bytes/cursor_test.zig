//! Byte cursor contract tests. See `docs/specs/bytes/cursor.md`.

const std = @import("std");

const stdx = @import("stdx");

const layout = stdx.layout;

const Cursor = stdx.bytes.Cursor;

const testing = std.testing;

test "unit: cursor peek does not advance and read advances" {
    const data = [_]u8{ 1, 2, 3, 4 };
    var c = Cursor.wrap(&data);
    try testing.expectEqual(@as(usize, 0), c.position());
    try testing.expectEqualSlices(u8, &.{ 1, 2 }, try c.peekBytes(2));
    try testing.expectEqual(@as(usize, 0), c.position());
    try testing.expectEqualSlices(u8, &.{ 1, 2 }, try c.readBytes(2));
    try testing.expectEqual(@as(usize, 2), c.position());
}

test "unit: failed read/skip leaves the cursor position unchanged" {
    const data = [_]u8{ 1, 2 };
    var c = Cursor.wrap(&data);
    c.index = 1;
    try testing.expectError(error.EndOfStream, c.readBytes(3));
    try testing.expectEqual(@as(usize, 1), c.position());
    try testing.expectError(error.EndOfStream, c.skip(2));
    try testing.expectEqual(@as(usize, 1), c.position());
}

test "unit: cursor copy serves as a checkpoint" {
    const data = [_]u8{ 1, 2, 3, 4 };
    var c = Cursor.wrap(&data);
    _ = try c.readBytes(2);
    const saved = c;
    try testing.expectEqual(@as(u8, 3), try c.read(u8));
    c = saved;
    try testing.expectEqual(@as(usize, 2), c.position());
}

test "unit: cursor exhausts to isEmpty and refuses further skips" {
    const data = [_]u8{ 1, 2 };
    var c = Cursor.wrap(&data);
    try c.skip(2);
    try testing.expect(c.isEmpty());
    try testing.expectError(error.EndOfStream, c.skip(1));
}

test "unit: cursor typed reads route through layout endian wrappers" {
    const data = [_]u8{ 0x34, 0x12, 0x12, 0x34 };
    var c = Cursor.wrap(&data);
    try testing.expectEqual(@as(u16, 0x1234), (try c.read(layout.Le(u16))).native());
    try testing.expectEqual(@as(u16, 0x1234), (try c.read(layout.Be(u16))).native());
}
