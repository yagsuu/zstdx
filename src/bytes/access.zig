//! Bounds-checked random byte access. See `docs/specs/bytes/access.md`.

const std = @import("std");

pub const Error = error{EndOfStream};

pub fn loadSlice(bytes: []const u8, offset: usize, len: usize) Error![]const u8 {
    const end = try checkedEnd(bytes.len, offset, len);
    return bytes[offset..end];
}

pub fn storeSlice(bytes: []u8, offset: usize, src: []const u8) Error!void {
    const end = try checkedEnd(bytes.len, offset, src.len);
    @memmove(bytes[offset..end], src);
}

fn checkedEnd(capacity: usize, offset: usize, len: usize) Error!usize {
    if (offset > capacity) {
        return error.EndOfStream;
    }
    if (len > capacity - offset) {
        return error.EndOfStream;
    }
    return offset + len;
}

pub const unit = struct {
    const testing = std.testing;

    test "unit: loadSlice borrows bounded byte windows" {
        var bytes = [_]u8{ 1, 2, 3, 4 };
        const first = try loadSlice(&bytes, 0, 2);
        const rest = try loadSlice(&bytes, 2, 2);

        bytes[0] = 9;

        try testing.expectEqualSlices(u8, &.{ 9, 2 }, first);
        try testing.expectEqualSlices(u8, &.{ 3, 4 }, rest);
        try testing.expectEqual(@as(usize, 0), (try loadSlice(&bytes, bytes.len, 0)).len);
        try testing.expectError(error.EndOfStream, loadSlice(&bytes, bytes.len + 1, 0));
        try testing.expectError(error.EndOfStream, loadSlice(&bytes, 2, 3));
        try testing.expectError(error.EndOfStream, loadSlice(&bytes, std.math.maxInt(usize), 1));
    }

    test "unit: storeSlice leaves bytes unchanged on bounds failure" {
        var bytes = [_]u8{ 1, 2, 3, 4 };

        try storeSlice(&bytes, 1, &.{ 9, 8 });
        try storeSlice(&bytes, bytes.len, &.{});

        try testing.expectEqualSlices(u8, &.{ 1, 9, 8, 4 }, &bytes);
        const before = bytes;

        try testing.expectError(error.EndOfStream, storeSlice(&bytes, 3, &.{ 7, 6 }));
        try testing.expectEqualSlices(u8, &before, &bytes);
        try testing.expectError(error.EndOfStream, storeSlice(&bytes, std.math.maxInt(usize), &.{1}));
        try testing.expectEqualSlices(u8, &before, &bytes);
    }

    test "unit: storeSlice copies overlapping regions in either direction" {
        var forward = [_]u8{ 1, 2, 3, 4, 5 };

        try storeSlice(&forward, 1, forward[0..3]);
        try testing.expectEqualSlices(u8, &.{ 1, 1, 2, 3, 5 }, &forward);

        var backward = [_]u8{ 1, 2, 3, 4, 5 };
        try storeSlice(&backward, 0, backward[1..4]);
        try testing.expectEqualSlices(u8, &.{ 2, 3, 4, 4, 5 }, &backward);
    }
};
