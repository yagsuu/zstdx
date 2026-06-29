//! Ring contract tests.
//! Specs: docs/specs/collections/ring-static.md and docs/specs/collections/ring-bounded.md.

const std = @import("std");

const zstdx = @import("zstdx");

const Ring = zstdx.Ring;

const testing = std.testing;

test "unit: Ring.Static(T, 0) reports full and returns input from overwriteOldest" {
    var zero = Ring.Static(u8, 0).init();
    try testing.expect(zero.isFull());
    try testing.expectError(error.Full, zero.pushBack(1));
    try testing.expectEqual(@as(?u8, 1), zero.pushBackOverwriteOldest(1));
    try testing.expectEqual(@as(?*u8, null), zero.front());
}

test "unit: Ring.Static enforces FIFO and reports error.Full" {
    var ring = Ring.Static(u8, 3).init();
    try ring.pushBack(1);
    try ring.pushBack(2);
    try ring.pushBack(3);
    try testing.expectError(error.Full, ring.pushBack(4));
    try testing.expectEqual(@as(u8, 1), ring.front().?.*);
    try testing.expectEqual(@as(u8, 3), ring.back().?.*);
    try testing.expectEqual(@as(?u8, 1), ring.popFront());
    try ring.pushBack(4);
    try testing.expectEqual(@as(?u8, 2), ring.pushBackOverwriteOldest(5));
    try testing.expectEqual(@as(?u8, 3), ring.popFront());
    try testing.expectEqual(@as(?u8, 4), ring.popFront());
    try testing.expectEqual(@as(?u8, 5), ring.popFront());
    try testing.expectEqual(@as(?u8, null), ring.popFront());
    ring.clearRetainingCapacity();
    ring.assertValid();
}

test "unit: Ring.Static drains in enqueue order for a sibling-shaped FIFO" {
    var fifo = Ring.Static(u16, 4).init();
    try fifo.pushBack(10);
    try fifo.pushBack(20);
    try fifo.pushBack(30);
    try testing.expectEqual(@as(?u16, 10), fifo.popFront());
    try testing.expectEqual(@as(?u16, 20), fifo.popFront());
    try testing.expectEqual(@as(?u16, 30), fifo.popFront());
}
