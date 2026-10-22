//! Fixed-capacity sequences with initialized-prefix tracking.
//! `Static` owns inline storage; `Bounded` borrows caller-provided storage.
//! See `docs/specs/collections/list/static.md` and `docs/specs/collections/list/bounded.md`.

const std = @import("std");

pub const List = struct {
    pub fn Static(comptime T: type, comptime capacity_items: usize) type {
        comptime {
            Impl.requireRuntimeValue(T);
            if (capacity_items == 0) {
                @compileError("List.Static capacity_items must be non-zero");
            }
        }

        return struct {
            buffer: [capacity_items]T = undefined,
            count: usize = 0,

            pub const item_capacity = capacity_items;

            const Self = @This();

            pub const Error = error{ Full, OutOfBounds };

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

            pub fn asSlice(self: *const Self) []const T {
                self.assertValid();
                return self.buffer[0..self.count];
            }

            pub fn asSliceMut(self: *Self) []T {
                self.assertValid();
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            pub fn append(self: *Self, item: T) error{Full}!void {
                return Impl.append(T, self.buffer[0..], &self.count, item);
            }

            pub fn appendAssumeCapacity(self: *Self, item: T) void {
                Impl.appendAssumeCapacity(T, self.buffer[0..], &self.count, item);
            }

            pub fn appendSlice(self: *Self, items: []const T) error{Full}!void {
                return Impl.appendSlice(T, self.buffer[0..], &self.count, items);
            }

            pub fn insert(self: *Self, index: usize, item: T) Error!void {
                return Impl.insert(T, self.buffer[0..], &self.count, index, item);
            }

            pub fn orderedRemove(self: *Self, index: usize) error{OutOfBounds}!T {
                return Impl.orderedRemove(T, self.buffer[0..], &self.count, index);
            }

            /// Replaces the removed item with the last live item.
            pub fn swapRemove(self: *Self, index: usize) error{OutOfBounds}!T {
                return Impl.swapRemove(T, self.buffer[0..], &self.count, index);
            }

            pub fn pop(self: *Self) ?T {
                return Impl.pop(T, self.buffer[0..], &self.count);
            }

            /// Insertion and removal can invalidate returned pointers.
            pub fn at(self: *const Self, index: usize) error{OutOfBounds}!*const T {
                return Impl.at(T, self.buffer[0..], self.count, index);
            }

            pub fn atMut(self: *Self, index: usize) error{OutOfBounds}!*T {
                return Impl.atMut(T, self.buffer[0..], self.count, index);
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.count <= item_capacity);
            }
        };
    }

    pub fn Bounded(comptime T: type) type {
        comptime Impl.requireRuntimeValue(T);

        return struct {
            buffer: []T,
            count: usize = 0,

            const Self = @This();

            pub const Error = error{ Full, OutOfBounds };

            pub fn wrap(buffer: []T) Self {
                return .{ .buffer = buffer };
            }

            pub fn len(self: *const Self) usize {
                self.assertValid();
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                self.assertValid();
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

            pub fn asSlice(self: *const Self) []const T {
                self.assertValid();
                return self.buffer[0..self.count];
            }

            pub fn asSliceMut(self: *Self) []T {
                self.assertValid();
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            pub fn append(self: *Self, item: T) error{Full}!void {
                return Impl.append(T, self.buffer[0..], &self.count, item);
            }

            pub fn appendAssumeCapacity(self: *Self, item: T) void {
                Impl.appendAssumeCapacity(T, self.buffer[0..], &self.count, item);
            }

            pub fn appendSlice(self: *Self, items: []const T) error{Full}!void {
                return Impl.appendSlice(T, self.buffer[0..], &self.count, items);
            }

            pub fn insert(self: *Self, index: usize, item: T) Error!void {
                return Impl.insert(T, self.buffer[0..], &self.count, index, item);
            }

            pub fn orderedRemove(self: *Self, index: usize) error{OutOfBounds}!T {
                return Impl.orderedRemove(T, self.buffer[0..], &self.count, index);
            }

            /// Replaces the removed item with the last live item.
            pub fn swapRemove(self: *Self, index: usize) error{OutOfBounds}!T {
                return Impl.swapRemove(T, self.buffer[0..], &self.count, index);
            }

            pub fn pop(self: *Self) ?T {
                return Impl.pop(T, self.buffer[0..], &self.count);
            }

            /// Insertion and removal can invalidate returned pointers.
            pub fn at(self: *const Self, index: usize) error{OutOfBounds}!*const T {
                return Impl.at(T, self.buffer[0..], self.count, index);
            }

            pub fn atMut(self: *Self, index: usize) error{OutOfBounds}!*T {
                return Impl.atMut(T, self.buffer[0..], self.count, index);
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.count <= self.buffer.len);
            }
        };
    }
};

const Impl = struct {
    fn append(comptime T: type, buffer: []T, count: *usize, item: T) error{Full}!void {
        std.debug.assert(count.* <= buffer.len);

        if (count.* == buffer.len) {
            return error.Full;
        }

        appendAssumeCapacity(T, buffer, count, item);
    }

    fn appendAssumeCapacity(comptime T: type, buffer: []T, count: *usize, item: T) void {
        std.debug.assert(count.* <= buffer.len);
        std.debug.assert(count.* < buffer.len);

        if (buffer.len == 0) {
            unreachable;
        }

        buffer[count.*] = item;
        count.* += 1;
        std.debug.assert(count.* <= buffer.len);
    }

    fn appendSlice(comptime T: type, buffer: []T, count: *usize, items: []const T) error{Full}!void {
        std.debug.assert(count.* <= buffer.len);

        if (items.len > buffer.len - count.*) {
            return error.Full;
        }

        @memcpy(buffer[count.*..][0..items.len], items);
        count.* += items.len;
        std.debug.assert(count.* <= buffer.len);
    }

    fn insert(comptime T: type, buffer: []T, count: *usize, index: usize, item: T) error{ Full, OutOfBounds }!void {
        std.debug.assert(count.* <= buffer.len);

        if (index > count.*) {
            return error.OutOfBounds;
        }

        if (count.* == buffer.len) {
            return error.Full;
        }

        std.mem.copyBackwards(T, buffer[index + 1 .. count.* + 1], buffer[index..count.*]);
        buffer[index] = item;
        count.* += 1;

        std.debug.assert(count.* <= buffer.len);
    }

    fn orderedRemove(comptime T: type, buffer: []T, count: *usize, index: usize) error{OutOfBounds}!T {
        std.debug.assert(count.* <= buffer.len);

        if (index >= count.*) {
            return error.OutOfBounds;
        }

        const out = buffer[index];
        std.mem.copyForwards(T, buffer[index .. count.* - 1], buffer[index + 1 .. count.*]);
        count.* -= 1;

        std.debug.assert(count.* <= buffer.len);
        return out;
    }

    fn swapRemove(comptime T: type, buffer: []T, count: *usize, index: usize) error{OutOfBounds}!T {
        std.debug.assert(count.* <= buffer.len);

        if (index >= count.*) {
            return error.OutOfBounds;
        }

        const out = buffer[index];
        count.* -= 1;

        if (index != count.*) {
            buffer[index] = buffer[count.*];
        }

        std.debug.assert(count.* <= buffer.len);
        return out;
    }

    fn pop(comptime T: type, buffer: []T, count: *usize) ?T {
        std.debug.assert(count.* <= buffer.len);

        if (count.* == 0) {
            return null;
        }

        count.* -= 1;
        std.debug.assert(count.* <= buffer.len);
        return buffer[count.*];
    }

    fn at(comptime T: type, buffer: []const T, count: usize, index: usize) error{OutOfBounds}!*const T {
        std.debug.assert(count <= buffer.len);

        if (index >= count) {
            return error.OutOfBounds;
        }

        return &buffer[index];
    }

    fn atMut(comptime T: type, buffer: []T, count: usize, index: usize) error{OutOfBounds}!*T {
        std.debug.assert(count <= buffer.len);

        if (index >= count) {
            return error.OutOfBounds;
        }

        return &buffer[index];
    }

    fn requireRuntimeValue(comptime T: type) void {
        if (@sizeOf(T) == 0) {
            @compileError("list element type must have nonzero size");
        }
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "unit: List core sequence" {
        var buffer: [3]u8 = undefined;
        var count: usize = 0;

        try Impl.append(u8, &buffer, &count, 1);
        try Impl.appendSlice(u8, &buffer, &count, &.{ 2, 3 });

        try testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, buffer[0..count]);
        try testing.expectError(error.Full, Impl.append(u8, &buffer, &count, 4));
        try testing.expectError(error.OutOfBounds, Impl.insert(u8, &buffer, &count, 4, 9));
        try testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, buffer[0..count]);
        try testing.expectEqual(@as(u8, 2), (try Impl.at(u8, &buffer, count, 1)).*);
        try testing.expectEqual(@as(u8, 3), (try Impl.at(u8, &buffer, count, 2)).*);
        try testing.expectEqual(@as(u8, 2), try Impl.orderedRemove(u8, &buffer, &count, 1));
        try testing.expectEqualSlices(u8, &.{ 1, 3 }, buffer[0..count]);

        try Impl.insert(u8, &buffer, &count, 1, 2);

        try testing.expectEqual(@as(u8, 1), try Impl.swapRemove(u8, &buffer, &count, 0));
        try testing.expectEqualSlices(u8, &.{ 3, 2 }, buffer[0..count]);
        try testing.expectEqual(@as(?u8, 2), Impl.pop(u8, &buffer, &count));
        try testing.expectEqual(@as(?u8, 3), Impl.pop(u8, &buffer, &count));
        try testing.expectEqual(@as(?u8, null), Impl.pop(u8, &buffer, &count));
    }

    test "unit: List.Static inline storage" {
        var list = List.Static(u8, 3).init();
        try list.append(1);
        try list.appendSlice(&.{ 2, 3 });
        (try list.atMut(1)).* = 4;

        try testing.expectEqual(@as(usize, 3), list.capacity());
        try testing.expect(list.isFull());
        try testing.expectEqualSlices(u8, &.{ 1, 4, 3 }, list.asSlice());
        try testing.expect(&list.asSliceMut()[0] == &list.buffer[0]);
        list.assertValid();

        list.clearRetainingCapacity();

        try testing.expect(list.isEmpty());
        list.assertValid();
    }

    test "unit: List.Bounded borrowed storage" {
        var buffer = [_]u32{ 10, 20, 30, 40 };
        var list = List.Bounded(u32).wrap(&buffer);

        try testing.expect(list.isEmpty());
        try testing.expectEqual(@as(usize, 4), list.capacity());
        try testing.expectEqualSlices(u32, &.{ 10, 20, 30, 40 }, &buffer);

        try list.appendSlice(&.{ 1, 2 });
        (try list.atMut(1)).* = 3;

        try testing.expectEqualSlices(u32, &.{ 1, 3 }, list.asSlice());
        try testing.expectEqualSlices(u32, &.{ 1, 3, 30, 40 }, &buffer);
        try testing.expect((try list.at(0)) == &buffer[0]);
        list.assertValid();
    }
};
