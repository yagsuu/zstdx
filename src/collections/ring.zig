//! Fixed-capacity FIFO ring buffer. See docs/specs/collections/ring-static.md.

const std = @import("std");

fn requireRuntimeValue(comptime T: type) void {
    if (@sizeOf(T) == 0) @compileError("ring element type must have nonzero size");
}

/// Family of fixed-capacity FIFO rings. The single approved variant
/// `Static(T, N)` owns inline storage; never allocates and never waits.
pub const Ring = struct {
    /// Inline `[capacity_items]T` storage with head index and live count.
    /// `Static(T, 0)` is valid; every `pushBack` returns `error.Full`, and
    /// `pushBackOverwriteOldest` returns the input unchanged.
    pub fn Static(comptime T: type, comptime capacity_items: usize) type {
        comptime requireRuntimeValue(T);
        return struct {
            buffer: [capacity_items]T = undefined,
            head: usize = 0,
            count: usize = 0,

            const Self = @This();

            /// `Full`: `pushBack` at capacity; ring is unchanged.
            pub const Error = error{Full};

            /// Comptime capacity in items.
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

            /// Drop every live item without releasing storage. Leaves `head`
            /// in place; the next `pushBack` enqueues at the current `head`.
            pub fn clearRetainingCapacity(self: *Self) void {
                self.assertValid();
                self.count = 0;
            }

            fn advance(index: usize) usize {
                if (item_capacity == 0) return 0;
                var next = index + 1;
                if (next == item_capacity) next = 0;
                return next;
            }

            fn addWrap(index: usize, amount: usize) usize {
                if (item_capacity == 0) return 0;
                var result = index + amount;
                if (result >= item_capacity) result -= item_capacity;
                return result;
            }

            fn backIndex(self: *const Self) usize {
                return addWrap(self.head, self.count - 1);
            }

            fn nextBackIndex(self: *const Self) usize {
                return addWrap(self.head, self.count);
            }

            pub fn pushBack(self: *Self, item: T) Error!void {
                if (self.isFull()) return error.Full;
                self.pushBackAssumeCapacity(item);
            }

            /// Append `item`; programmer error to call when full.
            pub fn pushBackAssumeCapacity(self: *Self, item: T) void {
                std.debug.assert(!self.isFull());
                if (item_capacity == 0) unreachable;
                const index = self.nextBackIndex();
                self.buffer[index] = item;
                self.count += 1;
            }

            /// Append `item`. When full, evicts the front element and returns
            /// it; otherwise returns `null`. On `Static(T, 0)` returns `item`
            /// unchanged.
            pub fn pushBackOverwriteOldest(self: *Self, item: T) ?T {
                if (item_capacity == 0) return item;
                if (!self.isFull()) {
                    self.pushBackAssumeCapacity(item);
                    return null;
                }
                const out = self.buffer[self.head];
                self.buffer[self.head] = item;
                self.head = advance(self.head);
                return out;
            }

            pub fn popFront(self: *Self) ?T {
                if (self.count == 0) return null;
                const out = self.buffer[self.head];
                self.head = advance(self.head);
                self.count -= 1;
                return out;
            }

            pub fn front(self: *Self) ?*T {
                if (self.count == 0) return null;
                if (item_capacity == 0) return null;
                return &self.buffer[self.head];
            }

            pub fn constFront(self: *const Self) ?*const T {
                if (self.count == 0) return null;
                if (item_capacity == 0) return null;
                return &self.buffer[self.head];
            }

            pub fn back(self: *Self) ?*T {
                if (self.count == 0) return null;
                if (item_capacity == 0) return null;
                return &self.buffer[self.backIndex()];
            }

            pub fn constBack(self: *const Self) ?*const T {
                if (self.count == 0) return null;
                if (item_capacity == 0) return null;
                return &self.buffer[self.backIndex()];
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.count <= item_capacity);
                if (item_capacity > 0) std.debug.assert(self.head < item_capacity);
            }
        };
    }

    /// Borrowed `[]T` storage with head index and live count.
    pub fn Bounded(comptime T: type) type {
        comptime requireRuntimeValue(T);
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

            pub fn clearRetainingCapacity(self: *Self) void {
                self.assertValid();
                self.count = 0;
            }

            fn advance(self: *const Self, index: usize) usize {
                if (self.buffer.len == 0) return 0;
                var next = index + 1;
                if (next == self.buffer.len) next = 0;
                return next;
            }

            fn addWrap(self: *const Self, index: usize, amount: usize) usize {
                if (self.buffer.len == 0) return 0;
                var result = index + amount;
                if (result >= self.buffer.len) result -= self.buffer.len;
                return result;
            }

            fn backIndex(self: *const Self) usize {
                return self.addWrap(self.head, self.count - 1);
            }

            fn nextBackIndex(self: *const Self) usize {
                return self.addWrap(self.head, self.count);
            }

            pub fn pushBack(self: *Self, item: T) Error!void {
                if (self.isFull()) return error.Full;
                self.pushBackAssumeCapacity(item);
            }

            pub fn pushBackAssumeCapacity(self: *Self, item: T) void {
                std.debug.assert(!self.isFull());
                if (self.buffer.len == 0) unreachable;
                const index = self.nextBackIndex();
                self.buffer[index] = item;
                self.count += 1;
            }

            pub fn pushBackOverwriteOldest(self: *Self, item: T) ?T {
                if (self.buffer.len == 0) return item;
                if (!self.isFull()) {
                    self.pushBackAssumeCapacity(item);
                    return null;
                }
                const out = self.buffer[self.head];
                self.buffer[self.head] = item;
                self.head = self.advance(self.head);
                return out;
            }

            pub fn popFront(self: *Self) ?T {
                if (self.count == 0) return null;
                const out = self.buffer[self.head];
                self.head = self.advance(self.head);
                self.count -= 1;
                return out;
            }

            pub fn front(self: *Self) ?*T {
                if (self.count == 0) return null;
                if (self.buffer.len == 0) return null;
                return &self.buffer[self.head];
            }

            pub fn constFront(self: *const Self) ?*const T {
                if (self.count == 0) return null;
                if (self.buffer.len == 0) return null;
                return &self.buffer[self.head];
            }

            pub fn back(self: *Self) ?*T {
                if (self.count == 0) return null;
                if (self.buffer.len == 0) return null;
                return &self.buffer[self.backIndex()];
            }

            pub fn constBack(self: *const Self) ?*const T {
                if (self.count == 0) return null;
                if (self.buffer.len == 0) return null;
                return &self.buffer[self.backIndex()];
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.count <= self.buffer.len);
                if (self.buffer.len > 0) std.debug.assert(self.head < self.buffer.len);
            }
        };
    }
};
