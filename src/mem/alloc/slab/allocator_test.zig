const std = @import("std");
const Arena = @import("../arena.zig").Arena;

const testing = std.testing;
const SlabAllocator = @import("allocator.zig").SlabAllocator;

const Frame = struct {
    id: u32,
    payload: u32,
};

test "unit: Arena-backed SlabAllocator stores and reuses objects" {
    var arena = Arena.Static(4 * 1024).init();
    const Slab = SlabAllocator.Bounded(Frame);
    const items = try arena.allocSlice(Slab.Slot, 3);
    var pool = Slab.wrap(items);
    const a = try pool.acquire();
    const b = try pool.acquire();
    const c = try pool.acquire();
    a.* = .{ .id = 1, .payload = 10 };
    b.* = .{ .id = 2, .payload = 20 };
    c.* = .{ .id = 3, .payload = 30 };

    try testing.expectError(error.OutOfMemory, pool.acquire());
    try testing.expectEqual(@as(usize, 3), pool.len());
    try testing.expectEqual(@as(u32, 20), b.payload);

    pool.release(b);
    const reused = try pool.acquire();
    reused.* = .{ .id = 4, .payload = 40 };

    try testing.expectEqual(b, reused);
    try testing.expectEqual(@as(u32, 10), a.payload);
    try testing.expectEqual(@as(u32, 30), c.payload);
    try testing.expectEqual(@as(u32, 40), reused.payload);
    try testing.expectError(error.OutOfMemory, pool.acquire());

    pool.release(a);
    pool.release(reused);
    pool.release(c);

    try testing.expect(pool.isEmpty());
    try testing.expectEqual(pool.capacity(), pool.remaining());
    try testing.expect(pool.isValid());
}
