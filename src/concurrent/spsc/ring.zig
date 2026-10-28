//! bounded single-producer/single-consumer ring

const std = @import("std");

const cache = @import("layout").cache;

const AtomicUsize = std.atomic.Value(usize);
const CachePad = cache.CachePad;

pub const Ring = struct {
    pub fn Static(comptime T: type, comptime count: usize) type {
        comptime Impl.requireItem(T);
        comptime Impl.requireCapacity(count);

        return struct {
            slots: [bound]Slot = undefined,
            head: CachePad(AtomicUsize) = .{ .value = AtomicUsize.init(0) },
            tail: CachePad(AtomicUsize) = .{ .value = AtomicUsize.init(0) },

            pub const bound = count;

            const Self = @This();

            pub const Item = T;
            pub const Slot = Impl.Slot(T);
            pub const Error = Impl.Error;

            pub fn init(self: *Self) void {
                self.head.value.store(0, .monotonic);
                self.tail.value.store(0, .monotonic);
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return bound;
            }

            pub fn isEmpty(self: *const Self) bool {
                return Impl.isEmpty(self);
            }

            pub fn tryPushBack(self: *Self, item: Item) Error!void {
                return Impl.tryPushBack(self, item);
            }

            pub fn popFront(self: *Self) ?Item {
                return Impl.popFront(self);
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(self);
            }
        };
    }

    pub fn Bounded(comptime T: type) type {
        comptime Impl.requireItem(T);

        return struct {
            slots: []Slot,
            head: CachePad(AtomicUsize) = .{ .value = AtomicUsize.init(0) },
            tail: CachePad(AtomicUsize) = .{ .value = AtomicUsize.init(0) },

            pub const Item = T;
            pub const Slot = Impl.Slot(T);
            pub const Error = Impl.Error;

            const Self = @This();

            pub fn init(self: *Self, slots: []Slot) void {
                std.debug.assert(slots.len != 0 and std.math.isPowerOfTwo(slots.len));
                self.slots = slots;
                self.head.value.store(0, .monotonic);
                self.tail.value.store(0, .monotonic);
            }

            pub fn capacity(self: *const Self) usize {
                return self.slots.len;
            }

            pub fn isEmpty(self: *const Self) bool {
                return Impl.isEmpty(self);
            }

            pub fn tryPushBack(self: *Self, item: Item) Error!void {
                return Impl.tryPushBack(self, item);
            }

            pub fn popFront(self: *Self) ?Item {
                return Impl.popFront(self);
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(self);
            }
        };
    }
};

const Impl = struct {
    const Error = error{Full};

    fn Slot(comptime T: type) type {
        return struct {
            item: T = undefined,
        };
    }

    fn requireItem(comptime T: type) void {
        if (@sizeOf(T) == 0) {
            @compileError("SPSC ring element type must have nonzero size");
        }
    }

    fn requireCapacity(comptime count: usize) void {
        if (count == 0 or !std.math.isPowerOfTwo(count)) {
            @compileError("SPSC ring capacity must be non-zero and a power of two");
        }
    }

    fn tryPushBack(ring: anytype, item: @TypeOf(ring.*).Item) Error!void {
        const capacity = ring.slots.len;
        const observed_tail = ring.tail.value.load(.monotonic);
        const observed_head = ring.head.value.load(.acquire);

        if (observed_tail -% observed_head >= capacity) {
            return error.Full;
        }

        ring.slots[observed_tail & (capacity - 1)].item = item;
        ring.tail.value.store(observed_tail +% 1, .release);
    }

    fn popFront(ring: anytype) ?@TypeOf(ring.*).Item {
        const observed_head = ring.head.value.load(.monotonic);
        const observed_tail = ring.tail.value.load(.acquire);

        if (observed_tail == observed_head) {
            return null;
        }

        const item = ring.slots[observed_head & (ring.slots.len - 1)].item;
        ring.head.value.store(observed_head +% 1, .release);
        return item;
    }

    fn isEmpty(ring: anytype) bool {
        const observed_head = ring.head.value.load(.monotonic);
        const observed_tail = ring.tail.value.load(.acquire);
        return observed_head == observed_tail;
    }

    fn isValid(ring: anytype) bool {
        const capacity = ring.slots.len;
        if (capacity == 0 or !std.math.isPowerOfTwo(capacity)) {
            return false;
        }

        const head = ring.head.value.load(.monotonic);
        const tail = ring.tail.value.load(.monotonic);
        return tail -% head <= capacity;
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "core FIFO preserves full state and reuses released slots" {
        var ring: Ring.Static(u8, 2) = undefined;
        ring.init();

        const empty = Impl.popFront(&ring);

        try testing.expectEqual(@as(?u8, null), empty);
        try testing.expect(Impl.isEmpty(&ring));
        try testing.expectEqual(@as(usize, 2), ring.capacity());

        try Impl.tryPushBack(&ring, 10);
        try Impl.tryPushBack(&ring, 20);
        const head = ring.head.value.load(.monotonic);
        const tail = ring.tail.value.load(.monotonic);
        const full = Impl.tryPushBack(&ring, 30);
        const full_again = Impl.tryPushBack(&ring, 40);

        try testing.expectError(error.Full, full);
        try testing.expectError(error.Full, full_again);
        try testing.expectEqual(head, ring.head.value.load(.monotonic));
        try testing.expectEqual(tail, ring.tail.value.load(.monotonic));
        try testing.expectEqual(@as(u8, 10), ring.slots[0].item);
        try testing.expectEqual(@as(u8, 20), ring.slots[1].item);
        try testing.expect(!Impl.isEmpty(&ring));
        try testing.expect(Impl.isValid(&ring));

        const first = Impl.popFront(&ring);
        try Impl.tryPushBack(&ring, 30);
        const second = Impl.popFront(&ring);
        const third = Impl.popFront(&ring);
        const drained = Impl.popFront(&ring);

        try testing.expectEqual(@as(?u8, 10), first);
        try testing.expectEqual(@as(?u8, 20), second);
        try testing.expectEqual(@as(?u8, 30), third);
        try testing.expectEqual(@as(?u8, null), drained);
        try testing.expect(Impl.isEmpty(&ring));
        try testing.expect(Impl.isValid(&ring));
    }

    test "core counters wrap through zero at capacity one and four" {
        inline for (.{ 1, 4 }) |count| {
            var ring: Ring.Static(u32, count) = undefined;
            ring.init();
            const start: usize = std.math.maxInt(usize) - 1;
            ring.head.value.store(start, .monotonic);
            ring.tail.value.store(start, .monotonic);

            for (0..8) |cycle| {
                for (0..count) |i| {
                    try Impl.tryPushBack(&ring, @intCast(cycle * count + i));
                }

                const full = Impl.tryPushBack(&ring, 999);

                try testing.expectError(error.Full, full);
                try testing.expect(Impl.isValid(&ring));

                for (0..count) |i| {
                    const item = Impl.popFront(&ring);

                    try testing.expectEqual(@as(?u32, @intCast(cycle * count + i)), item);
                }

                const empty = Impl.popFront(&ring);

                try testing.expectEqual(@as(?u32, null), empty);
                try testing.expect(Impl.isEmpty(&ring));
                try testing.expect(Impl.isValid(&ring));
            }

            try testing.expectEqual(start +% (8 * count), ring.head.value.load(.monotonic));
            try testing.expectEqual(start +% (8 * count), ring.tail.value.load(.monotonic));
        }
    }

    test "borrowed storage retains pointer payload aliases and supports reset" {
        const Bounded = Ring.Bounded(*u32);
        var slots: [2]Bounded.Slot = undefined;

        var ring: Bounded = undefined;
        ring.init(&slots);
        var payload: u32 = 7;

        try ring.tryPushBack(&payload);
        payload = 11;
        const item = ring.popFront().?;
        item.* = 13;

        try testing.expectEqual(&slots[0], &ring.slots[0]);
        try testing.expectEqual(&payload, slots[0].item);
        try testing.expectEqual(&payload, item);
        try testing.expectEqual(@as(u32, 13), payload);
        try testing.expectEqual(@as(usize, 2), ring.capacity());
        try testing.expect(ring.isEmpty());
        try testing.expect(ring.isValid());

        try ring.tryPushBack(&payload);
        ring.init(&slots);
        const empty = ring.popFront();

        try testing.expectEqual(@as(?*u32, null), empty);
        try testing.expect(ring.isEmpty());
        try testing.expect(ring.isValid());
    }

    test "diagnostic rejects invalid storage and wrapped occupancy" {
        const Bounded = Ring.Bounded(u8);
        var slots: [4]Bounded.Slot = undefined;

        inline for (.{ 0, 3 }) |count| {
            var ring: Bounded = undefined;
            ring.init(&slots);
            ring.slots = slots[0..count];

            try testing.expect(!ring.isValid());
        }

        var ring: Bounded = undefined;
        ring.init(&slots);
        ring.head.value.store(std.math.maxInt(usize) - 1, .monotonic);
        ring.tail.value.store(2, .monotonic);

        try testing.expect(ring.isValid());

        ring.tail.value.store(3, .monotonic);

        try testing.expect(!ring.isValid());

        ring.head.value.store(8, .monotonic);
        ring.tail.value.store(7, .monotonic);

        try testing.expect(!ring.isValid());
    }

    test "core matches a bounded FIFO model across fixed random workloads" {
        inline for (.{ 1, 2, 4, 16 }) |count| {
            try runModel(count);
        }
    }

    fn runModel(comptime count: usize) !void {
        var ring: Ring.Static(u32, count) = undefined;
        ring.init();

        var prng = std.Random.DefaultPrng.init(0x5EED_5C51 ^ count);
        const random = prng.random();

        var reference: [count]u32 = undefined;
        var len: usize = 0;
        var next: u32 = 0;

        for (0..4096) |_| {
            if (random.boolean()) {
                const result = Impl.tryPushBack(&ring, next);
                if (len == count) {
                    try testing.expectError(error.Full, result);
                } else {
                    try result;
                    reference[len] = next;
                    len += 1;
                    next += 1;
                }
            } else {
                const item = Impl.popFront(&ring);
                if (len == 0) {
                    try testing.expectEqual(@as(?u32, null), item);
                } else {
                    const expected = reference[0];
                    for (1..len) |i| {
                        reference[i - 1] = reference[i];
                    }
                    len -= 1;

                    try testing.expectEqual(@as(?u32, expected), item);
                }
            }

            try testing.expectEqual(len == 0, Impl.isEmpty(&ring));
            try testing.expect(Impl.isValid(&ring));
        }

        for (reference[0..len]) |expected| {
            const item = Impl.popFront(&ring);

            try testing.expectEqual(@as(?u32, expected), item);
        }
        const empty = Impl.popFront(&ring);

        try testing.expectEqual(@as(?u32, null), empty);
        try testing.expect(Impl.isEmpty(&ring));
        try testing.expect(Impl.isValid(&ring));
    }
};
