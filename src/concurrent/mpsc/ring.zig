//! bounded multi-producer/single-consumer ring

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

            /// requires exclusive access
            pub fn init(self: *Self) void {
                Impl.initialize(self);
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

            /// requires exclusive access; slots must remain valid and address-stable during ring use
            pub fn init(self: *Self, slots: []Slot) void {
                std.debug.assert(slots.len != 0);
                std.debug.assert(std.math.isPowerOfTwo(slots.len));
                self.slots = slots;
                Impl.initialize(self);
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
    const Error = error{ Full, Contended };

    fn Slot(comptime T: type) type {
        return struct {
            sequence: AtomicUsize = AtomicUsize.init(0),
            item: T = undefined,
        };
    }

    fn requireItem(comptime T: type) void {
        if (@sizeOf(T) == 0) {
            @compileError("MPSC ring element type must have nonzero size");
        }
    }

    fn requireCapacity(comptime count: usize) void {
        if (count == 0 or !std.math.isPowerOfTwo(count)) {
            @compileError("MPSC ring capacity must be non-zero and a power of two");
        }
    }

    fn initialize(ring: anytype) void {
        ring.head.value.store(0, .monotonic);
        ring.tail.value.store(0, .monotonic);

        for (ring.slots[0..]) |*slot| {
            slot.sequence.store(0, .monotonic);
        }
    }

    fn tryPushBack(ring: anytype, item: @TypeOf(ring.*).Item) Error!void {
        const capacity = ring.slots.len;
        const observed_tail = ring.tail.value.load(.monotonic);
        const observed_head = ring.head.value.load(.acquire);

        if (observed_tail -% observed_head >= capacity) {
            return error.Full;
        }

        if (ring.tail.value.cmpxchgStrong(observed_tail, observed_tail +% 1, .monotonic, .monotonic) != null) {
            return error.Contended;
        }

        const slot = &ring.slots[observed_tail & (capacity - 1)];
        slot.item = item;
        slot.sequence.store(observed_tail +% 1, .release);
    }

    fn popFront(ring: anytype) ?@TypeOf(ring.*).Item {
        const observed_head = ring.head.value.load(.monotonic);
        const slot = &ring.slots[observed_head & (ring.slots.len - 1)];

        if (slot.sequence.load(.acquire) != observed_head +% 1) {
            return null;
        }

        const item = slot.item;
        ring.head.value.store(observed_head +% 1, .release);
        return item;
    }

    fn isEmpty(ring: anytype) bool {
        const observed_head = ring.head.value.load(.monotonic);
        const slot = &ring.slots[observed_head & (ring.slots.len - 1)];
        return slot.sequence.load(.acquire) != observed_head +% 1;
    }

    fn isValid(ring: anytype) bool {
        const capacity = ring.slots.len;
        if (capacity == 0) {
            return false;
        }

        if (!std.math.isPowerOfTwo(capacity)) {
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
        try testing.expectEqual(@as(usize, 1), ring.slots[0].sequence.load(.monotonic));
        try testing.expectEqual(@as(usize, 2), ring.slots[1].sequence.load(.monotonic));
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

    test "core counters and publication tickets wrap through zero" {
        inline for (.{ 1, 4 }) |count| {
            var ring: Ring.Static(u32, count) = undefined;
            ring.init();

            const start: usize = std.math.maxInt(usize) - 1;
            ring.head.value.store(start, .monotonic);
            ring.tail.value.store(start, .monotonic);

            for (0..count) |i| {
                const ticket = start +% i;
                ring.slots[ticket & (count - 1)].sequence.store(ticket -% count +% 1, .monotonic);
            }

            for (0..8) |cycle| {
                const before = Impl.popFront(&ring);

                try testing.expectEqual(@as(?u32, null), before);
                try testing.expect(Impl.isEmpty(&ring));

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

    test "core does not bypass a reserved unpublished front" {
        var ring: Ring.Static(u8, 2) = undefined;
        ring.init();
        ring.tail.value.store(1, .monotonic);

        try Impl.tryPushBack(&ring, 20);
        const unpublished = Impl.popFront(&ring);
        const full = Impl.tryPushBack(&ring, 30);

        try testing.expectEqual(@as(?u8, null), unpublished);
        try testing.expect(Impl.isEmpty(&ring));
        try testing.expectEqual(@as(usize, 0), ring.head.value.load(.monotonic));
        try testing.expectError(error.Full, full);
        try testing.expect(Impl.isValid(&ring));

        ring.slots[0].item = 10;
        ring.slots[0].sequence.store(1, .release);
        const published = !Impl.isEmpty(&ring);
        const first = Impl.popFront(&ring);
        const second = Impl.popFront(&ring);
        const drained = Impl.popFront(&ring);

        try testing.expect(published);
        try testing.expectEqual(@as(?u8, 10), first);
        try testing.expectEqual(@as(?u8, 20), second);
        try testing.expectEqual(@as(?u8, null), drained);
        try testing.expect(Impl.isEmpty(&ring));
    }

    test "borrowed storage preserves pointer payload aliases and resets publication" {
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
        try ring.tryPushBack(&payload);
        ring.init(&slots);
        const empty = ring.popFront();

        try testing.expectEqual(@as(?*u32, null), empty);
        try testing.expect(ring.isEmpty());
        try testing.expect(ring.isValid());

        try ring.tryPushBack(&payload);
        const reused = ring.popFront();

        try testing.expectEqual(@as(?*u32, &payload), reused);
        try testing.expect(ring.isEmpty());
    }

    test "core validity rejects invalid storage shape and occupancy" {
        const Bounded = Ring.Bounded(u8);
        var slots: [4]Bounded.Slot = undefined;
        var ring: Bounded = undefined;
        ring.init(&slots);

        inline for (.{ 0, 3 }) |count| {
            ring.slots = slots[0..count];

            try testing.expect(!Impl.isValid(&ring));
        }

        ring.slots = &slots;
        ring.head.value.store(std.math.maxInt(usize), .monotonic);
        ring.tail.value.store(3, .monotonic);

        try testing.expect(Impl.isValid(&ring));

        ring.tail.value.store(4, .monotonic);

        try testing.expect(!Impl.isValid(&ring));

        ring.head.value.store(1, .monotonic);
        ring.tail.value.store(0, .monotonic);

        try testing.expect(!Impl.isValid(&ring));
    }
};
