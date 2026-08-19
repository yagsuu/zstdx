//! Multi-region typed object cache over `SlabAllocator.Bounded`.
//! See `docs/specs/mem/alloc/slab/cache.md`.

const std = @import("std");

const debug = @import("../../../core/debug.zig");
const power_of_two = @import("../../../bits/power_of_two.zig");
const slab_allocator = @import("allocator.zig");

const PerCPU = @import("../../../cpu/per_cpu.zig").PerCPU;
const RawSpinLock = @import("../../../sync/raw_spin_lock.zig").RawSpinLock;

const alignUp = @import("../../align.zig").alignUp;

pub fn SlabCache(comptime T: type, comptime RegionSource: type) type {
    comptime requireRuntimeValue(T);

    const Layout = SlabCacheLayout(T, RegionSource);
    const RegionHeader = Layout.RegionHeader;

    return struct {
        source: *RegionSource,
        empty_head: ?*RegionHeader = null,
        partial_head: ?*RegionHeader = null,
        full_head: ?*RegionHeader = null,
        region_count: usize = 0,
        live_count: usize = 0,
        next_color: usize = 0,

        const Self = @This();

        pub const Slot = Layout.Slot;
        pub const RefillError = RegionSource.Error;
        pub const Error = error{OutOfMemory};

        pub const color_stride = Layout.color_stride;
        pub const color_count = Layout.color_count;
        pub const slots_per_region = Layout.slots_per_region;

        /// `cpu_index` must have one concurrent executor.
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
            return self.ownsHeader(Layout.headerFromItem(item));
        }

        /// Does not acquire a region.
        pub fn acquire(self: *Self) Error!*T {
            const header = try self.nextAvailableHeader();
            const item = header.inner.acquire() catch unreachable;

            self.live_count += 1;
            self.reclassify(header);
            return item;
        }

        /// `item` must be live and belong to this cache.
        pub fn release(self: *Self, item: *T) void {
            const header = Layout.headerFromItem(item);
            self.assertOwnsHeader(header);

            std.debug.assert(header.inner.len() > 0);
            header.inner.release(item);

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

        fn nextAvailableHeader(self: *Self) Error!*RegionHeader {
            return self.partial_head orelse self.empty_head orelse error.OutOfMemory;
        }

        fn addRegion(
            self: *Self,
            region: *align(RegionSource.region_align) [RegionSource.region_bytes]u8,
        ) void {
            const header = Layout.initHeader(region, self.takeNextColor());
            self.linkHead(.empty, header);
            self.region_count += 1;
        }

        fn takeNextColor(self: *Self) usize {
            const color = self.next_color;
            self.next_color = (color + 1) % color_count;
            return color;
        }

        fn releaseEmptyRegion(self: *Self, header: *RegionHeader) void {
            self.unlink(header);
            self.source.release(header.region);
            self.region_count -= 1;
        }

        fn reclassify(self: *Self, header: *RegionHeader) void {
            self.move(header, Layout.occupancy(header));
        }

        fn assertOwnsHeader(self: *const Self, header: *const RegionHeader) void {
            if (debug.checksEnabled(.build_mode)) {
                std.debug.assert(self.ownsHeader(header));
            }
        }

        fn listHead(self: *Self, list: RegionHeader.ListID) *?*RegionHeader {
            return switch (list) {
                .empty => &self.empty_head,
                .partial => &self.partial_head,
                .full => &self.full_head,
            };
        }

        fn linkHead(self: *Self, list: RegionHeader.ListID, header: *RegionHeader) void {
            const head = self.listHead(list);

            header.prev = null;
            header.next = head.*;

            if (head.*) |old_head| {
                old_head.prev = header;
            }

            head.* = header;
            header.list = list;
        }

        fn unlink(self: *Self, header: *RegionHeader) void {
            const head = self.listHead(header.list);

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

        fn move(self: *Self, header: *RegionHeader, destination: RegionHeader.ListID) void {
            if (header.list == destination) return;

            self.unlink(header);
            self.linkHead(destination, header);
        }

        fn listContains(head: ?*RegionHeader, target: *const RegionHeader) bool {
            var current = head;
            while (current) |header| {
                if (header == target) return true;
                current = header.next;
            }
            return false;
        }

        fn ownsHeader(self: *const Self, target: *const RegionHeader) bool {
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
            head: ?*RegionHeader,
            expected: RegionHeader.ListID,
        ) ?ValidationTotals {
            var totals: ValidationTotals = .{};
            var previous: ?*RegionHeader = null;
            var current = head;

            while (current) |header| {
                totals.region_count += 1;
                if (totals.region_count > self.region_count) return null;
                if (!headerIsValid(header, expected, previous)) return null;

                totals.live_count += header.inner.len();
                previous = header;
                current = header.next;
            }

            return totals;
        }

        fn headerIsValid(
            header: *const RegionHeader,
            expected: RegionHeader.ListID,
            previous: ?*const RegionHeader,
        ) bool {
            if (header.list != expected) return false;
            if (header.prev != previous) return false;

            if (header.next) |next| {
                if (next.prev != header) return false;
            }

            return Layout.isHeaderValid(header) and Layout.occupancy(header) == expected;
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
    const LocalSlots = PerCPU.Static(Local, cpu_count);

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
            const local = self.locals.getPtr(cpu_index);
            return local.pop() orelse self.acquireFromGlobal(local);
        }

        /// Flushes a full local cache under the global spin lock.
        pub fn release(self: *Self, cpu_index: usize, item: *T) void {
            const local = self.locals.getPtr(cpu_index);
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
            for (self.locals.slots()) |*slot| {
                self.flushLocal(&slot.value);
            }
        }

        fn cachedCount(self: *const Self) usize {
            var count: usize = 0;
            for (self.locals.slotsConst()) |slot| {
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
            for (self.locals.slotsConst()) |slot| {
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

fn SlabCacheLayout(comptime T: type, comptime RegionSource: type) type {
    const InnerSlabAllocator = slab_allocator.SlabAllocator.Bounded(T);
    const LayoutSlot = InnerSlabAllocator.Slot;

    const region_bytes = RegionSource.region_bytes;
    const region_align = RegionSource.region_align;

    const Header = struct {
        prev: ?*Self = null,
        next: ?*Self = null,
        list: ListID,
        inner: InnerSlabAllocator,
        region: *align(region_align) [region_bytes]u8,
        slot_offset: usize,

        const ListID = enum(u8) { empty, partial, full };

        const Self = @This();

        fn init(
            region: *align(region_align) [region_bytes]u8,
            slots: []LayoutSlot,
            slot_offset: usize,
        ) Self {
            return .{
                .list = .empty,
                .inner = InnerSlabAllocator.wrap(slots),
                .region = region,
                .slot_offset = slot_offset,
            };
        }
    };

    const SlotLayout = struct {
        first_slot_offset: usize,
        color_stride: usize,
        color_count: usize,
        slots_per_region: usize,

        const Self = @This();

        fn init() Self {
            const first_slot_offset = alignUp(usize, @sizeOf(Header), @alignOf(LayoutSlot)) catch unreachable;
            const color_stride = @max(std.atomic.cache_line, @alignOf(LayoutSlot));
            const colored_slots = slotCount(first_slot_offset + color_stride);

            if (colored_slots == 0) {
                return .{
                    .first_slot_offset = first_slot_offset,
                    .color_stride = color_stride,
                    .color_count = 1,
                    .slots_per_region = slotCount(first_slot_offset),
                };
            }

            return .{
                .first_slot_offset = first_slot_offset,
                .color_stride = color_stride,
                .color_count = 2,
                .slots_per_region = colored_slots,
            };
        }

        fn slotCount(slot_offset: usize) usize {
            if (slot_offset >= region_bytes) return 0;
            return @divFloor(region_bytes - slot_offset, @sizeOf(LayoutSlot));
        }

        fn slotOffset(self: Self, color: usize) usize {
            std.debug.assert(color < self.color_count);
            return self.first_slot_offset + color * self.color_stride;
        }
    };

    const slot_layout = SlotLayout.init();

    comptime requireRegionSource(RegionSource, Header, LayoutSlot, slot_layout.slots_per_region);

    return struct {
        pub const Slot = LayoutSlot;
        pub const RegionHeader = Header;

        pub const color_stride = slot_layout.color_stride;
        pub const color_count = slot_layout.color_count;
        pub const slots_per_region = slot_layout.slots_per_region;

        pub fn initHeader(
            region: *align(region_align) [region_bytes]u8,
            color: usize,
        ) *Header {
            const slot_offset = slot_layout.slotOffset(color);
            const header = headerAt(region);
            header.* = Header.init(region, slotsAt(region, slot_offset), slot_offset);
            return header;
        }

        pub fn headerFromItem(item: anytype) *Header {
            const item_addr = @intFromPtr(item);
            const region_addr = item_addr & ~(region_align - 1);
            return @ptrFromInt(region_addr);
        }

        pub fn occupancy(header: *const Header) Header.ListID {
            const live = header.inner.len();
            if (live == 0) return .empty;
            if (live == slot_layout.slots_per_region) return .full;
            return .partial;
        }

        pub fn isHeaderValid(header: *const Header) bool {
            return hasRegionBase(header) and
                hasValidSlotOffset(header) and
                hasExpectedSlotBuffer(header) and
                header.inner.isValid();
        }

        fn headerAt(region: *align(region_align) [region_bytes]u8) *Header {
            const bytes: [*]align(region_align) u8 = @ptrCast(region);
            return @ptrCast(@alignCast(bytes));
        }

        fn slotsAt(
            region: *align(region_align) [region_bytes]u8,
            slot_offset: usize,
        ) []LayoutSlot {
            const bytes: [*]align(region_align) u8 = @ptrCast(region);
            const slot_bytes: [*]align(@alignOf(LayoutSlot)) u8 =
                @alignCast(bytes + slot_offset);
            return @as([*]LayoutSlot, @ptrCast(slot_bytes))[0..slot_layout.slots_per_region];
        }

        fn hasRegionBase(header: *const Header) bool {
            return @intFromPtr(header.region) == @intFromPtr(header) and
                @intFromPtr(header.region) % region_align == 0;
        }

        fn hasValidSlotOffset(header: *const Header) bool {
            if (header.slot_offset < slot_layout.first_slot_offset) return false;

            const color_offset = header.slot_offset - slot_layout.first_slot_offset;
            return color_offset % slot_layout.color_stride == 0 and
                @divExact(color_offset, slot_layout.color_stride) < slot_layout.color_count;
        }

        fn hasExpectedSlotBuffer(header: *const Header) bool {
            return @intFromPtr(header.inner.buffer.ptr) ==
                @intFromPtr(header.region) + header.slot_offset and
                header.inner.buffer.len == slot_layout.slots_per_region;
        }
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

fn requireRegionSource(
    comptime RegionSource: type,
    comptime Header: type,
    comptime Slot: type,
    comptime slots_per_region: usize,
) void {
    requireRegionSourceInterface(RegionSource);
    requireRegionAlignment(RegionSource, Header);
    requireRegionSlotCapacity(RegionSource, Header, Slot, slots_per_region);
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

    if (!power_of_two.isPowerOfTwo(usize, region_align)) {
        @compileError("SlabCache RegionSource.region_align must be a power of two");
    }

    if (region_align < region_bytes) {
        @compileError("SlabCache RegionSource.region_align must be at least region_bytes");
    }

    if (region_align < @alignOf(Header)) {
        @compileError("SlabCache RegionSource.region_align is smaller than RegionHeader alignment");
    }
}

fn requireRegionSlotCapacity(
    comptime RegionSource: type,
    comptime Header: type,
    comptime Slot: type,
    comptime slots_per_region: usize,
) void {
    const region_bytes: usize = RegionSource.region_bytes;
    const slot_start = alignUp(usize, @sizeOf(Header), @alignOf(Slot)) catch |err| {
        @compileError("SlabCache slot start alignment overflowed: " ++ @errorName(err));
    };

    if (slot_start >= region_bytes or (region_bytes - slot_start) < @sizeOf(Slot)) {
        @compileError("SlabCache region is too small to hold RegionHeader + one Slot");
    }

    if (slots_per_region == 0) {
        @compileError("SlabCache region is too small to hold RegionHeader + one colored Slot");
    }
}
