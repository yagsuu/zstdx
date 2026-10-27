//! fixed-capacity typed object allocator with intrusive free lists.

const std = @import("std");

const debug = @import("core").debug;

pub const SlabAllocator = struct {
    pub fn Static(comptime T: type, comptime count: usize) type {
        comptime Impl.requireRuntimeValue(T);
        comptime {
            if (count == 0) {
                @compileError("SlabAllocator.Static count must be non-zero");
            }
        }

        return struct {
            items: [count]Slot = undefined,
            free: ?*Slot = null,
            index: usize = 0,
            count: usize = 0,

            pub const bound = count;

            const Self = @This();

            pub const Slot = Impl.Slot(T);
            pub const Error = Impl.Error;

            pub fn init() Self {
                return .{};
            }

            pub fn len(self: *const Self) usize {
                return self.count;
            }

            pub fn capacity(_: *const Self) usize {
                return bound;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.count == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.count == bound;
            }

            /// returns uninitialized storage.
            pub fn acquire(self: *Self) Error!*T {
                return Impl.acquire(T, &self.items, &self.free, &self.index, &self.count);
            }

            pub fn release(self: *Self, item: *T) void {
                Impl.release(T, &self.free, &self.count, item);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.free = null;
                self.index = 0;
                self.count = 0;
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(T, &self.items, self.free, self.index, self.count);
            }
        };
    }

    pub fn Bounded(comptime T: type) type {
        comptime Impl.requireRuntimeValue(T);

        return struct {
            items: []Slot,
            free: ?*Slot = null,
            index: usize = 0,
            count: usize = 0,

            const Self = @This();

            pub const Slot = Impl.Slot(T);
            pub const Error = Impl.Error;

            pub fn wrap(items: []Slot) Self {
                return .{ .items = items };
            }

            pub fn len(self: *const Self) usize {
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                return self.items.len;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.count == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.count == self.items.len;
            }

            pub fn acquire(self: *Self) Error!*T {
                return Impl.acquire(T, self.items, &self.free, &self.index, &self.count);
            }

            pub fn release(self: *Self, item: *T) void {
                Impl.release(T, &self.free, &self.count, item);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.free = null;
                self.index = 0;
                self.count = 0;
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(T, self.items, self.free, self.index, self.count);
            }
        };
    }
};

const Impl = struct {
    const Error = error{OutOfMemory};

    fn Slot(comptime T: type) type {
        return union(enum) {
            free: ?*@This(),
            occupied: T,
        };
    }

    fn acquire(
        comptime T: type,
        items: []Slot(T),
        free: *?*Slot(T),
        index: *usize,
        count: *usize,
    ) Error!*T {
        const slot = if (free.*) |slot| blk: {
            free.* = slot.free;
            break :blk slot;
        } else blk: {
            if (index.* >= items.len) {
                return error.OutOfMemory;
            }

            const slot = &items[index.*];
            index.* += 1;
            break :blk slot;
        };

        slot.* = .{ .occupied = undefined };
        count.* += 1;

        const item = &slot.occupied;
        fill(T, item, 0xCD);
        return item;
    }

    fn release(comptime T: type, free: *?*Slot(T), count: *usize, item: *T) void {
        const slot: *Slot(T) = @alignCast(@fieldParentPtr("occupied", item));
        std.debug.assert(slot.* == .occupied);
        std.debug.assert(count.* > 0);

        fill(T, item, 0xFD);
        slot.* = .{ .free = free.* };
        free.* = slot;
        count.* -= 1;
    }

    fn isValid(comptime T: type, items: []const Slot(T), free: ?*Slot(T), index: usize, count: usize) bool {
        if (index > items.len or count > index) {
            return false;
        }

        const free_count = index - count;

        var seen: usize = 0;
        var current = free;
        while (current) |slot| {
            seen += 1;

            if (seen > free_count or !contains(T, items, slot)) {
                return false;
            }

            if (slot.* != .free) {
                return false;
            }

            current = slot.free;
        }

        return seen == free_count;
    }

    fn contains(comptime T: type, items: []const Slot(T), slot: *const Slot(T)) bool {
        if (items.len == 0) {
            return false;
        }

        const address = @intFromPtr(slot);
        const base = @intFromPtr(items.ptr);

        if (address < base) {
            return false;
        }

        const offset = address - base;
        if (offset % @sizeOf(Slot(T)) != 0) {
            return false;
        }

        return @divExact(offset, @sizeOf(Slot(T))) < items.len;
    }

    fn fill(comptime T: type, item: *T, pattern: u8) void {
        if (debug.checksEnabled()) {
            const bytes: [*]u8 = @ptrCast(item);
            @memset(bytes[0..@sizeOf(T)], pattern);
        }
    }

    fn requireRuntimeValue(comptime T: type) void {
        if (@sizeOf(T) == 0) {
            @compileError("slab allocator element type must have nonzero size");
        }
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "Impl exhaustion, nonaliasing and LIFO reuse" {
        var items: [3]Impl.Slot(u64) = undefined;
        var free: ?*Impl.Slot(u64) = null;
        var index: usize = 0;
        var count: usize = 0;

        const a = try Impl.acquire(u64, &items, &free, &index, &count);
        const b = try Impl.acquire(u64, &items, &free, &index, &count);
        const c = try Impl.acquire(u64, &items, &free, &index, &count);
        a.* = 11;
        b.* = 22;
        c.* = 33;

        try testing.expect(a != b and b != c and a != c);
        try testing.expectEqual(@as(u64, 11), a.*);
        try testing.expectEqual(@as(u64, 22), b.*);
        try testing.expectError(error.OutOfMemory, Impl.acquire(u64, &items, &free, &index, &count));
        try testing.expectEqual(@as(usize, 3), count);

        Impl.release(u64, &free, &count, a);
        Impl.release(u64, &free, &count, b);

        try testing.expectEqual(b, try Impl.acquire(u64, &items, &free, &index, &count));
        try testing.expectEqual(a, try Impl.acquire(u64, &items, &free, &index, &count));
        try testing.expectEqual(@as(u64, 33), c.*);
        try testing.expect(Impl.isValid(u64, &items, free, index, count));
    }

    test "Impl rejects invalid counters and free lists" {
        var items = [_]Impl.Slot(u64){ .{ .free = null }, .{ .occupied = 1 } };
        var outside: Impl.Slot(u64) = .{ .free = null };

        try testing.expect(Impl.isValid(u64, &items, &items[0], 2, 1));
        try testing.expect(!Impl.isValid(u64, &items, null, 3, 0));
        try testing.expect(!Impl.isValid(u64, &items, null, 1, 2));
        try testing.expect(!Impl.isValid(u64, &items, null, 2, 1));
        try testing.expect(!Impl.isValid(u64, &items, &outside, 2, 1));
        try testing.expect(!Impl.isValid(u64, &items, &items[1], 2, 1));
        try testing.expect(!Impl.contains(u64, items[0..0], &items[0]));
        try testing.expect(!Impl.contains(u64, items[0..1], &items[1]));

        items[0].free = &items[0];

        try testing.expect(!Impl.isValid(u64, &items, &items[0], 2, 0));
    }

    test "Static clear discards free links and Bounded accepts empty storage" {
        var pool = SlabAllocator.Static(u64, 2).init();
        const first = try pool.acquire();
        _ = try pool.acquire();
        pool.release(first);
        pool.clearRetainingCapacity();

        try testing.expect(pool.isEmpty());
        try testing.expectEqual(pool.capacity(), pool.remaining());
        try testing.expectEqual(first, try pool.acquire());

        _ = try pool.acquire();

        try testing.expect(pool.isFull());
        try testing.expectError(error.OutOfMemory, pool.acquire());
        try testing.expect(pool.isValid());

        var empty = SlabAllocator.Bounded(u64).wrap(&.{});

        try testing.expect(empty.isEmpty() and empty.isFull());
        try testing.expectError(error.OutOfMemory, empty.acquire());
        try testing.expect(empty.isValid());
    }

    test "Impl checked fill stays within payload" {
        const Payload = [64]u8;

        var items: [2]Impl.Slot(Payload) = .{ .{ .occupied = @splat(0x42) }, .{ .occupied = @splat(0x37) } };
        var free: ?*Impl.Slot(Payload) = null;
        var index: usize = 0;
        var count: usize = 0;

        const item = try Impl.acquire(Payload, &items, &free, &index, &count);

        if (debug.checksEnabled()) {
            try testing.expectEqualSlices(u8, &@as(Payload, @splat(0xCD)), item);
        }

        item.* = @splat(0x42);
        Impl.release(Payload, &free, &count, item);

        const raw: [*]const u8 = @ptrCast(item);
        const expected: u8 = if (debug.checksEnabled()) 0xFD else 0x42;

        for (raw[@sizeOf(?*Impl.Slot(Payload))..@sizeOf(Payload)]) |byte| {
            try testing.expectEqual(expected, byte);
        }

        try testing.expectEqualSlices(u8, &@as(Payload, @splat(0x37)), &items[1].occupied);
        try testing.expect(Impl.isValid(Payload, &items, free, index, count));
    }
};
