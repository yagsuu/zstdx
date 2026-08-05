//! SlabCache contract tests. See `docs/specs/mem/alloc/slab/cache.md`.

const std = @import("std");

const stdx = @import("stdx");

const SlabCache = stdx.mem.alloc.SlabCache;

const testing = std.testing;

// A backing store for the mock region source: `region_capacity` regions
// of `region_bytes` bytes each, plus counters and a small used-flag
// table. Instances are stack-allocated per test and passed by pointer to
// the region source.
fn MockStore(comptime bytes_per_region: usize, comptime region_capacity: usize) type {
    return struct {
        buffer: [region_capacity][bytes_per_region]u8 align(bytes_per_region) = undefined,
        used: [region_capacity]bool = [_]bool{false} ** region_capacity,
        acquire_calls: usize = 0,
        release_calls: usize = 0,
        acquire_returns_null_at: ?usize = null,

        const Self = @This();

        pub const region_bytes: usize = bytes_per_region;
        pub const region_align: usize = bytes_per_region;

        pub const Error = error{OutOfMemory};

        pub fn acquire(self: *Self) Error!*align(region_align) [region_bytes]u8 {
            if (self.acquire_returns_null_at) |threshold| {
                if (self.acquire_calls >= threshold) return error.OutOfMemory;
            }

            for (&self.used, 0..) |*used, i| {
                if (!used.*) {
                    used.* = true;
                    self.acquire_calls += 1;
                    return &self.buffer[i];
                }
            }
            return error.OutOfMemory;
        }

        pub fn release(self: *Self, region: *align(region_align) [region_bytes]u8) void {
            self.release_calls += 1;
            const region_addr = @intFromPtr(region);
            const base_addr = @intFromPtr(&self.buffer);
            const offset = region_addr - base_addr;
            const index = @divExact(offset, region_bytes);
            std.debug.assert(index < region_capacity);
            std.debug.assert(self.used[index]);
            self.used[index] = false;
        }

        pub fn liveRegions(self: *const Self) usize {
            var count: usize = 0;
            for (self.used) |used| {
                if (used) count += 1;
            }
            return count;
        }
    };
}

const Item = struct { value: u64 };

const WideAlignedStore = struct {
    buffer: [region_bytes]u8 align(region_align) = undefined,
    used: bool = false,

    pub const region_bytes: usize = 256;
    pub const region_align: usize = 512;
    pub const Error = error{OutOfMemory};

    pub fn acquire(self: *WideAlignedStore) Error!*align(region_align) [region_bytes]u8 {
        if (self.used) return error.OutOfMemory;
        self.used = true;
        return &self.buffer;
    }

    pub fn release(self: *WideAlignedStore, region: *align(region_align) [region_bytes]u8) void {
        std.debug.assert(region == &self.buffer);
        std.debug.assert(self.used);
        self.used = false;
    }
};

test "unit: SlabCache.init reports empty and does not call source" {
    const Store = MockStore(1024, 4);
    var store: Store = .{};
    var cache = SlabCache(Item, Store).init(&store);

    try testing.expectEqual(@as(usize, 0), cache.len());
    try testing.expectEqual(@as(usize, 0), cache.regionCount());
    try testing.expectEqual(@as(usize, 0), cache.capacity());
    try testing.expectEqual(@as(usize, 0), cache.remaining());
    try testing.expect(cache.isEmpty());
    try testing.expectError(error.OutOfMemory, cache.acquire());
    try testing.expectEqual(@as(usize, 0), store.acquire_calls);
    cache.assertValid();
}

test "unit: SlabCache.refill acquires one region and installs it empty" {
    const Store = MockStore(1024, 4);
    var store: Store = .{};
    var cache = SlabCache(Item, Store).init(&store);

    try cache.refill();
    try testing.expectEqual(@as(usize, 1), store.acquire_calls);
    try testing.expectEqual(@as(usize, 1), cache.regionCount());
    try testing.expect(cache.capacity() > 0);
    try testing.expectEqual(@as(usize, 0), cache.len());
    cache.assertValid();
}

test "unit: SlabCache.refill propagates source error without state change" {
    const Store = MockStore(1024, 4);
    var store: Store = .{};
    store.acquire_returns_null_at = 0; // fail every acquire
    var cache = SlabCache(Item, Store).init(&store);

    const before_count = cache.regionCount();
    try testing.expectError(error.OutOfMemory, cache.refill());
    try testing.expectEqual(before_count, cache.regionCount());
    try testing.expectEqual(@as(usize, 0), cache.len());
    cache.assertValid();
}

test "unit: SlabCache.acquire uses free slot without calling source" {
    const Store = MockStore(1024, 4);
    var store: Store = .{};
    var cache = SlabCache(Item, Store).init(&store);
    try cache.refill();

    const before_acquires = store.acquire_calls;
    const item = try cache.acquire();
    try testing.expectEqual(before_acquires, store.acquire_calls);
    try testing.expectEqual(@as(usize, 1), cache.len());
    try testing.expect(cache.contains(item));

    cache.release(item);
    try testing.expectEqual(@as(usize, 0), cache.len());
    cache.assertValid();
}

test "unit: SlabCache exhaustion returns OutOfMemory without source call" {
    const Store = MockStore(256, 4);
    var store: Store = .{};
    var cache = SlabCache(Item, Store).init(&store);
    try cache.refill();

    const capacity = cache.capacity();
    var items: [1024]*Item = undefined;
    var i: usize = 0;
    while (i < capacity) : (i += 1) {
        items[i] = try cache.acquire();
    }

    const before_acquires = store.acquire_calls;
    try testing.expectError(error.OutOfMemory, cache.acquire());
    try testing.expectEqual(before_acquires, store.acquire_calls);
    try testing.expectEqual(capacity, cache.len());
    cache.assertValid();

    var j: usize = 0;
    while (j < capacity) : (j += 1) {
        cache.release(items[j]);
    }
    cache.assertValid();
}

test "unit: SlabCache.drain returns only empty regions to source" {
    const Store = MockStore(1024, 4);
    var store: Store = .{};
    var cache = SlabCache(Item, Store).init(&store);

    try cache.refill();
    try cache.refill();
    try testing.expectEqual(@as(usize, 2), cache.regionCount());

    const item = try cache.acquire();

    const releases_before = store.release_calls;
    cache.drain();
    // One region was empty and returned; the other still holds a live
    // slot and stays.
    try testing.expectEqual(releases_before + 1, store.release_calls);
    try testing.expectEqual(@as(usize, 1), cache.regionCount());

    cache.release(item);
    cache.drain();
    try testing.expectEqual(@as(usize, 0), cache.regionCount());
    try testing.expectEqual(@as(usize, 0), store.liveRegions());
    cache.assertValid();
}

test "unit: SlabCache.contains rejects foreign pointers" {
    const Store = MockStore(1024, 4);
    var store: Store = .{};
    var cache = SlabCache(Item, Store).init(&store);
    try cache.refill();

    var stray: Item = .{ .value = 0 };
    try testing.expect(!cache.contains(&stray));

    const item = try cache.acquire();
    try testing.expect(cache.contains(item));
    cache.release(item);
    cache.assertValid();
}

test "unit: SlabCache recovers a region with alignment larger than its size" {
    var store: WideAlignedStore = .{};
    var cache = SlabCache(Item, WideAlignedStore).init(&store);
    try cache.refill();

    const item = try cache.acquire();
    try testing.expect(cache.contains(item));
    cache.release(item);
    cache.drain();
    try testing.expect(!store.used);
}

test "unit: SlabCache.refill rotates slot colors and maintains doubly linked empty list" {
    const Store = MockStore(1024, 4);
    const Cache = SlabCache(Item, Store);
    comptime std.debug.assert(Cache.color_count == 2);

    var store: Store = .{};
    var cache = Cache.init(&store);
    try cache.refill();
    const first = cache.empty_head.?;
    try cache.refill();
    const second = cache.empty_head.?;

    try testing.expectEqual(Cache.color_stride, second.slot_offset - first.slot_offset);
    try testing.expectEqual(first, second.next.?);
    try testing.expectEqual(second, first.prev.?);
    cache.assertValid();
}

test "unit: SlabCache.release moves a non-head full region in O(1)" {
    const Store = MockStore(1024, 4);
    const Cache = SlabCache(Item, Store);
    var store: Store = .{};
    var cache = Cache.init(&store);
    try cache.refill();
    try cache.refill();

    var items: [2 * Cache.slots_per_region]*Item = undefined;
    for (&items) |*item| item.* = try cache.acquire();
    const older_full = cache.full_head.?.next.?;

    cache.release(items[0]);
    try testing.expectEqual(older_full, cache.partial_head.?);
    try testing.expect(cache.full_head.?.next == null);
    cache.assertValid();

    for (items[1..]) |item| cache.release(item);
    cache.drain();
    try testing.expectEqual(@as(usize, 0), cache.regionCount());
}

test "unit: SlabCache.PerCpu caches locally and drains through global cache" {
    const Store = MockStore(1024, 4);
    const Cache = SlabCache(Item, Store);
    const PerCpuCache = Cache.PerCpu(2, 2);
    var store: Store = .{};
    var cache = PerCpuCache.init(&store);
    try cache.refill();

    const a = try cache.acquire(0);
    const b = try cache.acquire(1);
    cache.release(1, a);
    cache.release(0, b);

    try testing.expectEqual(@as(usize, 0), cache.len());
    const reuse = try cache.acquire(1);
    try testing.expectEqual(a, reuse);
    cache.release(1, reuse);
    cache.assertValid();

    cache.drain();
    try testing.expectEqual(@as(usize, 0), cache.regionCount());
    try testing.expectEqual(@as(usize, 0), store.liveRegions());
}

test "model: SlabCache matches ArrayList oracle over random ops" {
    const Store = MockStore(512, 8);
    var store: Store = .{};
    var cache = SlabCache(u64, Store).init(&store);

    var live: std.ArrayList(*u64) = .empty;
    defer live.deinit(testing.allocator);

    var rng = std.Random.DefaultPrng.init(0xC0FFEE);
    const random = rng.random();

    var ops: usize = 0;
    while (ops < 2_000) : (ops += 1) {
        const choice = random.uintLessThan(u8, 100);
        if (choice < 60) {
            const item = cache.acquire() catch {
                cache.refill() catch continue;
                const item = try cache.acquire();
                item.* = @intCast(ops);
                try live.append(testing.allocator, item);
                continue;
            };
            item.* = @intCast(ops);
            try live.append(testing.allocator, item);
        } else if (choice < 90 and live.items.len > 0) {
            const idx = random.uintLessThan(usize, live.items.len);
            const item = live.swapRemove(idx);
            cache.release(item);
        } else if (choice < 97) {
            cache.refill() catch {};
        } else {
            cache.drain();
        }
        cache.assertValid();
        try testing.expectEqual(live.items.len, cache.len());
    }

    for (live.items) |item| cache.release(item);
    cache.drain();

    try testing.expectEqual(@as(usize, 0), cache.len());
    try testing.expectEqual(@as(usize, 0), cache.regionCount());
    try testing.expectEqual(store.acquire_calls, store.release_calls);
    try testing.expectEqual(@as(usize, 0), store.liveRegions());
    cache.assertValid();
}
