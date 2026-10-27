//! multi-region typed object cache.
//! see `docs/specs/mem/alloc/slab/cache.md`.

const std = @import("std");

const debug = @import("core").debug;

const PerCpu = @import("cpu").per_cpu.PerCpu;
const RawSpinLock = @import("sync").raw_spin_lock.RawSpinLock;
const SlabAllocator = @import("allocator.zig").SlabAllocator;

const alignUp = @import("layout").alignment.alignUp;

pub fn SlabCache(comptime T: type, comptime RegionSource: type) type {
    comptime requireRuntimeValue(T);

    const Layout = RegionLayout(T, RegionSource);
    const Header = Layout.Header;

    return struct {
        source: *RegionSource,
        empty_head: ?*Header = null,
        partial_head: ?*Header = null,
        full_head: ?*Header = null,
        region_count: usize = 0,
        live_count: usize = 0,
        next_color: usize = 0,

        const Self = @This();

        pub const Slot = Layout.Slot;
        pub const RefillError = RegionSource.Error;
        pub const Error = error{OutOfMemory};

        pub const color_stride = Layout.color_stride;
        pub const color_count = Layout.color_count;
        pub const slots_per_region = Layout.capacity;

        pub fn PerCpu(comptime cpu_count: usize, comptime local_capacity: usize) type {
            return SlabCachePerCpu(T, RegionSource, Self, cpu_count, local_capacity);
        }

        pub fn init(source: *RegionSource) Self {
            return .{ .source = source };
        }

        pub fn len(self: *const Self) usize {
            return self.live_count;
        }

        pub fn regionCount(self: *const Self) usize {
            return self.region_count;
        }

        pub fn capacity(self: *const Self) usize {
            return self.region_count * slots_per_region;
        }

        pub fn remaining(self: *const Self) usize {
            return self.capacity() - self.live_count;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.live_count == 0;
        }

        pub fn contains(self: *const Self, item: *const T) bool {
            return self.ownsHeader(Header.fromItem(item));
        }

        /// Does not acquire a region.
        pub fn acquire(self: *Self) Error!*T {
            const header = try self.nextAvailableHeader();
            const item = header.pool.acquire() catch unreachable;

            self.live_count += 1;
            self.reclassify(header);
            return item;
        }

        /// `item` must be live and belong to this cache.
        pub fn release(self: *Self, item: *T) void {
            const header = Header.fromItem(item);
            self.assertOwnsHeader(header);

            std.debug.assert(header.pool.len() > 0);
            header.pool.release(item);

            self.live_count -= 1;
            self.reclassify(header);
        }

        /// Adds one region with the next slot color.
        pub fn refill(self: *Self) RefillError!void {
            const region = try self.source.acquire();
            self.addRegion(region);
        }

        /// Releases empty regions. Partial and full regions remain held.
        pub fn drain(self: *Self) void {
            while (self.empty_head) |header| {
                self.releaseEmptyRegion(header);
            }
        }

        pub fn isValid(self: *const Self) bool {
            return self.checkValid();
        }

        pub fn assertValid(self: *const Self) void {
            std.debug.assert(self.isValid());
        }

        fn nextAvailableHeader(self: *Self) Error!*Header {
            return self.partial_head orelse self.empty_head orelse error.OutOfMemory;
        }

        fn addRegion(
            self: *Self,
            region: *align(RegionSource.region_align) [RegionSource.region_bytes]u8,
        ) void {
            const header = Header.init(region, self.takeNextColor());
            self.linkHead(.empty, header);
            self.region_count += 1;
        }

        fn takeNextColor(self: *Self) usize {
            const color = self.next_color;
            self.next_color = (color + 1) % color_count;
            return color;
        }

        fn releaseEmptyRegion(self: *Self, header: *Header) void {
            self.unlink(header);
            self.source.release(@ptrCast(@alignCast(header)));
            self.region_count -= 1;
        }

        fn reclassify(self: *Self, header: *Header) void {
            self.move(header, header.classify());
        }

        fn assertOwnsHeader(self: *const Self, header: *const Header) void {
            if (debug.checksEnabled()) {
                std.debug.assert(self.ownsHeader(header));
            }
        }

        fn listHead(self: *Self, list: Header.Occupancy) *?*Header {
            return switch (list) {
                .empty => &self.empty_head,
                .partial => &self.partial_head,
                .full => &self.full_head,
            };
        }

        fn linkHead(self: *Self, list: Header.Occupancy, header: *Header) void {
            const head = self.listHead(list);

            header.prev = null;
            header.next = head.*;

            if (head.*) |old_head| {
                old_head.prev = header;
            }

            head.* = header;
            header.occupancy = list;
        }

        fn unlink(self: *Self, header: *Header) void {
            const head = self.listHead(header.occupancy);

            if (header.prev) |prev| {
                prev.next = header.next;
            } else {
                std.debug.assert(head.* == header);
                head.* = header.next;
            }

            if (header.next) |next| {
                next.prev = header.prev;
            }

            header.prev = null;
            header.next = null;
        }

        fn move(self: *Self, header: *Header, destination: Header.Occupancy) void {
            if (header.occupancy == destination) return;

            self.unlink(header);
            self.linkHead(destination, header);
        }

        fn listContains(head: ?*Header, target: *const Header) bool {
            var current = head;
            while (current) |header| {
                if (header == target) return true;
                current = header.next;
            }
            return false;
        }

        fn ownsHeader(self: *const Self, target: *const Header) bool {
            return listContains(self.empty_head, target) or
                listContains(self.partial_head, target) or
                listContains(self.full_head, target);
        }

        fn checkValid(self: *const Self) bool {
            var totals = self.listTotals(self.empty_head, .empty) orelse return false;
            totals.add(self.listTotals(self.partial_head, .partial) orelse return false);
            totals.add(self.listTotals(self.full_head, .full) orelse return false);

            return totals.region_count == self.region_count and totals.live_count == self.live_count;
        }

        const ValidationTotals = struct {
            region_count: usize = 0,
            live_count: usize = 0,

            fn add(self: *ValidationTotals, other: ValidationTotals) void {
                self.region_count += other.region_count;
                self.live_count += other.live_count;
            }
        };

        fn listTotals(
            self: *const Self,
            head: ?*Header,
            expected: Header.Occupancy,
        ) ?ValidationTotals {
            var totals: ValidationTotals = .{};
            var previous: ?*Header = null;
            var current = head;

            while (current) |header| {
                totals.region_count += 1;
                if (totals.region_count > self.region_count) return null;
                if (!headerIsValid(header, expected, previous)) return null;

                totals.live_count += header.pool.len();
                previous = header;
                current = header.next;
            }

            return totals;
        }

        fn headerIsValid(
            header: *const Header,
            expected: Header.Occupancy,
            previous: ?*const Header,
        ) bool {
            if (header.occupancy != expected) return false;
            if (header.prev != previous) return false;

            if (header.next) |next| {
                if (next.prev != header) return false;
            }

            return header.isValid() and header.classify() == expected;
        }
    };
}

fn SlabCachePerCpu(
    comptime T: type,
    comptime RegionSource: type,
    comptime Global: type,
    comptime cpu_count: usize,
    comptime local_capacity: usize,
) type {
    comptime requirePerCpuCapacity(local_capacity);

    const Local = SlabCacheMagazine(T, local_capacity);
    const LocalSlots = PerCpu.Static(Local, cpu_count);

    return struct {
        global: Global,
        locals: LocalSlots,
        lock: RawSpinLock = RawSpinLock.init(),

        const Self = @This();

        pub const Error = Global.Error;
        pub const RefillError = Global.RefillError;

        pub fn init(source: *RegionSource) Self {
            return .{
                .global = Global.init(source),
                .locals = LocalSlots.init(.{}),
            };
        }

        pub fn len(self: *const Self) usize {
            return self.global.len() - self.cachedCount();
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

        /// Uses the local cache before reserving a global batch.
        pub fn acquire(self: *Self, cpu_index: usize) Error!*T {
            const local = self.locals.getMut(cpu_index);
            return local.pop() orelse self.acquireFromGlobal(local);
        }

        /// Flushes a full local cache under the global spin lock.
        pub fn release(self: *Self, cpu_index: usize, item: *T) void {
            const local = self.locals.getMut(cpu_index);
            if (local.len == local_capacity) self.flushFullLocal(local);
            local.push(item);
        }

        pub fn refill(self: *Self) RefillError!void {
            self.lock.acquire();
            defer self.lock.release();

            try self.global.refill();
        }

        /// Requires quiescent local CPU operations.
        pub fn drain(self: *Self) void {
            self.lock.acquire();
            defer self.lock.release();

            self.flushAllLocals();
            self.global.drain();
        }

        pub fn isValid(self: *const Self) bool {
            return self.global.isValid() and self.localsAreValid();
        }

        pub fn assertValid(self: *const Self) void {
            std.debug.assert(self.isValid());
        }

        fn acquireFromGlobal(self: *Self, local: *Local) Error!*T {
            self.lock.acquire();
            defer self.lock.release();

            const item = try self.global.acquire();
            self.reserveLocalBatch(local);
            return item;
        }

        fn reserveLocalBatch(self: *Self, local: *Local) void {
            while (local.len < local_capacity) {
                const item = self.global.acquire() catch return;
                local.push(item);
            }
        }

        fn flushFullLocal(self: *Self, local: *Local) void {
            self.lock.acquire();
            defer self.lock.release();

            self.flushLocal(local);
        }

        fn flushAllLocals(self: *Self) void {
            for (self.locals.slotsMut()) |*slot| {
                self.flushLocal(&slot.value);
            }
        }

        fn cachedCount(self: *const Self) usize {
            var count: usize = 0;
            for (self.locals.slots()) |slot| {
                count += slot.value.len;
            }
            return count;
        }

        fn flushLocal(self: *Self, local: *Local) void {
            while (local.pop()) |item| {
                self.global.release(item);
            }
        }

        fn localsAreValid(self: *const Self) bool {
            for (self.locals.slots()) |slot| {
                if (!self.localIsValid(slot.value)) return false;
            }
            return true;
        }

        fn localIsValid(self: *const Self, local: Local) bool {
            if (local.len > local_capacity) return false;

            for (local.items[0..local.len]) |item| {
                if (!self.global.contains(item)) return false;
            }

            return true;
        }
    };
}

fn RegionLayout(comptime T: type, comptime RegionSource: type) type {
    const Pool = SlabAllocator.Bounded(T);

    const region_bytes: usize = RegionSource.region_bytes;
    const region_align: usize = RegionSource.region_align;

    return struct {
        comptime {
            requireRegionSourceInterface(RegionSource);
            requireRegionAlignment(RegionSource, Header);
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
    };
}

fn SlabCacheMagazine(comptime T: type, comptime capacity: usize) type {
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
            if (self.len == 0) return null;

            self.len -= 1;
            return self.items[self.len];
        }
    };
}

fn requireRuntimeValue(comptime T: type) void {
    if (@sizeOf(T) == 0) @compileError("slab cache element type must have nonzero size");
}

fn requirePerCpuCapacity(comptime local_capacity: usize) void {
    if (local_capacity == 0) {
        @compileError("SlabCache.PerCpu local_capacity must be non-zero");
    }
}

fn requireRegionSourceInterface(comptime RegionSource: type) void {
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

fn requireRegionAlignment(comptime RegionSource: type, comptime Header: type) void {
    const region_bytes: usize = RegionSource.region_bytes;
    const region_align: usize = RegionSource.region_align;

    if (region_bytes == 0) @compileError("SlabCache RegionSource.region_bytes must be non-zero");
    if (region_align == 0) @compileError("SlabCache RegionSource.region_align must be non-zero");

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
