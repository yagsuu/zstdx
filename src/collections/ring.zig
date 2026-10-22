//! Fixed-capacity FIFO ring buffers. See `docs/specs/collections/ring/static.md`
//! and `docs/specs/collections/ring/bounded.md`.

const std = @import("std");

/// `Static` owns inline storage; `Bounded` borrows caller storage. Neither allocates nor waits.
pub const Ring = struct {
    pub fn Static(comptime T: type, comptime capacity_items: usize) type {
        comptime {
            Impl.requireRuntimeValue(T);
            if (capacity_items == 0) {
                @compileError("Ring.Static capacity_items must be non-zero");
            }
        }

        return struct {
            buffer: [capacity_items]T = undefined,
            head: usize = 0,
            count: usize = 0,

            const Self = @This();

            pub const Error = error{Full};

            pub const item_capacity = capacity_items;

            pub fn init() Self {
                return .{};
            }

            pub fn len(self: *const Self) usize {
                self.assertValid();
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return item_capacity;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.len() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.len() == item_capacity;
            }

            pub fn pushBack(self: *Self, item: T) Error!void {
                return Impl.pushBack(T, self.buffer[0..], self.head, &self.count, item);
            }

            pub fn pushBackAssumeCapacity(self: *Self, item: T) void {
                Impl.pushBackAssumeCapacity(T, self.buffer[0..], self.head, &self.count, item);
            }

            /// Returns the evicted oldest item when full; otherwise returns null.
            pub fn pushBackOverwriteOldest(self: *Self, item: T) ?T {
                return Impl.pushBackOverwriteOldest(T, self.buffer[0..], &self.head, &self.count, item);
            }

            pub fn popFront(self: *Self) ?T {
                return Impl.popFront(T, self.buffer[0..], &self.head, &self.count);
            }

            pub fn front(self: *const Self) ?*const T {
                return Impl.front(T, self.buffer[0..], self.head, self.count);
            }

            pub fn frontMut(self: *Self) ?*T {
                return Impl.frontMut(T, self.buffer[0..], self.head, self.count);
            }

            pub fn back(self: *const Self) ?*const T {
                return Impl.back(T, self.buffer[0..], self.head, self.count);
            }

            pub fn backMut(self: *Self) ?*T {
                return Impl.backMut(T, self.buffer[0..], self.head, self.count);
            }

            /// Retains head; the next push enqueues there.
            pub fn clearRetainingCapacity(self: *Self) void {
                self.assertValid();
                self.count = 0;
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertValid(item_capacity, self.head, self.count);
            }
        };
    }

    pub fn Bounded(comptime T: type) type {
        comptime Impl.requireRuntimeValue(T);
        return struct {
            buffer: []T,
            head: usize = 0,
            count: usize = 0,

            const Self = @This();

            pub const Error = error{Full};

            pub fn wrap(buffer: []T) Self {
                return .{ .buffer = buffer };
            }

            pub fn len(self: *const Self) usize {
                self.assertValid();
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                return self.buffer.len;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.len() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.len() == self.capacity();
            }

            pub fn pushBack(self: *Self, item: T) Error!void {
                return Impl.pushBack(T, self.buffer, self.head, &self.count, item);
            }

            pub fn pushBackAssumeCapacity(self: *Self, item: T) void {
                Impl.pushBackAssumeCapacity(T, self.buffer, self.head, &self.count, item);
            }

            /// Returns the evicted oldest item when full, null when not full, or item for zero-capacity storage.
            pub fn pushBackOverwriteOldest(self: *Self, item: T) ?T {
                return Impl.pushBackOverwriteOldest(T, self.buffer, &self.head, &self.count, item);
            }

            pub fn popFront(self: *Self) ?T {
                return Impl.popFront(T, self.buffer, &self.head, &self.count);
            }

            pub fn front(self: *const Self) ?*const T {
                return Impl.front(T, self.buffer, self.head, self.count);
            }

            pub fn frontMut(self: *Self) ?*T {
                return Impl.frontMut(T, self.buffer, self.head, self.count);
            }

            pub fn back(self: *const Self) ?*const T {
                return Impl.back(T, self.buffer, self.head, self.count);
            }

            pub fn backMut(self: *Self) ?*T {
                return Impl.backMut(T, self.buffer, self.head, self.count);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.assertValid();
                self.count = 0;
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertValid(self.buffer.len, self.head, self.count);
            }
        };
    }
};

const Impl = struct {
    fn pushBack(comptime T: type, buffer: []T, head: usize, count: *usize, item: T) error{Full}!void {
        if (count.* == buffer.len) {
            return error.Full;
        }
        pushBackAssumeCapacity(T, buffer, head, count, item);
    }

    fn pushBackAssumeCapacity(comptime T: type, buffer: []T, head: usize, count: *usize, item: T) void {
        assertValid(buffer.len, head, count.*);
        std.debug.assert(count.* < buffer.len);

        buffer[addWrap(buffer.len, head, count.*)] = item;
        count.* += 1;
    }

    fn pushBackOverwriteOldest(comptime T: type, buffer: []T, head: *usize, count: *usize, item: T) ?T {
        if (buffer.len == 0) {
            return item;
        }

        if (count.* < buffer.len) {
            pushBackAssumeCapacity(T, buffer, head.*, count, item);
            return null;
        }

        assertValid(buffer.len, head.*, count.*);

        const out = buffer[head.*];
        buffer[head.*] = item;
        head.* = addWrap(buffer.len, head.*, 1);
        return out;
    }

    fn popFront(comptime T: type, buffer: []T, head: *usize, count: *usize) ?T {
        if (count.* == 0) {
            return null;
        }

        const out = buffer[head.*];
        head.* = addWrap(buffer.len, head.*, 1);
        count.* -= 1;
        return out;
    }

    fn front(comptime T: type, buffer: []const T, head: usize, count: usize) ?*const T {
        if (count == 0 or buffer.len == 0) {
            return null;
        }
        return &buffer[head];
    }

    fn frontMut(comptime T: type, buffer: []T, head: usize, count: usize) ?*T {
        if (count == 0 or buffer.len == 0) {
            return null;
        }
        return &buffer[head];
    }

    fn back(comptime T: type, buffer: []const T, head: usize, count: usize) ?*const T {
        if (count == 0 or buffer.len == 0) {
            return null;
        }
        return &buffer[addWrap(buffer.len, head, count - 1)];
    }

    fn backMut(comptime T: type, buffer: []T, head: usize, count: usize) ?*T {
        if (count == 0 or buffer.len == 0) {
            return null;
        }
        return &buffer[addWrap(buffer.len, head, count - 1)];
    }

    fn assertValid(capacity_items: usize, head: usize, count: usize) void {
        std.debug.assert(count <= capacity_items);
        if (capacity_items > 0) {
            std.debug.assert(head < capacity_items);
        }
    }

    fn requireRuntimeValue(comptime T: type) void {
        if (@sizeOf(T) == 0) {
            @compileError("ring element type must have nonzero size");
        }
    }

    fn addWrap(capacity_items: usize, index: usize, amount: usize) usize {
        if (capacity_items == 0) {
            return 0;
        }

        var result = index + amount;
        if (result >= capacity_items) {
            result -= capacity_items;
        }

        return result;
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "unit: Ring Impl FIFO wraparound and overwrite" {
        var storage: [3]u8 = undefined;
        var head: usize = 0;
        var count: usize = 0;
        try Impl.pushBack(u8, &storage, head, &count, 1);
        try Impl.pushBack(u8, &storage, head, &count, 2);
        Impl.pushBackAssumeCapacity(u8, &storage, head, &count, 3);

        try testing.expectError(error.Full, Impl.pushBack(u8, &storage, head, &count, 4));
        try testing.expectEqual(@as(u8, 1), Impl.front(u8, &storage, head, count).?.*);
        try testing.expectEqual(@as(u8, 3), Impl.back(u8, &storage, head, count).?.*);
        try testing.expectEqual(@as(?u8, 1), Impl.popFront(u8, &storage, &head, &count));

        try Impl.pushBack(u8, &storage, head, &count, 4);

        try testing.expectEqual(@as(?u8, 2), Impl.pushBackOverwriteOldest(u8, &storage, &head, &count, 5));
        try testing.expectEqual(@as(?u8, 3), Impl.popFront(u8, &storage, &head, &count));
        try testing.expectEqual(@as(?u8, 4), Impl.popFront(u8, &storage, &head, &count));
        try testing.expectEqual(@as(?u8, 5), Impl.popFront(u8, &storage, &head, &count));
        try testing.expectEqual(@as(?u8, null), Impl.popFront(u8, &storage, &head, &count));
        Impl.assertValid(storage.len, head, count);
    }

    test "unit: Ring.Bounded clear retains head and storage" {
        var storage: [2]u8 = undefined;
        var ring = Ring.Bounded(u8).wrap(&storage);
        try testing.expectEqual(@as(?u8, null), ring.pushBackOverwriteOldest(10));
        try ring.pushBack(20);
        try testing.expectEqual(@as(?u8, 10), ring.pushBackOverwriteOldest(30));

        ring.clearRetainingCapacity();

        try testing.expectEqual(@as(usize, 1), ring.head);
        try testing.expect(ring.isEmpty());
        try testing.expectEqualSlices(u8, &.{ 30, 20 }, &storage);

        try ring.pushBack(40);

        try testing.expectEqual(@as(u8, 40), storage[1]);
        try testing.expectEqual(@as(?u8, 40), ring.popFront());
        ring.assertValid();
    }

    test "unit: Ring Static uses inline storage" {
        var ring = Ring.Static(u8, 3).init();
        try ring.pushBack(5);
        ring.pushBackAssumeCapacity(9);

        try testing.expectEqual(@as(usize, 2), ring.len());
        try testing.expectEqual(@as(usize, 3), ring.capacity());
        try testing.expectEqual(@as(usize, 1), ring.remaining());
        try testing.expect(!ring.isEmpty());
        try testing.expect(!ring.isFull());
        try testing.expect(ring.frontMut().? == &ring.buffer[0]);
        try testing.expect(ring.backMut().? == &ring.buffer[1]);
        try testing.expectEqual(@as(u8, 5), ring.front().?.*);
        try testing.expectEqual(@as(u8, 9), ring.back().?.*);
        ring.assertValid();
    }

    test "unit: Ring Bounded endpoints alias borrowed storage" {
        var storage: [2]u8 = .{ 21, 22 };
        var ring = Ring.Bounded(u8).wrap(&storage);

        try testing.expectEqualSlices(u8, &.{ 21, 22 }, &storage);
        try testing.expectEqual(@as(usize, 2), ring.capacity());

        try ring.pushBack(5);
        ring.frontMut().?.* = 7;
        try ring.pushBack(9);
        ring.backMut().?.* = 11;

        try testing.expect(ring.front().? == &storage[0]);
        try testing.expect(ring.back().? == &storage[1]);
        try testing.expectEqualSlices(u8, &.{ 7, 11 }, &storage);
        try testing.expectEqual(@as(?u8, 7), ring.popFront());
        try testing.expectEqual(@as(?u8, 11), ring.popFront());
        ring.assertValid();
    }

    test "unit: Ring Bounded zero-length storage is empty and full" {
        var storage: [0]u8 = .{};
        var ring = Ring.Bounded(u8).wrap(&storage);

        try testing.expect(ring.isEmpty());
        try testing.expect(ring.isFull());
        try testing.expectEqual(@as(usize, 0), ring.capacity());
        try testing.expectError(error.Full, ring.pushBack(1));
        try testing.expectEqual(@as(?u8, 1), ring.pushBackOverwriteOldest(1));
        try testing.expectEqual(@as(?u8, null), ring.popFront());
        try testing.expectEqual(@as(?*u8, null), ring.frontMut());
        try testing.expectEqual(@as(?*const u8, null), ring.front());
        try testing.expectEqual(@as(?*u8, null), ring.backMut());
        try testing.expectEqual(@as(?*const u8, null), ring.back());
        ring.assertValid();
    }
};
