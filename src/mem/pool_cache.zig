//! Multi-region typed object cache over `Pool.Bounded`. Spec:
//! docs/specs/mem/pool-cache.md.

const std = @import("std");

const alignment = @import("alignment.zig");
const debug = @import("../core/debug.zig");
const power_of_two = @import("../bits/power_of_two.zig");
const pool = @import("pool.zig");

fn requireRuntimeValue(comptime T: type) void {
    if (@sizeOf(T) == 0) @compileError("pool cache element type must have nonzero size");
}

fn requireRegionSource(comptime RegionSource: type, comptime Header: type, comptime Slot: type) void {
    if (!@hasDecl(RegionSource, "region_bytes")) {
        @compileError("PoolCache requires RegionSource with pub const region_bytes: usize");
    }
    if (!@hasDecl(RegionSource, "region_align")) {
        @compileError("PoolCache requires RegionSource with pub const region_align: usize");
    }
    if (!@hasDecl(RegionSource, "Error")) {
        @compileError("PoolCache requires RegionSource with pub const Error: type");
    }
    if (!@hasDecl(RegionSource, "acquire")) {
        @compileError("PoolCache requires RegionSource with pub fn acquire");
    }
    if (!@hasDecl(RegionSource, "release")) {
        @compileError("PoolCache requires RegionSource with pub fn release");
    }

    const region_bytes: usize = RegionSource.region_bytes;
    const region_align: usize = RegionSource.region_align;

    if (region_bytes == 0) @compileError("PoolCache RegionSource.region_bytes must be non-zero");
    if (region_align == 0) @compileError("PoolCache RegionSource.region_align must be non-zero");
    if (!power_of_two.isPowerOfTwo(usize, region_align)) {
        @compileError("PoolCache RegionSource.region_align must be a power of two");
    }
    if ((region_bytes % region_align) != 0) {
        @compileError("PoolCache RegionSource.region_bytes must be a multiple of region_align");
    }
    if (region_align < @alignOf(Header)) {
        @compileError("PoolCache RegionSource.region_align is smaller than RegionHeader alignment");
    }

    const header_end: usize = @sizeOf(Header);
    const slot_start: usize = alignment.alignUp(usize, header_end, @alignOf(Slot)) catch |err| {
        @compileError("PoolCache slot start alignment overflowed: " ++ @errorName(err));
    };
    if (slot_start >= region_bytes) {
        @compileError("PoolCache region is too small to hold RegionHeader + one Slot");
    }
    if ((region_bytes - slot_start) < @sizeOf(Slot)) {
        @compileError("PoolCache region is too small to hold RegionHeader + one Slot");
    }
}

/// Multi-region typed cache. `T` is the object type; `RegionSource`
/// supplies fixed-size aligned regions on `refill` and takes them back
/// on `drain`. `acquire` never calls the region source.
pub fn PoolCache(comptime T: type, comptime RegionSource: type) type {
    comptime requireRuntimeValue(T);
    const InnerPool = pool.Pool.Bounded(T);
    return struct {
        source: *RegionSource,
        empty_head: ?*RegionHeader = null,
        partial_head: ?*RegionHeader = null,
        full_head: ?*RegionHeader = null,
        region_count: usize = 0,
        live_count: usize = 0,

        const Self = @This();

        /// Per-slot storage type shared with the inner `Pool.Bounded(T)`.
        pub const Slot = InnerPool.Slot;

        /// Per-region intrusive metadata. Lives at region offset zero.
        pub const RegionHeader = struct {
            next: ?*RegionHeader,
            list: ListId,
            inner: InnerPool,
            region_ptr: [*]align(region_align) u8,

            const ListId = enum(u8) { empty, partial, full };
        };

        /// `RegionSource.Error || error{OutOfMemory}` — collapses when
        /// the source's error set already contains `OutOfMemory`.
        pub const RefillError = RegionSource.Error || error{OutOfMemory};

        /// Acquire error set. `OutOfMemory` when every held region is
        /// full and no free slot exists.
        pub const Error = error{OutOfMemory};

        /// Number of slots per region. Region layout is `RegionHeader`,
        /// alignment padding, then a contiguous `[slots_per_region]Slot`
        /// array. Derived once at instantiation.
        pub const slots_per_region: usize = @divFloor(RegionSource.region_bytes - slot_start, @sizeOf(Slot));

        const region_bytes: usize = RegionSource.region_bytes;
        const region_align: usize = RegionSource.region_align;
        const slot_start: usize = alignment.alignUp(usize, @sizeOf(RegionHeader), @alignOf(Slot)) catch unreachable;

        comptime {
            requireRegionSource(RegionSource, RegionHeader, Slot);
            if (slots_per_region == 0) {
                @compileError("PoolCache region too small: slots_per_region must be at least 1");
            }
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

        /// Acquire one uninitialized `*T` from any region with free
        /// slots. Never calls `RegionSource.acquire`. Returns
        /// `error.OutOfMemory` when every region is full; state
        /// unchanged.
        pub fn acquire(self: *Self) Error!*T {
            const partial = self.partial_head;
            if (partial) |header| {
                return acquireFromRegion(self, header, .partial);
            }

            const empty = self.empty_head orelse return error.OutOfMemory;
            return acquireFromRegion(self, empty, .empty);
        }

        /// Return `item` to its owning region's pool. Panics under
        /// safety checks if `item` does not belong to this cache.
        pub fn release(self: *Self, item: *T) void {
            const region_ptr = regionPtrFromItem(item);
            const header = headerFromRegionPtr(region_ptr);

            if (debug.checksEnabled(.build_mode)) {
                std.debug.assert(self.ownsHeader(header));
            }

            const pre_live = header.inner.len();
            std.debug.assert(pre_live > 0);
            const was_full = pre_live == slots_per_region;

            header.inner.release(item);
            self.live_count -= 1;

            const post_live = header.inner.len();
            if (post_live == 0) {
                self.moveHeader(header, if (was_full) .full else .partial, .empty);
            } else if (was_full) {
                self.moveHeader(header, .full, .partial);
            }
        }

        /// Acquire one region from the source and install it on the
        /// empty list. Propagates the source's error unchanged.
        pub fn refill(self: *Self) RefillError!void {
            const region = try self.source.acquire();
            const region_base: [*]align(region_align) u8 = @ptrCast(region);
            const header: *RegionHeader = @ptrCast(@alignCast(region_base));

            const slot_bytes: [*]align(@alignOf(Slot)) u8 = @alignCast(region_base + slot_start);
            const slots_ptr: [*]Slot = @ptrCast(slot_bytes);
            const slots = slots_ptr[0..slots_per_region];

            header.* = .{
                .next = null,
                .list = .empty,
                .inner = InnerPool.wrap(slots),
                .region_ptr = region_base,
            };

            pushHead(&self.empty_head, header);
            self.region_count += 1;
        }

        /// Release every fully-empty region back to the source.
        /// Regions on the partial or full list are not touched.
        pub fn drain(self: *Self) void {
            var current = self.empty_head;
            self.empty_head = null;

            while (current) |header| {
                const next = header.next;
                const region_ptr = header.region_ptr;
                const region_array: *align(region_align) [region_bytes]u8 =
                    @ptrCast(@alignCast(region_ptr));
                self.source.release(region_array);
                self.region_count -= 1;
                current = next;
            }
        }

        /// True iff `item` points into a region owned by this cache.
        pub fn contains(self: *const Self, item: *const T) bool {
            const region_ptr = regionPtrFromItem(item);
            const header = headerFromRegionPtr(region_ptr);

            return self.ownsHeader(header);
        }

        pub fn isValid(self: *const Self) bool {
            return checkValid(self);
        }

        pub fn assertValid(self: *const Self) void {
            std.debug.assert(self.isValid());
        }

        fn acquireFromRegion(self: *Self, header: *RegionHeader, from: RegionHeader.ListId) Error!*T {
            const item = header.inner.acquire() catch |err| switch (err) {
                error.OutOfMemory => unreachable, // partial/empty region always has slots
            };

            self.live_count += 1;
            const post_live = header.inner.len();

            if (from == .empty) {
                const dest: RegionHeader.ListId = if (post_live == slots_per_region) .full else .partial;
                self.moveHeader(header, .empty, dest);
            } else if (post_live == slots_per_region) {
                self.moveHeader(header, .partial, .full);
            }

            return item;
        }

        fn moveHeader(
            self: *Self,
            header: *RegionHeader,
            from: RegionHeader.ListId,
            to: RegionHeader.ListId,
        ) void {
            std.debug.assert(header.list == from);
            self.unlinkFromList(header, from);
            pushHead(self.listHead(to), header);
            header.list = to;
        }

        fn listHead(self: *Self, list: RegionHeader.ListId) *?*RegionHeader {
            return switch (list) {
                .empty => &self.empty_head,
                .partial => &self.partial_head,
                .full => &self.full_head,
            };
        }

        fn pushHead(head: *?*RegionHeader, header: *RegionHeader) void {
            header.next = head.*;
            head.* = header;
        }

        fn unlinkFromList(self: *Self, target: *RegionHeader, list: RegionHeader.ListId) void {
            const head = self.listHead(list);
            var prev: ?*RegionHeader = null;
            var current = head.*;
            while (current) |node| {
                if (node == target) {
                    if (prev) |p| {
                        p.next = node.next;
                    } else {
                        head.* = node.next;
                    }
                    node.next = null;
                    return;
                }
                prev = node;
                current = node.next;
            }
            unreachable; // target was not on `list`
        }

        fn ownsHeader(self: *const Self, target: *const RegionHeader) bool {
            const lists = [_]?*RegionHeader{ self.empty_head, self.partial_head, self.full_head };
            for (lists) |list_head| {
                var current = list_head;
                while (current) |node| {
                    if (node == target) return true;
                    current = node.next;
                }
            }
            return false;
        }

        fn regionPtrFromItem(item: anytype) [*]align(region_align) u8 {
            const raw: usize = @intFromPtr(item);
            const mask: usize = ~(region_align - 1);
            const base = raw & mask;
            return @ptrFromInt(base);
        }

        fn headerFromRegionPtr(region_ptr: [*]align(region_align) u8) *RegionHeader {
            return @ptrCast(@alignCast(region_ptr));
        }
    };
}

fn checkValid(self: anytype) bool {
    const Self = @TypeOf(self.*);
    var counted: usize = 0;
    var live: usize = 0;
    const lists = [_]struct {
        head: ?*Self.RegionHeader,
        expected: Self.RegionHeader.ListId,
    }{
        .{ .head = self.empty_head, .expected = .empty },
        .{ .head = self.partial_head, .expected = .partial },
        .{ .head = self.full_head, .expected = .full },
    };

    for (lists) |list| {
        var current = list.head;
        while (current) |header| {
            counted += 1;
            if (header.list != list.expected) return false;
            if (!header.inner.isValid()) return false;

            const inner_len = header.inner.len();
            switch (list.expected) {
                .empty => if (inner_len != 0) return false,
                .partial => if (inner_len == 0 or inner_len == Self.slots_per_region) return false,
                .full => if (inner_len != Self.slots_per_region) return false,
            }

            live += inner_len;
            current = header.next;
        }
    }

    if (counted != self.region_count) return false;
    if (live != self.live_count) return false;

    return true;
}
