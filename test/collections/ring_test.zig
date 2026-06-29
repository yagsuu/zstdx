//! Ring contract tests.
//! Specs: docs/specs/collections/ring-static.md and docs/specs/collections/ring-bounded.md.

const std = @import("std");

const stdx = @import("stdx");

const Ring = stdx.Ring;

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

test "unit: Ring.Bounded zero-length buffer is empty and full" {
    var storage: [0]u8 = .{};
    var ring = Ring.Bounded(u8).wrap(&storage);
    try testing.expect(ring.isEmpty());
    try testing.expect(ring.isFull());
    try testing.expectEqual(@as(usize, 0), ring.capacity());
    try testing.expectError(error.Full, ring.pushBack(1));
    try testing.expectEqual(@as(?u8, 1), ring.pushBackOverwriteOldest(1));
    try testing.expectEqual(@as(?u8, null), ring.popFront());
    try testing.expectEqual(@as(?*u8, null), ring.front());
    try testing.expectEqual(@as(?*const u8, null), ring.constFront());
    try testing.expectEqual(@as(?*u8, null), ring.back());
    try testing.expectEqual(@as(?*const u8, null), ring.constBack());
    ring.assertValid();
}

test "unit: Ring.Bounded wraps caller storage and preserves FIFO across wrap" {
    var storage: [3]u8 = undefined;
    var ring = Ring.Bounded(u8).wrap(&storage);
    try testing.expectEqual(@as(usize, 3), ring.capacity());
    try ring.pushBack(1);
    try ring.pushBack(2);
    try ring.pushBack(3);
    try testing.expect(ring.isFull());
    try testing.expectError(error.Full, ring.pushBack(4));
    try testing.expectEqual(@as(u8, 1), ring.front().?.*);
    try testing.expectEqual(@as(u8, 3), ring.back().?.*);
    try testing.expectEqual(@as(?u8, 1), ring.popFront());
    try ring.pushBack(4);
    try testing.expectEqual(@as(?u8, 2), ring.popFront());
    try testing.expectEqual(@as(?u8, 3), ring.popFront());
    try testing.expectEqual(@as(?u8, 4), ring.popFront());
    try testing.expectEqual(@as(?u8, null), ring.popFront());
    ring.assertValid();
}

test "unit: Ring.Bounded overwrite evicts oldest and clear keeps backing storage" {
    var storage: [2]u8 = undefined;
    var ring = Ring.Bounded(u8).wrap(&storage);
    try ring.pushBack(10);
    try ring.pushBack(20);
    try testing.expectEqual(@as(?u8, 10), ring.pushBackOverwriteOldest(30));
    try testing.expectEqual(@as(u8, 20), ring.front().?.*);
    try testing.expectEqual(@as(u8, 30), ring.back().?.*);
    ring.clearRetainingCapacity();
    try testing.expect(ring.isEmpty());
    try testing.expectEqual(@as(usize, 2), ring.remaining());
    try ring.pushBack(40);
    try testing.expectEqual(@as(?u8, 40), ring.popFront());
}

test "unit: Ring.Bounded pointer access mutates caller storage" {
    var storage: [2]u8 = undefined;
    var ring = Ring.Bounded(u8).wrap(&storage);
    try ring.pushBack(5);
    ring.front().?.* = 7;
    try testing.expectEqual(@as(u8, 7), ring.constFront().?.*);
    try ring.pushBack(9);
    ring.back().?.* = 11;
    try testing.expectEqual(@as(u8, 11), ring.constBack().?.*);
    try testing.expectEqual(@as(?u8, 7), ring.popFront());
    try testing.expectEqual(@as(?u8, 11), ring.popFront());
}
