//! caller-indexed, cache-line-padded storage

const std = @import("std");

const debug = @import("core").debug;

const CachePad = @import("layout").cache.CachePad;

pub const PerCpu = struct {
    pub fn Static(comptime T: type, comptime count: usize) type {
        if (count == 0) {
            @compileError("PerCpu.Static count must be non-zero");
        }

        return struct {
            items: [count]Padded,

            const Self = @This();

            pub const Padded = CachePad(T);
            pub const Error = Impl.Error;

            pub fn init(value: T) Self {
                var self: Self = undefined;
                Impl.fill(T, &self.items, value);
                return self;
            }

            pub fn initFn(comptime make: fn (index: usize) T) Self {
                var self: Self = undefined;
                Impl.fillFn(T, &self.items, make);
                return self;
            }

            /// callback pointers must not outlive the call; storage is returned by value
            pub fn initEach(comptime fill: fn (index: usize, slot: *T) void) Self {
                var self: Self = undefined;
                Impl.fillEach(T, &self.items, fill);
                return self;
            }

            /// each payload must be written before reading
            pub fn initUndefined() Self {
                return undefined;
            }

            pub fn capacity(_: *const Self) usize {
                return count;
            }

            pub fn get(self: *const Self, index: usize) *const T {
                if (debug.checksEnabled()) {
                    std.debug.assert(index < count);
                }
                return &self.items[index].value;
            }

            pub fn getMut(self: *Self, index: usize) *T {
                if (debug.checksEnabled()) {
                    std.debug.assert(index < count);
                }
                return &self.items[index].value;
            }

            pub fn at(self: *const Self, index: usize) Error!*const T {
                if (index >= count) {
                    return error.OutOfBounds;
                }
                return &self.items[index].value;
            }

            pub fn atMut(self: *Self, index: usize) Error!*T {
                if (index >= count) {
                    return error.OutOfBounds;
                }
                return &self.items[index].value;
            }

            pub fn slots(self: *const Self) []const Padded {
                return &self.items;
            }

            pub fn slotsMut(self: *Self) []Padded {
                return &self.items;
            }
        };
    }

    pub fn Bounded(comptime T: type) type {
        return struct {
            items: []Padded,

            const Self = @This();

            pub const Padded = CachePad(T);
            pub const Error = Impl.Error;

            pub fn wrap(items: []Padded, value: T) Self {
                Impl.fill(T, items, value);
                return .{ .items = items };
            }

            pub fn wrapFn(items: []Padded, comptime make: fn (index: usize) T) Self {
                Impl.fillFn(T, items, make);
                return .{ .items = items };
            }

            pub fn wrapEach(items: []Padded, comptime fill: fn (index: usize, slot: *T) void) Self {
                Impl.fillEach(T, items, fill);
                return .{ .items = items };
            }

            /// each payload must be written before reading
            pub fn wrapUndefined(items: []Padded) Self {
                return .{ .items = items };
            }

            pub fn capacity(self: *const Self) usize {
                return self.items.len;
            }

            pub fn get(self: *const Self, index: usize) *const T {
                if (debug.checksEnabled()) {
                    std.debug.assert(index < self.items.len);
                }
                return &self.items[index].value;
            }

            pub fn getMut(self: *Self, index: usize) *T {
                if (debug.checksEnabled()) {
                    std.debug.assert(index < self.items.len);
                }
                return &self.items[index].value;
            }

            pub fn at(self: *const Self, index: usize) Error!*const T {
                if (index >= self.items.len) {
                    return error.OutOfBounds;
                }
                return &self.items[index].value;
            }

            pub fn atMut(self: *Self, index: usize) Error!*T {
                if (index >= self.items.len) {
                    return error.OutOfBounds;
                }
                return &self.items[index].value;
            }

            pub fn slots(self: *const Self) []const Padded {
                return self.items;
            }

            pub fn slotsMut(self: *Self) []Padded {
                return self.items;
            }
        };
    }
};

const Impl = struct {
    const Error = error{OutOfBounds};

    fn fill(comptime T: type, items: []CachePad(T), value: T) void {
        for (items) |*slot| {
            slot.value = value;
        }
    }

    fn fillFn(comptime T: type, items: []CachePad(T), comptime make: fn (index: usize) T) void {
        for (items, 0..) |*slot, index| {
            slot.value = make(index);
        }
    }

    fn fillEach(comptime T: type, items: []CachePad(T), comptime initialize: fn (index: usize, slot: *T) void) void {
        for (items, 0..) |*slot, index| {
            initialize(index, &slot.value);
        }
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "fill changes only the supplied payloads" {
        var items: [5]CachePad(u64) = undefined;
        Impl.fill(u64, &items, 99);
        Impl.fill(u64, items[1..4], 17);

        for (items, 0..) |slot, index| {
            const expected: u64 = switch (index) {
                0, 4 => 99,
                else => 17,
            };

            try testing.expectEqual(expected, slot.value);
        }
    }

    test "callbacks initialize once per slot in index order" {
        const Callbacks = struct {
            var next: usize = 0;

            fn make(index: usize) u64 {
                std.debug.assert(index == next);
                next += 1;
                return @intCast(3 * index + 1);
            }

            fn fill(index: usize, value: *u64) void {
                value.* = make(index);
            }
        };

        var items: [4]CachePad(u64) = undefined;
        Callbacks.next = 0;
        Impl.fillFn(u64, &items, Callbacks.make);

        try testing.expectEqual(items.len, Callbacks.next);
        for (items, 0..) |slot, index| {
            try testing.expectEqual(@as(u64, @intCast(3 * index + 1)), slot.value);
        }

        Callbacks.next = 0;
        const borrowed = PerCpu.Bounded(u64).wrapEach(&items, Callbacks.fill);

        try testing.expectEqual(items.len, Callbacks.next);
        for (0..borrowed.capacity()) |index| {
            try testing.expectEqual(@as(u64, @intCast(3 * index + 1)), borrowed.get(index).*);
        }
    }

    test "static pointer access and padded views share the same payloads" {
        var values = PerCpu.Static(u64, 3).init(10);
        const read: *const @TypeOf(values) = &values;
        const first = read.get(0);
        const last = try values.atMut(2);

        values.getMut(0).* = 31;
        last.* = 47;
        values.slotsMut()[1].value = 59;

        try testing.expectEqual(@as(u64, 31), first.*);
        try testing.expectEqual(@as(u64, 59), (try read.at(1)).*);
        try testing.expectEqual(@as(u64, 47), read.slots()[2].value);
        try testing.expectError(error.OutOfBounds, read.at(3));
        try testing.expectError(error.OutOfBounds, values.atMut(3));
    }

    test "borrowed copies alias payloads and empty storage rejects access" {
        const Bounded = PerCpu.Bounded(u64);

        var items: [2]Bounded.Padded = undefined;
        var writer = Bounded.wrap(&items, 7);
        var reader = writer;

        writer.getMut(1).* = 23;
        reader.slotsMut()[0].value = 41;

        try testing.expectEqual(@as(u64, 23), reader.get(1).*);
        try testing.expectEqual(@as(u64, 41), writer.get(0).*);

        var empty = Bounded.wrap(items[0..0], 99);

        try testing.expectEqual(@as(usize, 0), empty.capacity());
        try testing.expectError(error.OutOfBounds, empty.at(0));
        try testing.expectError(error.OutOfBounds, empty.atMut(0));
        try testing.expectEqual(@as(u64, 41), items[0].value);
    }

    test "undefined initialization permits writing before reading" {
        const Bounded = PerCpu.Bounded(u64);

        var fixed = PerCpu.Static(u64, 2).initUndefined();
        var items: [2]Bounded.Padded = undefined;
        var borrowed = Bounded.wrapUndefined(&items);

        for (0..fixed.capacity()) |index| {
            fixed.getMut(index).* = @intCast(index + 3);
            borrowed.getMut(index).* = @intCast(index + 7);
        }

        try testing.expectEqual(@as(u64, 3), fixed.get(0).*);
        try testing.expectEqual(@as(u64, 4), fixed.get(1).*);
        try testing.expectEqual(@as(u64, 7), borrowed.get(0).*);
        try testing.expectEqual(@as(u64, 8), borrowed.get(1).*);
    }
};
