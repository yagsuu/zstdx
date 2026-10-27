const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const SlabCache = stdx.mem.alloc.SlabCache;

const testing = std.testing;

fn RegionSource(comptime bytes: usize, comptime alignment: usize, comptime capacity: usize) type {
    return struct {
        regions: [capacity]Region = undefined,
        used: [capacity]bool = [_]bool{false} ** capacity,

        const Region = struct { buffer: [bytes]u8 align(alignment) };
        const Self = @This();

        pub const region_bytes = bytes;
        pub const region_align = alignment;
        pub const Error = error{OutOfRegions};

        pub fn acquire(self: *Self) Error!*align(region_align) [region_bytes]u8 {
            for (&self.used, 0..) |*used, i| {
                if (!used.*) {
                    used.* = true;
                    return &self.regions[i].buffer;
                }
            }
            return error.OutOfRegions;
        }

        pub fn release(self: *Self, region: *align(region_align) [region_bytes]u8) void {
            const offset = @intFromPtr(region) - @intFromPtr(&self.regions);
            const index = @divExact(offset, @sizeOf(Region));
            std.debug.assert(index < capacity);
            std.debug.assert(self.used[index]);
            self.used[index] = false;
        }

        fn liveRegions(self: *const Self) usize {
            var count: usize = 0;
            for (self.used) |used| {
                if (used) {
                    count += 1;
                }
            }
            return count;
        }
    };
}

test "integration: slab source preserves capacity and payload across colors and recovery" {
    const Payload = [4 * std.atomic.cache_line]u8;
    const bytes = 16 * std.atomic.cache_line;
    const Source = RegionSource(bytes, 2 * bytes, 1);
    const Cache = SlabCache(Payload, Source);
    var source: Source = .{};
    var cache = Cache.init(&source);
    var items: [Cache.slots_per_region]*Payload = undefined;
    var first_offset: usize = undefined;

    try testing.expect(Cache.color_count > 1);

    for (0..Cache.color_count + 1) |cycle| {
        try cache.refill();
        try testing.expectEqual(Cache.slots_per_region, cache.capacity());
        try testing.expectError(error.OutOfRegions, cache.refill());

        var lowest_address: usize = std.math.maxInt(usize);
        for (&items, 0..) |*item, i| {
            item.* = try cache.acquire();
            @memset(item.*, @intCast(i + 1));
            lowest_address = @min(lowest_address, @intFromPtr(item.*));
        }
        const offset = lowest_address - @intFromPtr(&source.regions[0].buffer);
        if (cycle == 0) {
            first_offset = offset;
        }

        try testing.expectEqual(first_offset + (cycle % Cache.color_count) * Cache.color_stride, offset);
        try testing.expectEqual(items.len, cache.len());
        try testing.expectError(error.OutOfMemory, cache.acquire());
        for (items, 0..) |item, i| {
            try testing.expect(cache.contains(item));
            for (item) |byte| {
                try testing.expectEqual(@as(u8, @intCast(i + 1)), byte);
            }
        }
        try testing.expect(cache.isValid());

        for (items[1..]) |item| {
            cache.release(item);
        }
        cache.drain();

        try testing.expectEqual(@as(usize, 1), source.liveRegions());
        try testing.expectEqual(@as(usize, 1), cache.len());
        for (items[0]) |byte| {
            try testing.expectEqual(@as(u8, 1), byte);
        }

        cache.release(items[0]);
        cache.drain();

        try testing.expectEqual(@as(usize, 0), source.liveRegions());
        try testing.expectEqual(@as(usize, 0), cache.regionCount());
        try testing.expectEqual(@as(usize, 0), cache.capacity());
        try testing.expect(cache.isValid());
    }
}

test "integration: slab per-cpu workers preserve payloads and drain after joining" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }
    const Payload = struct { owner: usize, sequence: usize };
    const Source = RegionSource(1024, 1024, 4);
    const Cache = SlabCache(Payload, Source).PerCpu(4, 4);
    const Worker = struct {
        cache: *Cache,
        start: *std.atomic.Value(bool),
        cpu_index: usize,
        failed: bool = false,

        fn run(self: *@This()) void {
            while (!self.start.load(.acquire)) {
                std.atomic.spinLoopHint();
            }
            for (0..256) |sequence| {
                var items: [8]*Payload = undefined;
                var acquired: usize = 0;
                for (&items) |*item| {
                    item.* = self.cache.acquire(self.cpu_index) catch {
                        self.failed = true;
                        break;
                    };
                    item.*.* = .{ .owner = self.cpu_index, .sequence = sequence };
                    acquired += 1;
                }
                for (items[0..acquired]) |item| {
                    if (item.owner != self.cpu_index or item.sequence != sequence) {
                        self.failed = true;
                    }
                    self.cache.release(self.cpu_index, item);
                }
                if (self.failed) {
                    return;
                }
            }
        }
    };
    var source: Source = .{};
    var cache = Cache.init(&source);
    for (0..4) |_| {
        try cache.refill();
    }
    var start = std.atomic.Value(bool).init(false);
    var workers: [4]Worker = undefined;
    var threads: [4]std.Thread = undefined;
    var started: usize = 0;
    errdefer {
        start.store(true, .release);
        for (threads[0..started]) |thread| {
            thread.join();
        }
        cache.drain();
    }
    for (&workers, 0..) |*worker, i| {
        worker.* = .{ .cache = &cache, .start = &start, .cpu_index = i };
        threads[i] = try std.Thread.spawn(.{}, Worker.run, .{worker});
        started += 1;
    }
    start.store(true, .release);
    for (threads) |thread| {
        thread.join();
    }
    started = 0;

    for (workers) |worker| {
        try testing.expect(!worker.failed);
    }
    try testing.expectEqual(@as(usize, 0), cache.len());
    try testing.expect(cache.isValid());

    cache.drain();

    try testing.expectEqual(@as(usize, 0), cache.regionCount());
    try testing.expectEqual(@as(usize, 0), source.liveRegions());
    try testing.expect(cache.isValid());
}
