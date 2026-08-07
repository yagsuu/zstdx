//! Buddy arithmetic contract tests. See `docs/specs/algo/alloc/buddy.md`.

const std = @import("std");
const buddy = @import("stdx").algo.alloc.buddy;
const testing = std.testing;

test "unit: blockSize returns powers of two and rejects unrepresentable orders" {
    try testing.expectEqual(@as(usize, 1), try buddy.blockSize(0));
    try testing.expectEqual(@as(usize, 2), try buddy.blockSize(1));
    try testing.expectEqual(@as(usize, 1024), try buddy.blockSize(10));

    const bits = @bitSizeOf(usize);
    try testing.expectError(error.Overflow, buddy.blockSize(@intCast(bits)));
}

test "unit: orderForLen rounds up and rejects zero and unrepresentable lengths" {
    try testing.expectEqual(@as(u8, 0), try buddy.orderForLen(1));
    try testing.expectEqual(@as(u8, 1), try buddy.orderForLen(2));
    try testing.expectEqual(@as(u8, 2), try buddy.orderForLen(3));
    try testing.expectEqual(@as(u8, 10), try buddy.orderForLen(1024));
    try testing.expectEqual(@as(u8, 11), try buddy.orderForLen(1025));
    try testing.expectError(error.InvalidRequest, buddy.orderForLen(0));

    const highest: usize = @as(usize, 1) << (@bitSizeOf(usize) - 1);
    try testing.expectEqual(@as(u8, @bitSizeOf(usize) - 1), try buddy.orderForLen(highest));
    try testing.expectError(error.Overflow, buddy.orderForLen(highest + 1));
}

test "unit: contains uses a half-open block extent" {
    const block: buddy.Block = .{ .start = 16, .order = 3 };
    try testing.expect(try buddy.contains(block, 16));
    try testing.expect(try buddy.contains(block, 23));
    try testing.expect(!(try buddy.contains(block, 24)));
    try testing.expect(!(try buddy.contains(block, 15)));
}

test "unit: buddyOf returns the adjacent sibling" {
    const block: buddy.Block = .{ .start = 16, .order = 3 };
    const sibling = try buddy.buddyOf(block);
    try testing.expectEqual(@as(usize, 24), sibling.start);
    try testing.expectEqual(block.order, sibling.order);
    try testing.expectEqual(block, try buddy.buddyOf(sibling));
}

test "unit: parentOf returns the containing next-order block" {
    const left = try buddy.parentOf(.{ .start = 16, .order = 3 });
    const right = try buddy.parentOf(.{ .start = 24, .order = 3 });
    try testing.expectEqual(buddy.Block{ .start = 16, .order = 4 }, left);
    try testing.expectEqual(left, right);

    const top: u8 = @bitSizeOf(usize) - 1;
    try testing.expectError(error.Overflow, buddy.parentOf(.{ .start = 0, .order = top }));
}

test "unit: split returns exact child geometry and rejects order zero" {
    const children = try buddy.split(.{ .start = 16, .order = 3 });
    try testing.expectEqual(buddy.Block{ .start = 16, .order = 2 }, children[0]);
    try testing.expectEqual(buddy.Block{ .start = 20, .order = 2 }, children[1]);
    try testing.expectError(error.InvalidRequest, buddy.split(.{ .start = 0, .order = 0 }));
}

test "unit: canCoalesce distinguishes siblings" {
    try testing.expect(buddy.canCoalesce(
        .{ .start = 0, .order = 2 },
        .{ .start = 4, .order = 2 },
    ));
    try testing.expect(!buddy.canCoalesce(
        .{ .start = 4, .order = 2 },
        .{ .start = 8, .order = 2 },
    ));
    try testing.expect(!buddy.canCoalesce(
        .{ .start = 0, .order = 2 },
        .{ .start = 4, .order = 3 },
    ));
}

test "compile: public surface exposes buddy namespace" {
    _ = buddy.Error;
    _ = buddy.Block;
    _ = buddy.blockSize;
    _ = buddy.orderForLen;
    _ = buddy.contains;
    _ = buddy.buddyOf;
    _ = buddy.parentOf;
    _ = buddy.split;
    _ = buddy.canCoalesce;
}
