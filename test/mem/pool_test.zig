//! Pool contract tests. Spec: docs/specs/mem/pool.md.

const std = @import("std");

const stdx = @import("stdx");

const Pool = stdx.mem.Pool;

const testing = std.testing;

const Frame = struct {
    id: u32,
    payload: u32,
};

test "unit: Pool.Static reports capacity and starts empty" {
    var pool = Pool.Static(Frame, 4).init();
    try testing.expectEqual(@as(usize, 4), @TypeOf(pool).item_capacity);
    try testing.expectEqual(@as(usize, 4), pool.capacity());
    try testing.expectEqual(@as(usize, 0), pool.len());
    try testing.expectEqual(@as(usize, 4), pool.remaining());
    try testing.expect(pool.isEmpty());
    try testing.expect(!pool.isFull());
    pool.assertValid();
}

test "unit: Pool.Static(T, 0) is empty and full and exhausts immediately" {
    var pool = Pool.Static(Frame, 0).init();
    try testing.expectEqual(@as(usize, 0), pool.capacity());
    try testing.expect(pool.isEmpty());
    try testing.expect(pool.isFull());
    try testing.expectError(error.OutOfMemory, pool.acquire());
    pool.assertValid();
}

test "unit: Pool.Bounded.wrap(&.{}) is empty and full" {
    const PoolT = Pool.Bounded(Frame);
    var pool = PoolT.wrap(&.{});
    try testing.expectEqual(@as(usize, 0), pool.capacity());
    try testing.expect(pool.isEmpty());
    try testing.expect(pool.isFull());
    try testing.expectError(error.OutOfMemory, pool.acquire());
    pool.assertValid();
}

test "unit: Pool.Static acquires and releases with LIFO reuse" {
    var pool = Pool.Static(Frame, 3).init();
    const a = try pool.acquire();
    a.* = .{ .id = 1, .payload = 10 };
    const b = try pool.acquire();
    b.* = .{ .id = 2, .payload = 20 };
    const c = try pool.acquire();
    c.* = .{ .id = 3, .payload = 30 };
    try testing.expectError(error.OutOfMemory, pool.acquire());
    try testing.expectEqual(@as(usize, 3), pool.len());

    pool.release(b);
    try testing.expectEqual(@as(usize, 2), pool.len());
    const reuse = try pool.acquire();
    try testing.expectEqual(b, reuse);
    try testing.expectEqual(@as(u32, 1), a.id);
    try testing.expectEqual(@as(u32, 3), c.id);
    pool.assertValid();
}

test "unit: Pool.Static.acquire after exhaustion leaves live_count unchanged" {
    var pool = Pool.Static(Frame, 1).init();
    const a = try pool.acquire();
    try testing.expectError(error.OutOfMemory, pool.acquire());
    try testing.expectEqual(@as(usize, 1), pool.len());
    pool.release(a);
    try testing.expectEqual(@as(usize, 0), pool.len());
}

test "unit: Pool.Bounded over caller storage cycles through capacity" {
    const PoolT = Pool.Bounded(Frame);
    var storage: [4]PoolT.Slot = undefined;
    var pool = PoolT.wrap(&storage);
    try testing.expectEqual(@as(usize, 4), pool.capacity());

    var live: [4]*Frame = undefined;
    for (&live, 0..) |*slot, i| {
        slot.* = try pool.acquire();
        slot.*.* = .{ .id = @intCast(i), .payload = @intCast(i * 2) };
    }
    try testing.expectError(error.OutOfMemory, pool.acquire());
    for (live) |item| pool.release(item);
    try testing.expect(pool.isEmpty());
    pool.assertValid();
}

test "unit: Pool.Static clearRetainingCapacity rebuilds the free list" {
    var pool = Pool.Static(Frame, 4).init();
    _ = try pool.acquire();
    _ = try pool.acquire();
    try testing.expectEqual(@as(usize, 2), pool.len());
    pool.clearRetainingCapacity();
    try testing.expectEqual(@as(usize, 0), pool.len());
    try testing.expectEqual(@as(usize, 4), pool.remaining());

    var live: [4]*Frame = undefined;
    for (&live, 0..) |*slot, i| {
        slot.* = try pool.acquire();
        slot.*.* = .{ .id = @intCast(i), .payload = 0 };
    }
    try testing.expectError(error.OutOfMemory, pool.acquire());
    pool.assertValid();
}

test "unit: Pool.Static returns pointers that satisfy @alignOf(T)" {
    var pool = Pool.Static(u64, 4).init();
    const p = try pool.acquire();
    try testing.expect(stdx.mem.isAligned(usize, @intFromPtr(p), @alignOf(u64)));
    pool.release(p);
}

test "unit: Pool.Bounded backed by Arena storage acquires until exhaustion" {
    var arena = stdx.mem.Arena.Static(4 * 1024).init();
    const PoolT = Pool.Bounded(Frame);
    const storage = try arena.allocSlice(PoolT.Slot, 8);
    var pool = PoolT.wrap(storage);
    try testing.expectEqual(@as(usize, 8), pool.capacity());

    var live: [8]*Frame = undefined;
    for (&live, 0..) |*slot, i| {
        slot.* = try pool.acquire();
        slot.*.* = .{ .id = @intCast(i), .payload = 0 };
    }
    try testing.expectError(error.OutOfMemory, pool.acquire());
    pool.assertValid();
}

test "unit: Pool.Static invariants hold across many acquire/release cycles" {
    var pool = Pool.Static(Frame, 8).init();
    var live: [8]?*Frame = .{ null, null, null, null, null, null, null, null };
    var rng = std.Random.DefaultPrng.init(0x1234);
    var random = rng.random();
    var iter: usize = 0;
    while (iter < 256) : (iter += 1) {
        const idx = random.intRangeAtMost(usize, 0, 7);
        if (live[idx]) |item| {
            pool.release(item);
            live[idx] = null;
        } else {
            live[idx] = try pool.acquire();
        }
    }
    pool.assertValid();
    var expected_live: usize = 0;
    for (live) |entry| if (entry != null) {
        expected_live += 1;
    };
    try testing.expectEqual(expected_live, pool.len());
}

test "unit: Pool families produce distinct types per element and capacity" {
    try testing.expect(Pool.Bounded(Frame) != Pool.Bounded(u32));
    try testing.expect(Pool.Static(Frame, 4) != Pool.Static(Frame, 8));
}
