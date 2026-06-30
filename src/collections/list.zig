//! Fixed-capacity sequences with initialized-prefix tracking. `Static` owns
//! inline storage; `Bounded` borrows caller-provided storage. See
//! docs/specs/collections/list-static.md and
//! docs/specs/collections/list-bounded.md.

const std = @import("std");

fn requireRuntimeValue(comptime T: type) void {
    if (@sizeOf(T) == 0) @compileError("list element type must have nonzero size");
}

/// Fixed-capacity list family. Both variants preserve insertion order, never
/// allocate, and leave the list unchanged on error.
pub const List = struct {
    /// Inline `[capacity_items]T` storage plus an initialized-prefix count.
    /// `Static(T, 0)` is valid and is both empty and full.
    pub fn Static(comptime T: type, comptime capacity_items: usize) type {
        comptime requireRuntimeValue(T);
        return struct {
            buffer: [capacity_items]T = undefined,
            count: usize = 0,

            const Self = @This();

            /// `Full`: append/insert at capacity.
            /// `OutOfBounds`: index access at or past `count`, or insert at
            ///   `index > count`.
            pub const Error = error{ Full, OutOfBounds };

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

            /// Mutable slice over the initialized prefix.
            pub fn asSlice(self: *Self) []T {
                self.assertValid();
                return self.buffer[0..self.count];
            }

            /// Read-only slice over the initialized prefix.
            pub fn asConstSlice(self: *const Self) []const T {
                self.assertValid();
                return self.buffer[0..self.count];
            }

            /// Drop every initialized item without releasing storage.
            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            pub fn append(self: *Self, item: T) error{Full}!void {
                if (self.isFull()) return error.Full;
                self.appendAssumeCapacity(item);
            }

            /// Append `item`; programmer error to call when full.
            pub fn appendAssumeCapacity(self: *Self, item: T) void {
                std.debug.assert(!self.isFull());
                if (capacity_items == 0) unreachable;

                self.buffer[self.count] = item;
                self.count += 1;
            }

            /// Append `items` in order. `error.Full` when the batch does not
            /// fit; the list is unchanged.
            pub fn appendSlice(self: *Self, items: []const T) error{Full}!void {
                if (items.len > self.remaining()) return error.Full;
                @memcpy(self.buffer[self.count..][0..items.len], items);
                self.count += items.len;
            }

            /// Insert `item` at `index`; shifts later elements right.
            /// Checks `index` before capacity.
            pub fn insert(self: *Self, index: usize, item: T) Error!void {
                if (index > self.count) return error.OutOfBounds;
                if (self.isFull()) return error.Full;

                std.mem.copyBackwards(T, self.buffer[index + 1 .. self.count + 1], self.buffer[index..self.count]);
                self.buffer[index] = item;
                self.count += 1;
            }

            /// Remove and return `buffer[index]`, shifting later items left.
            pub fn orderedRemove(self: *Self, index: usize) error{OutOfBounds}!T {
                if (index >= self.count) return error.OutOfBounds;

                const out = self.buffer[index];
                std.mem.copyForwards(T, self.buffer[index .. self.count - 1], self.buffer[index + 1 .. self.count]);
                self.count -= 1;
                return out;
            }

            /// Remove and return `buffer[index]`; moves the last item into
            /// the vacated slot.
            pub fn swapRemove(self: *Self, index: usize) error{OutOfBounds}!T {
                if (index >= self.count) return error.OutOfBounds;

                const out = self.buffer[index];
                self.count -= 1;
                if (index != self.count) self.buffer[index] = self.buffer[self.count];
                return out;
            }

            pub fn pop(self: *Self) ?T {
                if (self.count == 0) return null;
                self.count -= 1;
                return self.buffer[self.count];
            }

            /// Mutable pointer into `buffer[index]`. Invalidated by any
            /// subsequent mutation that shifts elements.
            pub fn at(self: *Self, index: usize) error{OutOfBounds}!*T {
                if (index >= self.count) return error.OutOfBounds;
                return &self.buffer[index];
            }

            pub fn constAt(self: *const Self, index: usize) error{OutOfBounds}!*const T {
                if (index >= self.count) return error.OutOfBounds;
                return &self.buffer[index];
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.count <= item_capacity);
            }
        };
    }

    /// Borrowed `[]T` storage plus an initialized-prefix count. Capacity is
    /// the caller-provided slice length.
    pub fn Bounded(comptime T: type) type {
        comptime requireRuntimeValue(T);
        return struct {
            buffer: []T,
            count: usize = 0,

            const Self = @This();

            /// `Full`: append/insert at capacity.
            /// `OutOfBounds`: index access at or past `count`, or insert at
            ///   `index > count`.
            pub const Error = error{ Full, OutOfBounds };

            /// Wrap `buffer` as backing storage; capacity is `buffer.len`.
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

            /// Mutable slice over the initialized prefix.
            pub fn asSlice(self: *Self) []T {
                self.assertValid();
                return self.buffer[0..self.count];
            }

            /// Read-only slice over the initialized prefix.
            pub fn asConstSlice(self: *const Self) []const T {
                self.assertValid();
                return self.buffer[0..self.count];
            }

            /// Drop every initialized item without releasing storage.
            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            pub fn append(self: *Self, item: T) error{Full}!void {
                if (self.isFull()) return error.Full;
                self.appendAssumeCapacity(item);
            }

            /// Append `item`; programmer error to call when full.
            pub fn appendAssumeCapacity(self: *Self, item: T) void {
                std.debug.assert(!self.isFull());
                if (self.buffer.len == 0) unreachable;

                self.buffer[self.count] = item;
                self.count += 1;
            }

            /// Append `items` in order. `error.Full` when the batch does not
            /// fit; the list is unchanged.
            pub fn appendSlice(self: *Self, items: []const T) error{Full}!void {
                if (items.len > self.remaining()) return error.Full;
                @memcpy(self.buffer[self.count..][0..items.len], items);
                self.count += items.len;
            }

            /// Insert `item` at `index`; shifts later elements right.
            /// Checks `index` before capacity.
            pub fn insert(self: *Self, index: usize, item: T) Error!void {
                if (index > self.count) return error.OutOfBounds;
                if (self.isFull()) return error.Full;

                std.mem.copyBackwards(T, self.buffer[index + 1 .. self.count + 1], self.buffer[index..self.count]);
                self.buffer[index] = item;
                self.count += 1;
            }

            /// Remove and return `buffer[index]`, shifting later items left.
            pub fn orderedRemove(self: *Self, index: usize) error{OutOfBounds}!T {
                if (index >= self.count) return error.OutOfBounds;

                const out = self.buffer[index];
                std.mem.copyForwards(T, self.buffer[index .. self.count - 1], self.buffer[index + 1 .. self.count]);
                self.count -= 1;
                return out;
            }

            /// Remove and return `buffer[index]`; moves the last item into
            /// the vacated slot.
            pub fn swapRemove(self: *Self, index: usize) error{OutOfBounds}!T {
                if (index >= self.count) return error.OutOfBounds;

                const out = self.buffer[index];
                self.count -= 1;
                if (index != self.count) self.buffer[index] = self.buffer[self.count];
                return out;
            }

            pub fn pop(self: *Self) ?T {
                if (self.count == 0) return null;
                self.count -= 1;
                return self.buffer[self.count];
            }

            /// Mutable pointer into `buffer[index]`. Invalidated by any
            /// subsequent mutation that shifts elements.
            pub fn at(self: *Self, index: usize) error{OutOfBounds}!*T {
                if (index >= self.count) return error.OutOfBounds;
                return &self.buffer[index];
            }

            pub fn constAt(self: *const Self, index: usize) error{OutOfBounds}!*const T {
                if (index >= self.count) return error.OutOfBounds;
                return &self.buffer[index];
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.count <= self.buffer.len);
            }
        };
    }
};
