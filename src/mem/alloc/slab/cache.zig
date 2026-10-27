//! multi-region typed object cache.

const std = @import("std");

const debug = @import("core").debug;

const PerCpu = @import("cpu").per_cpu.PerCpu;
const RawSpinLock = @import("sync").raw_spin_lock.RawSpinLock;
const SlabAllocator = @import("allocator.zig").SlabAllocator;

const alignUp = @import("layout").alignment.alignUp;

pub fn SlabCache(comptime T: type, comptime RegionSource: type) type {
    comptime {
        if (@sizeOf(T) == 0) {
            @compileError("slab cache element type must have nonzero size");
        }
    }

    const Layout = RegionLayout(T, RegionSource);
    const Header = Layout.Header;

    return struct {
        source: *RegionSource,
        empty_head: ?*Header = null,
        partial_head: ?*Header = null,
        full_head: ?*Header = null,
        region_count: usize = 0,
        count: usize = 0,
        next_color: usize = 0,

        const Self = @This();

        pub const Slot = Layout.Slot;
        pub const RefillError = RegionSource.Error;
        pub const Error = Impl.Error;

        pub const color_stride = Layout.color_stride;
        pub const color_count = Layout.color_count;
        pub const slots_per_region = Layout.capacity;

        /// local slots require exclusive access; aggregate queries and drain require quiescence
        pub fn PerCpu(comptime cpu_count: usize, comptime local_capacity: usize) type {
            return PerCpuCache(T, RegionSource, Self, cpu_count, local_capacity);
        }

        pub fn init(source: *RegionSource) Self {
            return .{ .source = source };
        }

        pub fn len(self: *const Self) usize {
            return self.count;
        }

        pub fn regionCount(self: *const Self) usize {
            return self.region_count;
        }

        pub fn capacity(self: *const Self) usize {
            return self.region_count * slots_per_region;
        }

        pub fn remaining(self: *const Self) usize {
            return self.capacity() - self.count;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.count == 0;
        }

        pub fn contains(self: *const Self, item: *const T) bool {
            return Impl.hasHeader(self, Header.fromItem(item));
        }

        /// does not acquire a region.
        pub fn acquire(self: *Self) Error!*T {
            return Impl.acquire(self);
        }

        /// `item` must be live and belong to this cache.
        pub fn release(self: *Self, item: *T) void {
            Impl.release(self, item);
        }

        pub fn refill(self: *Self) RefillError!void {
            return Impl.refill(self);
        }

        /// releases empty regions. partial and full regions remain held.
        pub fn drain(self: *Self) void {
            Impl.drain(self);
        }

        pub fn isValid(self: *const Self) bool {
            return Impl.isValid(self);
        }

        const Impl = struct {
            const Error = error{OutOfMemory};
            const Totals = struct {
                regions: usize = 0,
                count: usize = 0,
            };

            fn acquire(cache: *Self) Impl.Error!*T {
                const header = cache.partial_head orelse cache.empty_head orelse return error.OutOfMemory;
                const item = header.pool.acquire() catch unreachable;

                cache.count += 1;
                moveTo(cache, header, header.classify());

                return item;
            }

            fn release(cache: *Self, item: *T) void {
                const header = Header.fromItem(item);

                if (debug.checksEnabled()) {
                    std.debug.assert(hasHeader(cache, header));
                }

                std.debug.assert(header.pool.len() > 0);
                header.pool.release(item);

                cache.count -= 1;
                moveTo(cache, header, header.classify());
            }

            fn refill(cache: *Self) RegionSource.Error!void {
                const region = try cache.source.acquire();
                const header = Header.init(region, cache.next_color);
                cache.next_color = (cache.next_color + 1) % color_count;
                header.link(&cache.empty_head, .empty);
                cache.region_count += 1;
            }

            fn drain(cache: *Self) void {
                while (cache.empty_head) |header| {
                    header.unlink(&cache.empty_head);
                    cache.source.release(@ptrCast(@alignCast(header)));
                    cache.region_count -= 1;
                }
            }

            fn listHead(cache: *Self, occupancy: Header.Occupancy) *?*Header {
                return switch (occupancy) {
                    .empty => &cache.empty_head,
                    .partial => &cache.partial_head,
                    .full => &cache.full_head,
                };
            }

            fn moveTo(cache: *Self, header: *Header, occupancy: Header.Occupancy) void {
                if (header.occupancy == occupancy) {
                    return;
                }
                header.unlink(listHead(cache, header.occupancy));
                header.link(listHead(cache, occupancy), occupancy);
            }

            fn listContains(first: ?*const Header, target: *const Header) bool {
                var current = first;
                while (current) |header| {
                    if (header == target) {
                        return true;
                    }
                    current = header.next;
                }
                return false;
            }

            fn hasHeader(cache: *const Self, header: *const Header) bool {
                return listContains(cache.empty_head, header) or
                    listContains(cache.partial_head, header) or
                    listContains(cache.full_head, header);
            }

            fn validateList(cache: *const Self, first: ?*const Header, occupancy: Header.Occupancy) ?Totals {
                var totals: Totals = .{};
                var previous: ?*const Header = null;
                var current = first;

                while (current) |header| {
                    totals.regions += 1;

                    if (totals.regions > cache.region_count) {
                        return null;
                    }

                    if (header.occupancy != occupancy or header.prev != previous) {
                        return null;
                    }

                    if (header.next) |next| {
                        if (next.prev != header) {
                            return null;
                        }
                    }

                    if (!header.isValid() or header.classify() != occupancy) {
                        return null;
                    }

                    totals.count += header.pool.len();
                    previous = header;
                    current = header.next;
                }

                return totals;
            }

            fn isValid(cache: *const Self) bool {
                const empty = validateList(cache, cache.empty_head, .empty) orelse return false;
                const partial = validateList(cache, cache.partial_head, .partial) orelse return false;
                const full = validateList(cache, cache.full_head, .full) orelse return false;
                return empty.regions + partial.regions + full.regions == cache.region_count and
                    empty.count + partial.count + full.count == cache.count;
            }
        };
    };
}

fn PerCpuCache(
    comptime T: type,
    comptime RegionSource: type,
    comptime Global: type,
    comptime cpu_count: usize,
    comptime local_capacity: usize,
) type {
    comptime {
        if (local_capacity == 0) {
            @compileError("SlabCache.PerCpu local_capacity must be non-zero");
        }
    }

    const Local = Magazine(T, local_capacity);
    const Locals = PerCpu.Static(Local, cpu_count);

    return struct {
        global: Global,
        locals: Locals,
        lock: RawSpinLock = RawSpinLock.init(),

        const Self = @This();

        pub const Error = Global.Error;
        pub const RefillError = Global.RefillError;

        pub fn init(source: *RegionSource) Self {
            return .{
                .global = Global.init(source),
                .locals = Locals.init(.{}),
            };
        }

        pub fn len(self: *const Self) usize {
            return self.global.len() - self.cached();
        }

        pub fn regionCount(self: *const Self) usize {
            return self.global.regionCount();
        }

        pub fn capacity(self: *const Self) usize {
            return self.global.capacity();
        }

        pub fn remaining(self: *const Self) usize {
            return self.capacity() - self.len();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.len() == 0;
        }

        pub fn contains(self: *const Self, item: *const T) bool {
            return self.global.contains(item);
        }

        pub fn acquire(self: *Self, cpu: usize) Error!*T {
            const local = self.locals.getMut(cpu);
            return local.pop() orelse self.acquireGlobal(local);
        }

        pub fn release(self: *Self, cpu: usize, item: *T) void {
            const local = self.locals.getMut(cpu);
            if (local.len == local_capacity) {
                self.flushFull(local);
            }
            local.push(item);
        }

        pub fn refill(self: *Self) RefillError!void {
            self.lock.acquire();
            defer self.lock.release();

            try self.global.refill();
        }

        /// requires quiescent local cpu operations.
        pub fn drain(self: *Self) void {
            self.lock.acquire();
            defer self.lock.release();

            for (self.locals.slotsMut()) |*slot| {
                self.flush(&slot.value);
            }
            self.global.drain();
        }

        pub fn isValid(self: *const Self) bool {
            if (!self.global.isValid()) {
                return false;
            }

            for (self.locals.slots()) |*slot| {
                if (!slot.value.isValid(&self.global)) {
                    return false;
                }
            }

            return true;
        }

        fn acquireGlobal(self: *Self, local: *Local) Error!*T {
            self.lock.acquire();
            defer self.lock.release();

            const item = try self.global.acquire();
            self.fill(local);
            return item;
        }

        fn fill(self: *Self, local: *Local) void {
            while (local.len < local_capacity) {
                const item = self.global.acquire() catch return;
                local.push(item);
            }
        }

        fn flushFull(self: *Self, local: *Local) void {
            self.lock.acquire();
            defer self.lock.release();

            self.flush(local);
        }

        fn cached(self: *const Self) usize {
            var count: usize = 0;
            for (self.locals.slots()) |*slot| {
                count += slot.value.len;
            }
            return count;
        }

        fn flush(self: *Self, local: *Local) void {
            while (local.pop()) |item| {
                self.global.release(item);
            }
        }
    };
}

fn RegionLayout(comptime T: type, comptime RegionSource: type) type {
    const Pool = SlabAllocator.Bounded(T);

    const region_bytes: usize = RegionSource.region_bytes;
    const region_align: usize = RegionSource.region_align;

    return struct {
        comptime {
            requireSource();
            requireAlignment();
        }

        const Slot = Pool.Slot;
        const Header = struct {
            prev: ?*Self = null,
            next: ?*Self = null,
            occupancy: Occupancy,
            pool: Pool,

            const Occupancy = enum(u8) { empty, partial, full };

            const Self = @This();

            fn init(region: *align(region_align) [region_bytes]u8, color: usize) *Self {
                std.debug.assert(color < color_count);

                const bytes: [*]align(region_align) u8 = @ptrCast(region);
                const items: [*]Slot = @ptrCast(@alignCast(bytes + offset + color * color_stride));

                const header: *Self = @ptrCast(region);
                header.* = .{ .occupancy = .empty, .pool = Pool.wrap(items[0..capacity]) };
                return header;
            }

            fn fromItem(item: *const T) *Self {
                return @ptrFromInt(@intFromPtr(item) & ~(region_align - 1));
            }

            fn classify(self: *const Self) Occupancy {
                return switch (self.pool.len()) {
                    0 => .empty,
                    capacity => .full,
                    else => .partial,
                };
            }

            fn isValid(self: *const Self) bool {
                const base = @intFromPtr(self);
                const start = @intFromPtr(self.pool.items.ptr);

                if (base % region_align != 0 or start < base) {
                    return false;
                }

                const item_offset = start - base;
                if (item_offset < offset) {
                    return false;
                }

                const color_offset = item_offset - offset;
                if (color_offset % color_stride != 0 or color_offset / color_stride >= color_count) {
                    return false;
                }

                return self.pool.items.len == capacity and self.pool.isValid();
            }

            fn link(self: *Self, head: *?*Self, occupancy: Occupancy) void {
                self.prev = null;
                self.next = head.*;

                if (head.*) |previous| {
                    previous.prev = self;
                }

                head.* = self;
                self.occupancy = occupancy;
            }

            fn unlink(self: *Self, head: *?*Self) void {
                if (self.prev) |previous| {
                    previous.next = self.next;
                } else {
                    std.debug.assert(head.* == self);
                    head.* = self.next;
                }

                if (self.next) |next| {
                    next.prev = self.prev;
                }

                self.prev = null;
                self.next = null;
            }
        };

        const offset = alignUp(usize, @sizeOf(Header), @alignOf(Slot)) catch {
            @compileError("SlabCache slot alignment overflowed");
        };

        const capacity = blk: {
            if (offset >= region_bytes or region_bytes - offset < @sizeOf(Slot)) {
                @compileError("SlabCache region is too small to hold Header + one Slot");
            }
            break :blk (region_bytes - offset) / @sizeOf(Slot);
        };

        const slack = region_bytes - offset - capacity * @sizeOf(Slot);
        const color_stride = @max(std.atomic.cache_line, @alignOf(Slot));
        const color_count = 1 + slack / color_stride;

        fn requireSource() void {
            if (!@hasDecl(RegionSource, "region_bytes")) {
                @compileError("SlabCache requires RegionSource with pub const region_bytes: usize");
            }

            if (!@hasDecl(RegionSource, "region_align")) {
                @compileError("SlabCache requires RegionSource with pub const region_align: usize");
            }

            if (!@hasDecl(RegionSource, "Error")) {
                @compileError("SlabCache requires RegionSource with pub const Error: type");
            }

            if (!@hasDecl(RegionSource, "acquire")) {
                @compileError("SlabCache requires RegionSource with pub fn acquire");
            }

            if (!@hasDecl(RegionSource, "release")) {
                @compileError("SlabCache requires RegionSource with pub fn release");
            }
        }

        fn requireAlignment() void {
            if (region_bytes == 0) {
                @compileError("SlabCache RegionSource.region_bytes must be non-zero");
            }

            if (region_align == 0) {
                @compileError("SlabCache RegionSource.region_align must be non-zero");
            }

            if (!std.math.isPowerOfTwo(region_align)) {
                @compileError("SlabCache RegionSource.region_align must be a power of two");
            }

            if (region_align < region_bytes) {
                @compileError("SlabCache RegionSource.region_align must be at least region_bytes");
            }

            if (region_align < @alignOf(Header)) {
                @compileError("SlabCache RegionSource.region_align is smaller than Header alignment");
            }
        }
    };
}

fn Magazine(comptime T: type, comptime capacity: usize) type {
    return struct {
        items: [capacity]*T = undefined,
        len: usize = 0,

        const Self = @This();

        fn push(self: *Self, item: *T) void {
            std.debug.assert(self.len < capacity);
            self.items[self.len] = item;
            self.len += 1;
        }

        fn pop(self: *Self) ?*T {
            if (self.len == 0) {
                return null;
            }

            self.len -= 1;
            return self.items[self.len];
        }

        fn isValid(self: *const Self, global: anytype) bool {
            if (self.len > capacity) {
                return false;
            }

            for (self.items[0..self.len]) |item| {
                if (!global.contains(item)) {
                    return false;
                }
            }

            return true;
        }
    };
}

pub const unit = struct {
    const testing = std.testing;

    const Source = struct {
        bytes: [region_bytes]u8 align(region_align) = undefined,
        used: bool = false,

        pub const region_bytes = 16 * std.atomic.cache_line;
        pub const region_align = region_bytes;

        pub const Error = error{OutOfMemory};

        pub fn acquire(self: *@This()) Error!*align(region_align) [region_bytes]u8 {
            if (self.used) {
                return error.OutOfMemory;
            }

            self.used = true;
            return &self.bytes;
        }

        pub fn release(self: *@This(), region: *align(region_align) [region_bytes]u8) void {
            std.debug.assert(region == &self.bytes and self.used);
            self.used = false;
        }
    };

    const Regions = struct {
        bytes: [2][region_bytes]u8 align(region_align) = undefined,
        used: [2]bool = .{ false, false },
        fail: bool = false,

        pub const region_bytes = Source.region_bytes;
        pub const region_align = region_bytes;
        pub const Error = error{Unavailable};

        pub fn acquire(self: *@This()) Error!*align(region_align) [region_bytes]u8 {
            if (!self.fail) {
                for (&self.used, 0..) |*used, index| {
                    if (!used.*) {
                        used.* = true;
                        return @alignCast(&self.bytes[index]);
                    }
                }
            }
            return error.Unavailable;
        }

        pub fn release(self: *@This(), region: *align(region_align) [region_bytes]u8) void {
            for (&self.bytes, &self.used) |*bytes, *used| {
                if (region == bytes) {
                    std.debug.assert(used.*);
                    used.* = false;
                    return;
                }
            }
            unreachable;
        }
    };

    test "region transitions preserve counts and drain only empty regions" {
        const Cache = SlabCache(u64, Regions);
        var source: Regions = .{};
        var cache = Cache.init(&source);
        var items: [Cache.slots_per_region]*u64 = undefined;
        try Cache.Impl.refill(&cache);
        for (&items) |*item| {
            item.* = try Cache.Impl.acquire(&cache);
        }
        try Cache.Impl.refill(&cache);
        const extra = try Cache.Impl.acquire(&cache);

        try testing.expect(cache.empty_head == null);
        try testing.expect(cache.partial_head != null);
        try testing.expect(cache.full_head != null);
        try testing.expectEqual(items.len + 1, cache.len());
        try testing.expect(cache.isValid());

        Cache.Impl.drain(&cache);
        try testing.expectEqual(@as(usize, 2), cache.regionCount());
        Cache.Impl.release(&cache, extra);
        Cache.Impl.drain(&cache);

        try testing.expectEqual(@as(usize, 1), cache.regionCount());
        try testing.expectEqual(items.len, cache.len());
        try testing.expect(cache.isValid());

        for (items) |item| {
            Cache.Impl.release(&cache, item);
        }
        const header = cache.empty_head.?;
        header.next = header;

        try testing.expect(!cache.isValid());

        header.next = null;
        Cache.Impl.drain(&cache);

        try testing.expectEqual(@as(usize, 0), cache.regionCount());
        try testing.expect(cache.isEmpty());
        try testing.expect(cache.isValid());
        try testing.expectEqual([2]bool{ false, false }, source.used);
    }

    test "failed refill preserves color region count and live objects" {
        const Cache = SlabCache([4 * std.atomic.cache_line]u8, Regions);
        var source: Regions = .{};
        var cache = Cache.init(&source);
        try Cache.Impl.refill(&cache);
        const item = try Cache.Impl.acquire(&cache);
        const color = cache.next_color;
        source.fail = true;

        try testing.expectError(error.Unavailable, Cache.Impl.refill(&cache));
        try testing.expectEqual(color, cache.next_color);
        try testing.expectEqual(@as(usize, 1), cache.regionCount());
        try testing.expectEqual(@as(usize, 1), cache.len());
        try testing.expect(cache.contains(item));
        try testing.expect(cache.isValid());

        source.fail = false;
        try Cache.Impl.refill(&cache);

        try testing.expectEqual((color + 1) % Cache.color_count, cache.next_color);
        try testing.expectEqual(@as(usize, 2), cache.regionCount());

        Cache.Impl.release(&cache, item);
        Cache.Impl.drain(&cache);
    }

    test "magazine keeps a bounded LIFO of global objects" {
        const Cache = SlabCache(u64, Regions);
        var source: Regions = .{};
        var cache = Cache.init(&source);
        const other = Cache.init(&source);
        var local: Magazine(u64, 2) = .{};
        try cache.refill();
        const first = try cache.acquire();
        const second = try cache.acquire();
        local.push(first);
        local.push(second);

        try testing.expectEqual(@as(usize, 2), local.len);
        try testing.expect(local.isValid(&cache));
        try testing.expect(!local.isValid(&other));
        try testing.expectEqual(second, local.pop().?);
        try testing.expectEqual(first, local.pop().?);
        try testing.expect(local.pop() == null);
        try testing.expect(local.isValid(&cache));

        local.len = 3;

        try testing.expect(!local.isValid(&cache));

        cache.release(first);
        cache.release(second);
        cache.drain();
    }

    test "per cpu batches fall back and full magazines flush before quiescent drain" {
        const Cache = SlabCache([4 * std.atomic.cache_line]u8, Regions);
        const LocalCache = Cache.PerCpu(2, Cache.slots_per_region);
        var source: Regions = .{};
        var cache = LocalCache.init(&source);

        try testing.expectError(error.OutOfMemory, cache.acquire(0));
        try testing.expectEqual(@as(usize, 0), cache.regionCount());

        try cache.refill();
        const first = try cache.acquire(0);

        try testing.expectEqual(Cache.slots_per_region - 1, cache.locals.getMut(0).len);
        try testing.expectEqual(@as(usize, 1), cache.len());
        try testing.expectError(error.OutOfMemory, cache.acquire(1));
        try testing.expect(cache.isValid());

        try cache.refill();
        const second = try cache.acquire(1);
        cache.release(0, first);
        cache.release(0, second);

        try testing.expectEqual(@as(usize, 1), cache.locals.getMut(0).len);
        try testing.expect(cache.isEmpty());
        try testing.expectEqual(cache.capacity(), cache.remaining());
        try testing.expect(cache.isValid());

        cache.drain();

        try testing.expectEqual(@as(usize, 0), cache.regionCount());
        try testing.expectEqual(@as(usize, 0), cache.cached());
        try testing.expect(cache.isValid());
        try testing.expectEqual([2]bool{ false, false }, source.used);
    }

    test "small slots keep maximum capacity when no color fits in slack" {
        const Layout = RegionLayout(u64, Source);

        var source: Source = .{};
        const region = try source.acquire();
        defer source.release(region);

        const header = Layout.Header.init(region, 0);
        const end = @intFromPtr(header.pool.items.ptr) + header.pool.items.len * @sizeOf(Layout.Slot);
        const limit = @intFromPtr(region) + Source.region_bytes;

        try testing.expectEqual(@as(usize, 1), Layout.color_count);
        try testing.expect(end <= limit);
        try testing.expect(limit - end < @sizeOf(Layout.Slot));
        try testing.expect(header.isValid());
    }

    test "every color preserves maximum capacity alignment bounds and header recovery" {
        const Payload = [4 * std.atomic.cache_line]u8;
        const Layout = RegionLayout(Payload, Source);

        var source: Source = .{};
        const region = try source.acquire();
        defer source.release(region);

        const base = @intFromPtr(region);
        const limit = base + Source.region_bytes;

        try testing.expect(Layout.color_count > 1);

        for (0..Layout.color_count) |color| {
            const header = Layout.Header.init(region, color);
            const start = @intFromPtr(header.pool.items.ptr);
            const end = start + header.pool.capacity() * @sizeOf(Layout.Slot);

            try testing.expectEqual(Layout.capacity, header.pool.capacity());
            try testing.expectEqual(Layout.offset + color * Layout.color_stride, start - base);
            try testing.expectEqual(@as(usize, 0), start % @alignOf(Layout.Slot));
            try testing.expect(end <= limit);

            if (color == 0) {
                try testing.expect(limit - end < @sizeOf(Layout.Slot));
            }

            for (0..Layout.capacity) |_| {
                const item = try header.pool.acquire();
                try testing.expectEqual(header, Layout.Header.fromItem(item));
            }

            try testing.expectError(error.OutOfMemory, header.pool.acquire());
            try testing.expect(header.isValid());
        }
    }
};
