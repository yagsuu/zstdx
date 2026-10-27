const std = @import("std");

const alignUp = @import("layout").alignment.alignUp;

pub const Arena = struct {
    pub const Bounded = struct {
        items: []u8,
        index: usize = 0,

        pub const Mark = struct { index: usize };
        pub const Error = Impl.Error.All;
        pub const AllocationError = Impl.Error.Allocation;

        const Self = @This();

        pub fn wrap(items: []u8) Self {
            return .{ .items = items };
        }

        pub fn capacity(self: *const Self) usize {
            return self.items.len;
        }

        pub fn used(self: *const Self) usize {
            return self.index;
        }

        pub fn remaining(self: *const Self) usize {
            return self.items.len - self.index;
        }

        pub fn remainingBytes(self: *const Self) []const u8 {
            return self.items[self.index..];
        }

        pub fn remainingBytesMut(self: *Self) []u8 {
            return self.items[self.index..];
        }

        pub fn allocBytes(self: *Self, len: usize) Self.AllocationError![]u8 {
            return Impl.allocBytes(self.items, &self.index, len, 1) catch |err| switch (err) {
                error.InvalidAlignment => unreachable,
                error.OutOfMemory => return error.OutOfMemory,
                error.Overflow => return error.Overflow,
            };
        }

        pub fn allocAlignedBytes(self: *Self, len: usize, alignment: usize) Self.Error![]u8 {
            return Impl.allocBytes(self.items, &self.index, len, alignment);
        }

        pub fn alloc(self: *Self, comptime T: type) Self.AllocationError!*T {
            return Impl.alloc(T, self.items, &self.index);
        }

        pub fn allocSlice(self: *Self, comptime T: type, len: usize) Self.AllocationError![]T {
            return Impl.allocSlice(T, self.items, &self.index, len);
        }

        pub fn allocator(self: *Self) std.mem.Allocator {
            return .{ .ptr = self, .vtable = &Impl.Adapter(Self).vtable };
        }

        pub fn mark(self: *const Self) Mark {
            return .{ .index = self.index };
        }

        /// invalidates allocations after the checkpoint; its index must not exceed the current index.
        pub fn restore(self: *Self, checkpoint: Mark) void {
            std.debug.assert(checkpoint.index <= self.index);
            self.index = checkpoint.index;
        }

        /// invalidates all outstanding allocations.
        pub fn reset(self: *Self) void {
            self.index = 0;
        }

        pub fn isValid(self: *const Self) bool {
            return self.index <= self.items.len;
        }
    };

    /// owns inline storage; do not move the arena while allocations are live.
    pub fn Static(comptime count: usize) type {
        if (count == 0) {
            @compileError("Arena.Static count must be non-zero");
        }
        return struct {
            items: [count]u8 = undefined,
            index: usize = 0,

            pub const Mark = struct { index: usize };
            pub const Error = Impl.Error.All;
            pub const AllocationError = Impl.Error.Allocation;
            pub const bound = count;

            const Self = @This();

            pub fn init() Self {
                return .{};
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return count;
            }

            pub fn used(self: *const Self) usize {
                return self.index;
            }

            pub fn remaining(self: *const Self) usize {
                return count - self.index;
            }

            pub fn remainingBytes(self: *const Self) []const u8 {
                return self.items[self.index..];
            }

            pub fn remainingBytesMut(self: *Self) []u8 {
                return self.items[self.index..];
            }

            pub fn allocBytes(self: *Self, len: usize) Self.AllocationError![]u8 {
                return Impl.allocBytes(&self.items, &self.index, len, 1) catch |err| switch (err) {
                    error.InvalidAlignment => unreachable,
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Overflow => return error.Overflow,
                };
            }

            /// errors and zero-length requests leave the cursor unchanged; alignment is validated first.
            pub fn allocAlignedBytes(self: *Self, len: usize, alignment: usize) Self.Error![]u8 {
                return Impl.allocBytes(&self.items, &self.index, len, alignment);
            }

            pub fn alloc(self: *Self, comptime T: type) Self.AllocationError!*T {
                return Impl.alloc(T, &self.items, &self.index);
            }

            pub fn allocSlice(self: *Self, comptime T: type, len: usize) Self.AllocationError![]T {
                return Impl.allocSlice(T, &self.items, &self.index, len);
            }

            pub fn allocator(self: *Self) std.mem.Allocator {
                return .{ .ptr = self, .vtable = &Impl.Adapter(Self).vtable };
            }

            pub fn mark(self: *const Self) Mark {
                return .{ .index = self.index };
            }

            /// invalidates allocations after the checkpoint; its index must not exceed the current index.
            pub fn restore(self: *Self, checkpoint: Mark) void {
                std.debug.assert(checkpoint.index <= self.index);
                self.index = checkpoint.index;
            }

            /// invalidates all outstanding allocations.
            pub fn reset(self: *Self) void {
                self.index = 0;
            }

            pub fn isValid(self: *const Self) bool {
                return self.index <= count;
            }
        };
    }
};

const Impl = struct {
    const Error = struct {
        const Allocation = error{ OutOfMemory, Overflow };
        const All = Allocation || error{InvalidAlignment};
    };

    fn allocBytes(items: []u8, index: *usize, len: usize, alignment: usize) Error.All![]u8 {
        const absolute = @intFromPtr(items.ptr) + index.*;
        const aligned = try alignUp(usize, absolute, alignment);

        if (len == 0) {
            return items[index.*..index.*];
        }

        const padding = aligned - absolute;
        const start = std.math.add(usize, index.*, padding) catch return error.Overflow;
        const end = std.math.add(usize, start, len) catch return error.Overflow;

        if (end > items.len) {
            return error.OutOfMemory;
        }

        const out = items[start..end];
        index.* = end;
        return out;
    }

    fn alloc(comptime T: type, items: []u8, index: *usize) Error.Allocation!*T {
        if (@sizeOf(T) == 0) {
            @compileError("cannot allocate zero-sized type");
        }

        const bytes = allocBytes(items, index, @sizeOf(T), @alignOf(T)) catch |err| switch (err) {
            error.InvalidAlignment => unreachable,
            error.OutOfMemory => return error.OutOfMemory,
            error.Overflow => return error.Overflow,
        };

        return @ptrCast(@alignCast(bytes.ptr));
    }

    fn allocSlice(comptime T: type, items: []u8, index: *usize, len: usize) Error.Allocation![]T {
        if (@sizeOf(T) == 0) {
            @compileError("cannot allocate zero-sized type");
        }

        const byte_count = std.math.mul(usize, @sizeOf(T), len) catch return error.Overflow;
        if (len == 0) {
            return &[_]T{};
        }

        const bytes = allocBytes(items, index, byte_count, @alignOf(T)) catch |err| switch (err) {
            error.InvalidAlignment => unreachable,
            error.OutOfMemory => return error.OutOfMemory,
            error.Overflow => return error.Overflow,
        };

        const ptr: [*]T = @ptrCast(@alignCast(bytes.ptr));
        return ptr[0..len];
    }

    fn Adapter(comptime A: type) type {
        return struct {
            const vtable: std.mem.Allocator.VTable = .{
                .alloc = allocate,
                .resize = std.mem.Allocator.noResize,
                .remap = std.mem.Allocator.noRemap,
                .free = std.mem.Allocator.noFree,
            };

            fn allocate(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
                _ = ret_addr;
                const self: *A = @ptrCast(@alignCast(ctx));
                const bytes = self.allocAlignedBytes(len, alignment.toByteUnits()) catch return null;
                return bytes.ptr;
            }
        };
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "allocation aligns actual addresses and typed slices" {
        var storage: [128]u8 align(16) = undefined;
        const items = storage[1..];

        var index: usize = 0;
        const bytes = try Impl.allocBytes(items, &index, 3, 8);
        const value = try Impl.alloc(u64, items, &index);
        value.* = 42;

        const values = try Impl.allocSlice(u32, items, &index, 3);
        @memset(values, 7);

        try testing.expectEqual(@as(usize, 0), @intFromPtr(bytes.ptr) % 8);
        try testing.expectEqual(@intFromPtr(values.ptr) + values.len * @sizeOf(u32), @intFromPtr(items.ptr) + index);
        try testing.expectEqual(@as(usize, 0), @intFromPtr(value) % @alignOf(u64));
        try testing.expectEqualSlices(u32, &.{ 7, 7, 7 }, values);
    }

    test "zero requests and errors preserve the cursor" {
        var storage: [32]u8 align(8) = undefined;
        var index: usize = 3;
        const zero = try Impl.allocBytes(&storage, &index, 0, 8);

        try testing.expectEqual(storage[3..3].ptr, zero.ptr);
        try testing.expectEqual(@as(usize, 3), index);
        try testing.expectError(error.InvalidAlignment, Impl.allocBytes(&storage, &index, 0, 0));
        try testing.expectError(error.InvalidAlignment, Impl.allocBytes(&storage, &index, 1, 3));
        try testing.expectError(error.OutOfMemory, Impl.allocBytes(&storage, &index, 64, 1));
        try testing.expectError(error.Overflow, Impl.allocBytes(&storage, &index, std.math.maxInt(usize), 1));
        try testing.expectError(error.Overflow, Impl.allocSlice(u64, &storage, &index, std.math.maxInt(usize)));
        try testing.expectEqual(@as(usize, 0), (try Impl.allocSlice(u64, &storage, &index, 0)).len);
        try testing.expectEqual(@as(usize, 3), index);
    }

    test "borrowed storage supports checkpoints and empty capacity" {
        var storage: [32]u8 = undefined;
        var arena = Arena.Bounded.wrap(&storage);

        const first = try arena.allocBytes(3);
        @memset(first, 9);

        const checkpoint = arena.mark();
        _ = try arena.allocAlignedBytes(4, 8);
        arena.restore(checkpoint);
        arena.remainingBytesMut()[0] = 5;

        const view: *const Arena.Bounded = &arena;

        try testing.expectEqual(@as(usize, 32), view.capacity());
        try testing.expectEqual(@as(usize, 3), view.used());
        try testing.expectEqual(@as(usize, 29), view.remaining());
        try testing.expectEqual(@as(u8, 5), view.remainingBytes()[0]);
        try testing.expectEqualSlices(u8, &.{ 9, 9, 9 }, first);

        arena.reset();
        try testing.expect(arena.isValid());
        try testing.expectEqual(@as(usize, 0), arena.used());

        var empty = Arena.Bounded.wrap(&.{});
        try testing.expectEqual(@as(usize, 0), (try empty.allocBytes(0)).len);
        try testing.expectError(error.OutOfMemory, empty.allocBytes(1));
        try testing.expect(empty.isValid());
    }

    test "inline storage supports checkpoints and const remaining bytes" {
        var arena = Arena.Static(32).init();
        const first = try arena.alloc(u8);
        first.* = 9;

        const checkpoint = arena.mark();
        _ = try arena.allocSlice(u16, 2);
        arena.restore(checkpoint);
        arena.remainingBytesMut()[0] = 5;

        const view: *const @TypeOf(arena) = &arena;
        try testing.expectEqual(@as(usize, 32), @TypeOf(arena).bound);
        try testing.expectEqual(@as(usize, 32), view.capacity());
        try testing.expectEqual(@as(usize, 1), view.used());
        try testing.expectEqual(@as(usize, 31), view.remaining());
        try testing.expectEqual(@as(u8, 5), view.remainingBytes()[0]);
        try testing.expectEqual(@as(u8, 9), first.*);

        arena.reset();
        try testing.expect(arena.isValid());
        try testing.expectEqual(@as(usize, 0), arena.used());
    }
};
