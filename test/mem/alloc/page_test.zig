const std = @import("std");
const testing = std.testing;
const stdx = @import("stdx");

test "region source composes with SlabCache over host memory" {
    const page_size = stdx.addr.pages._4kib;
    const count = 4;
    const Page = stdx.addr.Page(stdx.addr.VirtAddr, page_size);
    const Backend = stdx.mem.alloc.BuddyAllocator.Static(count, 3);
    const Pages = stdx.mem.alloc.PageAllocator.Bounded(Backend, Page);
    const backing = try testing.allocator.alignedAlloc(u8, .fromByteUnits(page_size), count * page_size);
    defer testing.allocator.free(backing);

    const origin = try Page.Base.fromInt(@intCast(@intFromPtr(backing.ptr)));
    var pages = try Pages.init(Backend.init(), origin);
    const Source = struct {
        pages: *Pages,
        items: []align(page_size) u8,
        allocations: [count]?Pages.Allocation = @splat(null),

        const Self = @This();
        const Region = *align(page_size) [page_size]u8;
        pub const region_bytes = page_size;
        pub const region_align = page_size;
        pub const Error = Pages.Error;

        pub fn acquire(self: *Self) Error!Region {
            const allocation = try self.pages.alloc(0);
            const range = allocation.range();
            const offset = range.base.raw() - @intFromPtr(self.items.ptr);
            std.debug.assert(offset <= self.items.len - page_size);
            self.allocations[offset / page_size] = allocation;
            return @ptrCast(@alignCast(self.items.ptr + offset));
        }

        pub fn release(self: *Self, region: Region) void {
            const address = @intFromPtr(region);
            const start = @intFromPtr(self.items.ptr);
            std.debug.assert(address >= start and address - start <= self.items.len - page_size);

            const index = (address - start) / page_size;
            self.pages.free(self.allocations[index].?) catch unreachable;
            self.allocations[index] = null;
        }
    };
    var source: Source = .{ .pages = &pages, .items = backing };
    const Cache = stdx.mem.alloc.SlabCache(u64, @TypeOf(source));
    var cache = Cache.init(&source);
    try cache.refill();
    const item = try cache.acquire();
    item.* = 0xDEAD_BEEF;

    try testing.expectEqual(@as(u64, 0xDEAD_BEEF), item.*);
    try testing.expect(cache.contains(item));

    cache.release(item);
    cache.drain();

    try testing.expectEqual(@as(u64, 0), pages.allocated());
    try testing.expect(cache.isValid());
    try testing.expect(pages.isValid());
}

test "page allocation with buddy backend matches allocation oracle" {
    const Page = stdx.addr.Page(stdx.addr.PhysAddr, 4096);
    const Backend = stdx.mem.alloc.BuddyAllocator.Static(16, 5);
    const origin = comptime Page.Base.fromInt(0x100000) catch unreachable;
    const Pages = stdx.mem.alloc.PageAllocator.Static(Backend, Page, origin);
    var pages = Pages.init();
    var allocated: [16]bool = @splat(false);
    var live: [16]?Pages.Allocation = @splat(null);
    var count: usize = 0;
    var rng = std.Random.DefaultPrng.init(0xF00D);
    const random = rng.random();

    for (0..512) |_| {
        if (random.boolean() and count < live.len) {
            const order = random.uintAtMost(u8, 3);
            const allocation = pages.alloc(order) catch continue;
            const range = allocation.range();
            const offset: usize = @intCast((range.base.raw() - origin.raw()) >> Page.shift);
            const size: usize = @intCast(range.count.raw());
            for (allocated[offset..][0..size]) |bit| {
                try testing.expect(!bit);
            }
            @memset(allocated[offset..][0..size], true);
            for (&live) |*slot| {
                if (slot.* == null) {
                    slot.* = allocation;
                    count += 1;
                    break;
                }
            }
        } else if (count > 0) {
            var chosen: ?usize = null;
            for (live, 0..) |slot, i| {
                if (slot != null) {
                    if (chosen == null or random.boolean()) {
                        chosen = i;
                    }
                }
            }
            const index = chosen.?;
            const allocation = live[index].?;
            const range = allocation.range();
            live[index] = null;
            count -= 1;
            const offset: usize = @intCast((range.base.raw() - origin.raw()) >> Page.shift);
            const size: usize = @intCast(range.count.raw());
            for (allocated[offset..][0..size]) |bit| {
                try testing.expect(bit);
            }
            @memset(allocated[offset..][0..size], false);
            try pages.free(allocation);
        }

        var remaining: u64 = 0;
        for (allocated) |bit| {
            if (!bit) {
                remaining += 1;
            }
        }
        try testing.expectEqual(remaining, pages.remaining());
        try testing.expect(pages.isValid());
    }
}
