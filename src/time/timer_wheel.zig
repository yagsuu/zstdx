const std = @import("std");

const debug = @import("core").debug;

const Deadline = @import("deadline.zig").Deadline;
const Instant = @import("monotonic.zig").Instant;

pub const TimerWheel = struct {
    pub const Config = struct {
        tick_ns: u64,
        bucket_count: usize,
    };

    pub fn Static(comptime T: type, comptime count: usize, comptime config: Config) type {
        comptime {
            Impl.requireConfig(config);
            if (count == 0) {
                @compileError("TimerWheel.Static count must be non-zero");
            }
        }

        return struct {
            slots: [count]Slot,
            buckets: [config.bucket_count]Impl.List,
            start: Instant,
            tick: Impl.Tick,
            count: usize,
            free: usize,
            expired: Impl.List,

            pub const bound = count;

            const Self = @This();
            const Slot = Impl.Slot(T);

            pub const Handle = Impl.Handle(Self);
            pub const Entry = Impl.Entry(T);
            pub const Error = Impl.Error;
            pub const RangeError = Impl.RangeError;

            pub fn init(start: Instant) Self {
                var self: Self = undefined;
                self.start = start;
                Impl.initialize(&self);
                return self;
            }

            pub fn len(self: *const Self) usize {
                return self.count;
            }

            pub fn capacity(_: *const Self) usize {
                return bound;
            }

            pub fn remaining(self: *const Self) usize {
                return bound - self.count;
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.count == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.count == bound;
            }

            pub fn origin(self: *const Self) Instant {
                return self.start;
            }

            pub fn cursor(self: *const Self) Instant {
                return self.tick.instant(self.start, config.tick_ns).?;
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                Impl.clear(self);
            }

            pub fn advanceTo(self: *Self, now: Instant) void {
                if (debug.checksEnabled()) {
                    std.debug.assert(now.nanos() >= self.cursor().nanos());
                }
                Impl.advanceTo(self, now, config);
            }

            pub fn insert(self: *Self, deadline: Deadline, item: T) Error!Handle {
                if (self.isFull()) {
                    return error.Full;
                }
                const due = try Impl.quantize(self, deadline, config);
                return Impl.insert(T, self, deadline, item, due);
            }

            pub fn insertAssumeCapacity(self: *Self, deadline: Deadline, item: T) RangeError!Handle {
                if (debug.checksEnabled()) {
                    std.debug.assert(!self.isFull());
                }
                const due = try Impl.quantize(self, deadline, config);
                return Impl.insert(T, self, deadline, item, due);
            }

            pub fn nextWake(self: *const Self) ?Instant {
                return Impl.nextWake(self, config);
            }

            pub fn popExpired(self: *Self) ?Entry {
                return Impl.popExpired(self);
            }

            pub fn remove(self: *Self, handle: Handle) ?Entry {
                return Impl.remove(self, handle);
            }

            pub fn updateDeadline(self: *Self, handle: Handle, deadline: Deadline) RangeError!bool {
                return Impl.updateDeadline(self, handle, deadline, config);
            }

            pub fn contains(self: *const Self, handle: Handle) bool {
                return Impl.resolve(self, handle) != null;
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(self, config);
            }
        };
    }

    pub fn Bounded(comptime T: type, comptime config: Config) type {
        comptime Impl.requireConfig(config);

        return struct {
            slots: []Slot,
            buckets: []Bucket,
            start: Instant,
            tick: Impl.Tick,
            count: usize,
            free: usize,
            expired: Impl.List,

            const Self = @This();

            pub const Slot = Impl.Slot(T);
            pub const Bucket = Impl.List;
            pub const Handle = Impl.Handle(Self);
            pub const Entry = Impl.Entry(T);
            pub const Error = Impl.Error;
            pub const RangeError = Impl.RangeError;

            /// borrows and reinitializes slots and buckets; buckets.len must equal config.bucket_count
            /// storage must remain valid and exclusive to this wheel for its lifetime
            pub fn wrap(slots: []Slot, buckets: []Bucket, start: Instant) Self {
                if (debug.checksEnabled()) {
                    std.debug.assert(buckets.len == config.bucket_count);
                }
                var self: Self = .{
                    .slots = slots,
                    .buckets = buckets,
                    .start = start,
                    .tick = undefined,
                    .count = undefined,
                    .free = undefined,
                    .expired = undefined,
                };
                Impl.initialize(&self);
                return self;
            }

            pub fn len(self: *const Self) usize {
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                return self.slots.len;
            }

            pub fn remaining(self: *const Self) usize {
                return self.slots.len - self.count;
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.count == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.count == self.slots.len;
            }

            pub fn origin(self: *const Self) Instant {
                return self.start;
            }

            pub fn cursor(self: *const Self) Instant {
                return self.tick.instant(self.start, config.tick_ns).?;
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                Impl.clear(self);
            }

            pub fn advanceTo(self: *Self, now: Instant) void {
                if (debug.checksEnabled()) {
                    std.debug.assert(now.nanos() >= self.cursor().nanos());
                }
                Impl.advanceTo(self, now, config);
            }

            pub fn insert(self: *Self, deadline: Deadline, item: T) Error!Handle {
                const due = try Impl.quantize(self, deadline, config);
                if (self.isFull()) {
                    return error.Full;
                }
                return Impl.insert(T, self, deadline, item, due);
            }

            pub fn insertAssumeCapacity(self: *Self, deadline: Deadline, item: T) RangeError!Handle {
                const due = try Impl.quantize(self, deadline, config);
                if (debug.checksEnabled()) {
                    std.debug.assert(!self.isFull());
                }
                return Impl.insert(T, self, deadline, item, due);
            }

            pub fn nextWake(self: *const Self) ?Instant {
                return Impl.nextWake(self, config);
            }

            pub fn popExpired(self: *Self) ?Entry {
                return Impl.popExpired(self);
            }

            pub fn remove(self: *Self, handle: Handle) ?Entry {
                return Impl.remove(self, handle);
            }

            pub fn updateDeadline(self: *Self, handle: Handle, deadline: Deadline) RangeError!bool {
                return Impl.updateDeadline(self, handle, deadline, config);
            }

            pub fn contains(self: *const Self, handle: Handle) bool {
                return Impl.resolve(self, handle) != null;
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(self, config);
            }
        };
    }
};

const Impl = struct {
    const Error = error{ Full, OutOfRange };
    const RangeError = error{OutOfRange};
    const none: usize = std.math.maxInt(usize);

    const Tick = struct {
        index: u64,

        const Self = @This();
        const zero: Self = .{ .index = 0 };

        fn floor(start: Instant, now: Instant, tick_ns: u64) Self {
            if (now.nanos() <= start.nanos()) {
                return zero;
            }
            return .{ .index = (now.nanos() - start.nanos()) / tick_ns };
        }

        fn ceil(start: Instant, now: Instant, tick_ns: u64) Self {
            if (now.nanos() <= start.nanos()) {
                return zero;
            }
            const delta = now.nanos() - start.nanos();
            var index = delta / tick_ns;
            if (delta % tick_ns != 0) {
                index += 1;
            }
            return .{ .index = index };
        }

        fn instant(self: Self, start: Instant, tick_ns: u64) ?Instant {
            if (self.index > (std.math.maxInt(u64) - start.nanos()) / tick_ns) {
                return null;
            }
            return Instant.fromNanos(start.nanos() + self.index * tick_ns);
        }

        fn bucket(self: Self, bucket_count: usize) usize {
            return @intCast(self.index & @as(u64, @intCast(bucket_count - 1)));
        }
    };

    fn Slot(comptime T: type) type {
        return struct {
            deadline: Deadline,
            item: T,
            due: Tick,
            generation: u64,
            prev: usize,
            next: usize,
            bucket: usize,
            state: State,

            const State = enum { free, bucket, expired };
            const Self = @This();

            fn invalidate(self: *Self, next: usize) void {
                self.generation +%= 1;
                if (self.generation == 0) {
                    self.generation = 1;
                }
                self.deadline = Deadline.never;
                self.item = undefined;
                self.due = Tick.zero;
                self.prev = none;
                self.next = next;
                self.bucket = none;
                self.state = .free;
            }
        };
    }

    fn Entry(comptime T: type) type {
        return struct {
            deadline: Deadline,
            item: T,
        };
    }

    fn Handle(comptime Owner: type) type {
        return enum(u128) {
            _,

            const Self = @This();
            const Parts = struct { index: usize, generation: u64 };

            fn init(index: usize, generation: u64) Self {
                _ = Owner;
                const encoded_index: u64 = @intCast(index);
                return @enumFromInt((@as(u128, generation) << 64) | encoded_index);
            }

            fn decode(self: Self) ?Parts {
                const raw = @intFromEnum(self);
                const encoded_index: u64 = @truncate(raw);
                return .{
                    .index = std.math.cast(usize, encoded_index) orelse return null,
                    .generation = @truncate(raw >> 64),
                };
            }
        };
    }

    const List = struct {
        head: usize = none,
        tail: usize = none,

        fn append(self: *List, slots: anytype, index: usize) void {
            slots[index].prev = self.tail;
            slots[index].next = none;

            if (self.tail == none) {
                self.head = index;
            } else {
                slots[self.tail].next = index;
            }

            self.tail = index;
        }

        fn remove(self: *List, slots: anytype, index: usize) void {
            const prev = slots[index].prev;
            const next = slots[index].next;

            if (prev == none) {
                self.head = next;
            } else {
                slots[prev].next = next;
            }

            if (next == none) {
                self.tail = prev;
            } else {
                slots[next].prev = prev;
            }

            slots[index].prev = none;
            slots[index].next = none;
        }

        fn isValid(self: *const List, slots: anytype) ?usize {
            var index = self.head;
            var prev = none;
            var count: usize = 0;

            while (index != none) {
                if (index >= slots.len or count == slots.len) {
                    return null;
                }

                if (slots[index].prev != prev) {
                    return null;
                }

                prev = index;
                index = slots[index].next;
                count += 1;
            }

            if (prev != self.tail) {
                return null;
            }

            return count;
        }
    };

    fn requireConfig(comptime config: TimerWheel.Config) void {
        if (config.tick_ns == 0) {
            @compileError("TimerWheel.Config.tick_ns must be greater than zero");
        }
        if (config.bucket_count < 2 or !std.math.isPowerOfTwo(config.bucket_count)) {
            @compileError("TimerWheel.Config.bucket_count must be a power of two of at least 2");
        }
        if (config.bucket_count - 1 > std.math.maxInt(u64) / config.tick_ns) {
            @compileError("TimerWheel.Config horizon must fit in the Instant nanosecond domain");
        }
    }

    fn initialize(wheel: anytype) void {
        for (wheel.slots[0..], 0..) |*slot, index| {
            slot.generation = 0;
            slot.invalidate(if (index + 1 < wheel.slots.len) index + 1 else none);
        }

        for (wheel.buckets[0..]) |*bucket| {
            bucket.* = .{};
        }

        wheel.tick = Tick.zero;
        wheel.count = 0;
        wheel.free = if (wheel.slots.len == 0) none else 0;
        wheel.expired = .{};
    }

    fn clear(wheel: anytype) void {
        for (wheel.slots[0..], 0..) |*slot, index| {
            slot.invalidate(if (index + 1 < wheel.slots.len) index + 1 else none);
        }

        for (wheel.buckets[0..]) |*bucket| {
            bucket.* = .{};
        }

        wheel.count = 0;
        wheel.free = if (wheel.slots.len == 0) none else 0;
        wheel.expired = .{};
    }

    fn quantize(wheel: anytype, deadline: Deadline, comptime config: TimerWheel.Config) RangeError!Tick {
        if (deadline.isNever()) {
            return error.OutOfRange;
        }

        const cursor = wheel.tick.instant(wheel.start, config.tick_ns) orelse return error.OutOfRange;
        const deadline_ns = deadline.instant().nanos();
        if (deadline_ns <= cursor.nanos()) {
            return wheel.tick;
        }

        const due = Tick.ceil(wheel.start, deadline.instant(), config.tick_ns);
        if (due.index - wheel.tick.index >= config.bucket_count) {
            return error.OutOfRange;
        }

        _ = due.instant(wheel.start, config.tick_ns) orelse return error.OutOfRange;
        return due;
    }

    fn insert(
        comptime T: type,
        wheel: anytype,
        deadline: Deadline,
        item: T,
        due: Tick,
    ) @TypeOf(wheel.*).Handle {
        const Wheel = @TypeOf(wheel.*);

        const index = wheel.free;
        const slot = &wheel.slots[index];
        wheel.free = slot.next;

        slot.deadline = deadline;
        slot.item = item;
        slot.due = due;
        attach(wheel, index);

        wheel.count += 1;

        return Wheel.Handle.init(index, slot.generation);
    }

    fn advanceTo(wheel: anytype, now: Instant, comptime config: TimerWheel.Config) void {
        const target = Tick.floor(wheel.start, now, config.tick_ns);
        if (target.index <= wheel.tick.index) {
            return;
        }

        if (target.index - wheel.tick.index >= config.bucket_count) {
            for (0..wheel.buckets.len) |index| {
                expireBucket(wheel, index);
            }
        } else {
            var tick = wheel.tick;
            while (tick.index < target.index) {
                tick.index += 1;
                expireBucket(wheel, tick.bucket(config.bucket_count));
            }
        }

        wheel.tick = target;
    }

    fn nextWake(wheel: anytype, comptime config: TimerWheel.Config) ?Instant {
        if (wheel.expired.head != none) {
            return wheel.tick.instant(wheel.start, config.tick_ns);
        }

        var best: ?Tick = null;
        for (wheel.buckets[0..]) |bucket| {
            if (bucket.head != none) {
                const due = wheel.slots[bucket.head].due;
                if (best == null or due.index < best.?.index) {
                    best = due;
                }
            }
        }

        return if (best) |tick| tick.instant(wheel.start, config.tick_ns) else null;
    }

    fn popExpired(wheel: anytype) ?@TypeOf(wheel.*).Entry {
        if (wheel.expired.head == none) {
            return null;
        }
        return removeAt(wheel, wheel.expired.head);
    }

    fn remove(wheel: anytype, handle: @TypeOf(wheel.*).Handle) ?@TypeOf(wheel.*).Entry {
        const index = resolve(wheel, handle) orelse return null;
        return removeAt(wheel, index);
    }

    fn updateDeadline(
        wheel: anytype,
        handle: @TypeOf(wheel.*).Handle,
        deadline: Deadline,
        comptime config: TimerWheel.Config,
    ) RangeError!bool {
        const index = resolve(wheel, handle) orelse return false;
        const due = try quantize(wheel, deadline, config);

        detach(wheel, index);
        wheel.slots[index].deadline = deadline;
        wheel.slots[index].due = due;
        attach(wheel, index);

        return true;
    }

    fn resolve(wheel: anytype, handle: @TypeOf(wheel.*).Handle) ?usize {
        const parts = handle.decode() orelse return null;
        if (parts.index >= wheel.slots.len) {
            return null;
        }

        const slot = &wheel.slots[parts.index];
        if (slot.state == .free or slot.generation != parts.generation) {
            return null;
        }

        return parts.index;
    }

    fn removeAt(wheel: anytype, index: usize) @TypeOf(wheel.*).Entry {
        const slot = &wheel.slots[index];
        const entry: @TypeOf(wheel.*).Entry = .{ .deadline = slot.deadline, .item = slot.item };

        detach(wheel, index);
        slot.invalidate(wheel.free);

        wheel.free = index;
        wheel.count -= 1;

        return entry;
    }

    fn attach(wheel: anytype, index: usize) void {
        const slot = &wheel.slots[index];
        if (slot.due.index <= wheel.tick.index) {
            slot.state = .expired;
            slot.bucket = none;
            wheel.expired.append(wheel.slots[0..], index);
        } else {
            const bucket = slot.due.bucket(wheel.buckets.len);
            slot.state = .bucket;
            slot.bucket = bucket;
            wheel.buckets[bucket].append(wheel.slots[0..], index);
        }
    }

    fn detach(wheel: anytype, index: usize) void {
        const slot = &wheel.slots[index];
        switch (slot.state) {
            .free => unreachable,
            .bucket => wheel.buckets[slot.bucket].remove(wheel.slots[0..], index),
            .expired => wheel.expired.remove(wheel.slots[0..], index),
        }
    }

    fn expireBucket(wheel: anytype, index: usize) void {
        const bucket = &wheel.buckets[index];
        while (bucket.head != none) {
            const head = bucket.head;
            bucket.remove(wheel.slots[0..], head);
            wheel.slots[head].state = .expired;
            wheel.slots[head].bucket = none;
            wheel.expired.append(wheel.slots[0..], head);
        }
    }

    fn isValid(wheel: anytype, comptime config: TimerWheel.Config) bool {
        if (wheel.buckets.len != config.bucket_count or wheel.count > wheel.slots.len) {
            return false;
        }

        if (wheel.tick.instant(wheel.start, config.tick_ns) == null) {
            return false;
        }

        var free_count: usize = 0;
        var index = wheel.free;

        while (index != none) {
            if (index >= wheel.slots.len or free_count == wheel.slots.len) {
                return false;
            }

            const slot = &wheel.slots[index];
            if (slot.state != .free) {
                return false;
            }

            if (slot.prev != none or slot.bucket != none) {
                return false;
            }

            free_count += 1;
            index = slot.next;
        }

        var listed = wheel.expired.isValid(wheel.slots[0..]) orelse return false;

        index = wheel.expired.head;
        while (index != none) {
            const slot = &wheel.slots[index];
            if (slot.state != .expired or slot.bucket != none) {
                return false;
            }

            if (slot.due.index > wheel.tick.index) {
                return false;
            }

            index = slot.next;
        }

        for (wheel.buckets[0..], 0..) |*bucket, bucket_index| {
            const bucket_len = bucket.isValid(wheel.slots[0..]) orelse return false;
            if (bucket_len > wheel.slots.len - listed) {
                return false;
            }

            listed += bucket_len;
            index = bucket.head;

            while (index != none) {
                const slot = &wheel.slots[index];
                if (slot.state != .bucket or slot.bucket != bucket_index) {
                    return false;
                }

                if (slot.due.index <= wheel.tick.index) {
                    return false;
                }

                if (slot.due.index - wheel.tick.index >= config.bucket_count) {
                    return false;
                }

                if (slot.due.bucket(config.bucket_count) != bucket_index) {
                    return false;
                }

                if (slot.due.instant(wheel.start, config.tick_ns) == null) {
                    return false;
                }

                index = slot.next;
            }
        }

        for (wheel.slots[0..]) |*slot| {
            if (slot.generation == 0) {
                return false;
            }
        }

        return listed == wheel.count and free_count == wheel.slots.len - wheel.count;
    }
};

pub const unit = struct {
    const testing = std.testing;

    const config = TimerWheel.Config{ .tick_ns = 10, .bucket_count = 8 };

    fn instant(ns: u64) Instant {
        return Instant.fromNanos(ns);
    }

    fn makeDeadline(ns: u64) Deadline {
        return Deadline.from(instant(ns));
    }

    fn Wheel(comptime T: type, comptime capacity: usize) type {
        return TimerWheel.Static(T, capacity, config);
    }

    fn insert(wheel: anytype, deadline: Deadline, item: u8) !@TypeOf(wheel.*).Handle {
        const due = try Impl.quantize(wheel, deadline, config);
        return Impl.insert(u8, wheel, deadline, item, due);
    }

    fn expectWake(wheel: anytype, ns: ?u64) !void {
        const wake = Impl.nextWake(wheel, config);
        if (ns) |value| {
            try testing.expectEqual(instant(value), wake.?);
        } else {
            try testing.expect(wake == null);
        }
    }

    fn expectEntry(entry: anytype, ns: u64, item: u8) !void {
        try testing.expectEqual(makeDeadline(ns), entry.deadline);
        try testing.expectEqual(item, entry.item);
    }

    test "owned and borrowed storage preserve entries across capacity and range errors" {
        const Borrowed = TimerWheel.Bounded(*u8, config);

        {
            var item: u8 = 0;
            var slots: [0]Borrowed.Slot = .{};
            var buckets: [config.bucket_count]Borrowed.Bucket = undefined;
            var wheel = Borrowed.wrap(&slots, &buckets, instant(100));

            try testing.expectEqual(@as(usize, 0), wheel.capacity());
            try testing.expect(wheel.isEmpty() and wheel.isFull());
            try testing.expectError(error.OutOfRange, wheel.insert(Deadline.never, &item));
            try testing.expectError(error.Full, wheel.insert(makeDeadline(100), &item));
            try testing.expect(wheel.isValid());
        }

        var first: u8 = 1;
        var second: u8 = 2;
        var owned = Wheel(*u8, 2).init(instant(100));
        var slots: [2]Borrowed.Slot = undefined;
        var buckets: [config.bucket_count]Borrowed.Bucket = undefined;
        var borrowed = Borrowed.wrap(&slots, &buckets, instant(100));

        inline for (.{ &owned, &borrowed }) |wheel| {
            const due = try wheel.insertAssumeCapacity(makeDeadline(100), &first);
            const future = try wheel.insert(makeDeadline(170), &second);

            try testing.expectEqual(@as(usize, 2), wheel.len());
            try testing.expectEqual(@as(usize, 0), wheel.remaining());
            try testing.expect(wheel.isFull());
            try testing.expectError(error.Full, wheel.insert(makeDeadline(110), &first));

            const popped = wheel.popExpired().?;

            try testing.expectEqual(makeDeadline(100), popped.deadline);
            try testing.expectEqual(&first, popped.item);
            try testing.expectEqual(@as(u8, 1), popped.item.*);
            try testing.expect(!wheel.contains(due));

            const removed = wheel.remove(future).?;

            try testing.expectEqual(makeDeadline(170), removed.deadline);
            try testing.expectEqual(&second, removed.item);
            try testing.expectEqual(@as(u8, 2), removed.item.*);

            try testing.expectError(error.OutOfRange, wheel.insert(Deadline.never, &first));
            try testing.expectError(error.OutOfRange, wheel.insert(makeDeadline(171), &first));
            try testing.expectError(error.OutOfRange, wheel.insertAssumeCapacity(Deadline.never, &first));
            try testing.expect(wheel.isEmpty());
            try testing.expect(wheel.isValid());
        }

        try testing.expect(borrowed.slots.ptr == &slots);
        try testing.expect(borrowed.buckets.ptr == &buckets);
    }

    test "ceiling quantization and inclusive cursor expiry never expire early" {
        var wheel = Wheel(u8, 4).init(instant(100));
        _ = try insert(&wheel, makeDeadline(99), 0);
        _ = try insert(&wheel, makeDeadline(105), 1);
        _ = try insert(&wheel, makeDeadline(120), 2);
        _ = try insert(&wheel, makeDeadline(121), 3);

        try expectWake(&wheel, 100);

        const past = Impl.popExpired(&wheel).?;

        try expectEntry(past, 99, 0);
        try expectWake(&wheel, 110);

        Impl.advanceTo(&wheel, instant(109), config);

        try testing.expectEqual(instant(100), wheel.cursor());
        try testing.expect(Impl.popExpired(&wheel) == null);

        Impl.advanceTo(&wheel, instant(110), config);
        const rounded = Impl.popExpired(&wheel).?;

        try expectEntry(rounded, 105, 1);
        try expectWake(&wheel, 120);

        Impl.advanceTo(&wheel, instant(119), config);

        try testing.expect(Impl.popExpired(&wheel) == null);

        Impl.advanceTo(&wheel, instant(120), config);
        const exact = Impl.popExpired(&wheel).?;

        try expectEntry(exact, 120, 2);
        try expectWake(&wheel, 130);

        Impl.advanceTo(&wheel, instant(129), config);

        try testing.expect(Impl.popExpired(&wheel) == null);

        Impl.advanceTo(&wheel, instant(130), config);
        const after = Impl.popExpired(&wheel).?;

        try expectEntry(after, 121, 3);
        try expectWake(&wheel, null);
        try testing.expect(Impl.isValid(&wheel, config));
    }

    test "updates detach and append including unchanged deadlines and expired entries" {
        var wheel = Wheel(u8, 4).init(instant(0));
        const first = try insert(&wheel, makeDeadline(50), 1);
        const second = try insert(&wheel, makeDeadline(20), 2);
        const third = try insert(&wheel, makeDeadline(20), 3);

        const moved = try Impl.updateDeadline(&wheel, first, makeDeadline(20), config);
        const unchanged = try Impl.updateDeadline(&wheel, second, makeDeadline(20), config);
        Impl.advanceTo(&wheel, instant(20), config);
        const head = Impl.popExpired(&wheel).?;

        try testing.expect(moved and unchanged);
        try expectEntry(head, 20, 3);
        try testing.expect(Impl.resolve(&wheel, third) == null);

        const postponed = try Impl.updateDeadline(&wheel, first, makeDeadline(60), config);
        const expired = try Impl.updateDeadline(&wheel, second, makeDeadline(20), config);
        const next = Impl.popExpired(&wheel).?;

        try testing.expect(postponed and expired);
        try expectEntry(next, 20, 2);
        try expectWake(&wheel, 60);

        try testing.expectError(error.OutOfRange, Impl.updateDeadline(&wheel, first, Deadline.never, config));
        try testing.expectError(error.OutOfRange, Impl.updateDeadline(&wheel, first, makeDeadline(100), config));
        try expectWake(&wheel, 60);

        const removed = Impl.remove(&wheel, first).?;

        try expectEntry(removed, 60, 1);
        try expectWake(&wheel, null);
        try testing.expect(Impl.isValid(&wheel, config));
    }

    test "pop remove clear and generation rollover invalidate handles after reuse" {
        const Timers = Wheel(void, 1);

        {
            var wheel = Timers.init(instant(100));
            var stale: [3]Timers.Handle = undefined;

            stale[0] = try wheel.insert(makeDeadline(100), {});
            _ = Impl.popExpired(&wheel).?;

            stale[1] = try wheel.insert(makeDeadline(110), {});
            _ = Impl.remove(&wheel, stale[1]).?;

            stale[2] = try wheel.insert(makeDeadline(130), {});
            Impl.advanceTo(&wheel, instant(120), config);
            Impl.clear(&wheel);
            const current = try wheel.insert(makeDeadline(120), {});

            try testing.expectEqual(instant(100), wheel.origin());
            try testing.expectEqual(instant(120), wheel.cursor());
            try testing.expect(wheel.contains(current));

            for (stale) |handle| {
                const removed = Impl.remove(&wheel, handle);
                const updated = try Impl.updateDeadline(&wheel, handle, Deadline.never, config);

                try testing.expect(Impl.resolve(&wheel, handle) == null);
                try testing.expect(removed == null);
                try testing.expect(!updated);
            }

            try testing.expect(Impl.isValid(&wheel, config));
        }

        {
            var wheel = Timers.init(instant(120));
            wheel.slots[0].generation = std.math.maxInt(u64);

            const wrapping = try wheel.insert(makeDeadline(120), {});
            _ = Impl.remove(&wheel, wrapping).?;
            const reused = try wheel.insert(makeDeadline(120), {});

            try testing.expectEqual(@as(u64, 1), wheel.slots[0].generation);
            try testing.expect(!wheel.contains(wrapping));
            try testing.expect(wheel.contains(reused));
            try testing.expect(Impl.isValid(&wheel, config));
        }

        {
            var wheel = Timers.init(instant(100));
            const invalid: Timers.Handle = @enumFromInt((@as(u128, 1) << 64) | std.math.maxInt(u64));

            try testing.expect(!wheel.contains(@enumFromInt(0)));
            try testing.expect(!wheel.contains(invalid));
        }
    }

    test "maximum instants reject unrepresentable rounded wakes and permit final tick advances" {
        const max = std.math.maxInt(u64);

        {
            const Fine = TimerWheel.Static(u8, 2, .{ .tick_ns = 1, .bucket_count = 8 });
            var wheel = Fine.init(instant(0));
            wheel.advanceTo(instant(max - 2));
            _ = try wheel.insert(makeDeadline(max - 1), 1);

            wheel.advanceTo(instant(max));
            wheel.advanceTo(instant(max));
            const entry = wheel.popExpired().?;

            try expectEntry(entry, max - 1, 1);
            try testing.expect(wheel.isValid());
        }

        {
            var wheel = Wheel(u8, 2).init(instant(max - 15));
            _ = try wheel.insert(makeDeadline(max - 5), 2);

            try testing.expectError(error.OutOfRange, wheel.insert(makeDeadline(max - 4), 3));

            wheel.advanceTo(instant(max));
            const entry = wheel.popExpired().?;

            try testing.expectEqual(instant(max - 5), wheel.cursor());
            try expectEntry(entry, max - 5, 2);
            try testing.expect(wheel.isValid());
        }
    }

    test "validator rejects invalid links accounting generations ticks and storage lengths" {
        var wheel = Wheel(u8, 4).init(instant(0));
        const handle = try insert(&wheel, makeDeadline(20), 1);
        const live = Impl.resolve(&wheel, handle).?;
        const free = wheel.free;
        const original = wheel;

        try testing.expect(Impl.isValid(&original, config));

        {
            var invalid = original;
            invalid.count += 1;

            try testing.expect(!Impl.isValid(&invalid, config));
        }

        {
            var invalid = original;
            invalid.slots[free].next = free;

            try testing.expect(!Impl.isValid(&invalid, config));
        }

        {
            var invalid = original;
            invalid.slots[live].next = live;

            try testing.expect(!Impl.isValid(&invalid, config));
        }

        {
            var invalid = original;
            invalid.slots[live].prev = free;

            try testing.expect(!Impl.isValid(&invalid, config));
        }

        {
            var invalid = original;
            invalid.free = live;

            try testing.expect(!Impl.isValid(&invalid, config));
        }

        {
            var invalid = original;
            invalid.slots[free].generation = 0;

            try testing.expect(!Impl.isValid(&invalid, config));
        }

        {
            var invalid = original;
            invalid.slots[live].due = .{ .index = 3 };

            try testing.expect(!Impl.isValid(&invalid, config));
        }

        {
            var invalid = original;
            invalid.slots[live].due = .{ .index = 10 };

            try testing.expect(!Impl.isValid(&invalid, config));
        }

        {
            var invalid = original;
            invalid.tick = .{ .index = std.math.maxInt(u64) };

            try testing.expect(!Impl.isValid(&invalid, config));
        }

        {
            var invalid = original;
            Impl.advanceTo(&invalid, instant(20), config);
            invalid.slots[live].due = .{ .index = 3 };

            try testing.expect(!Impl.isValid(&invalid, config));
        }

        const Borrowed = TimerWheel.Bounded(u8, config);
        var slots: [2]Borrowed.Slot = undefined;
        var buckets: [config.bucket_count]Borrowed.Bucket = undefined;
        const borrowed = Borrowed.wrap(&slots, &buckets, instant(0));

        {
            var invalid = borrowed;
            invalid.buckets = buckets[0 .. buckets.len - 1];

            try testing.expect(!Impl.isValid(&invalid, config));
        }

        {
            var invalid = borrowed;
            invalid.slots = slots[0..1];

            try testing.expect(!Impl.isValid(&invalid, config));
        }
    }

    const Model = struct {
        const capacity = 6;
        const origin_ns = 0;
        const tick_ns = config.tick_ns;
        const bucket_count = config.bucket_count;

        const Entry = struct {
            live: bool = false,
            deadline_ns: u64 = 0,
            due_tick: u64 = 0,
            item: u8 = 0,
        };

        entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
        current_tick: u64 = 0,
        len: usize = 0,

        fn cursorNs(self: *const Model) u64 {
            return origin_ns + self.current_tick * tick_ns;
        }

        fn quantize(self: *const Model, ns: u64) error{OutOfRange}!u64 {
            const due_tick = if (ns <= self.cursorNs())
                self.current_tick
            else
                @divFloor(ns - origin_ns + tick_ns - 1, tick_ns);

            if (due_tick < self.current_tick or due_tick >= self.current_tick + bucket_count) {
                return error.OutOfRange;
            }
            return due_tick;
        }

        fn insert(self: *Model, id: usize, ns: u64, item: u8) error{OutOfRange}!void {
            const due_tick = try self.quantize(ns);
            testing.expect(!self.entries[id].live) catch unreachable;
            self.entries[id] = .{
                .live = true,
                .deadline_ns = ns,
                .due_tick = due_tick,
                .item = item,
            };
            self.len += 1;
        }

        fn update(self: *Model, id: usize, ns: u64) error{OutOfRange}!bool {
            if (!self.entries[id].live) {
                return false;
            }
            const due_tick = try self.quantize(ns);
            self.entries[id].deadline_ns = ns;
            self.entries[id].due_tick = due_tick;
            return true;
        }

        fn advanceTo(self: *Model, ns: u64) void {
            const target_tick = @divFloor(ns - origin_ns, tick_ns);
            if (target_tick > self.current_tick) {
                self.current_tick = target_tick;
            }
        }

        fn nextWakeNs(self: *const Model) ?u64 {
            if (self.len == 0) {
                return null;
            }

            var best: ?u64 = null;
            for (self.entries) |entry| {
                if (!entry.live) {
                    continue;
                }
                if (entry.due_tick <= self.current_tick) {
                    return self.cursorNs();
                }
                if (best == null or entry.due_tick < best.?) {
                    best = entry.due_tick;
                }
            }
            return origin_ns + best.? * tick_ns;
        }

        fn removeExpired(self: *Model, item: u8) !Entry {
            for (&self.entries) |*entry| {
                if (!entry.live or entry.item != item) {
                    continue;
                }

                try testing.expect(entry.due_tick <= self.current_tick);
                const expected = entry.*;
                entry.live = false;
                self.len -= 1;
                return expected;
            }
            return error.TestUnexpectedResult;
        }

        fn clear(self: *Model) void {
            for (&self.entries) |*entry| {
                entry.live = false;
            }
            self.len = 0;
        }
    };

    fn expectModelState(comptime Timers: type, wheel: *const Timers, model: *const Model) !void {
        try testing.expectEqual(model.len, wheel.len());
        try expectWake(wheel, model.nextWakeNs());
        try testing.expect(Impl.isValid(wheel, config));
    }

    fn popAndMirror(comptime Timers: type, wheel: *Timers, model: *Model) !void {
        const entry = wheel.popExpired() orelse {
            for (model.entries) |expected| {
                try testing.expect(!expected.live or expected.due_tick > model.current_tick);
            }
            return;
        };
        const expected = try model.removeExpired(entry.item);

        try expectEntry(entry, expected.deadline_ns, expected.item);
        try expectModelState(Timers, wheel, model);
    }

    test "model: deterministic sequence matches reference wheel semantics" {
        const Timers = Wheel(u8, Model.capacity);

        var wheel = Timers.init(instant(Model.origin_ns));
        var model = Model{};
        var handles: [Model.capacity]Timers.Handle = undefined;

        try expectModelState(Timers, &wheel, &model);

        handles[0] = try wheel.insert(makeDeadline(5), 0);
        try model.insert(0, 5, 0);

        try expectModelState(Timers, &wheel, &model);

        handles[1] = try wheel.insert(makeDeadline(24), 1);
        try model.insert(1, 24, 1);

        try expectModelState(Timers, &wheel, &model);

        try testing.expectError(error.OutOfRange, wheel.insert(makeDeadline(80), 5));
        try expectModelState(Timers, &wheel, &model);

        const moved = try wheel.updateDeadline(handles[1], makeDeadline(45));
        const model_moved = try model.update(1, 45);

        try testing.expectEqual(model_moved, moved);
        try expectModelState(Timers, &wheel, &model);

        try testing.expectError(error.OutOfRange, wheel.updateDeadline(handles[0], Deadline.never));
        try expectModelState(Timers, &wheel, &model);

        wheel.advanceTo(instant(9));
        model.advanceTo(9);

        try expectModelState(Timers, &wheel, &model);
        try popAndMirror(Timers, &wheel, &model);

        wheel.advanceTo(instant(10));
        model.advanceTo(10);

        try expectModelState(Timers, &wheel, &model);
        try popAndMirror(Timers, &wheel, &model);

        try testing.expect(!wheel.contains(handles[0]));
        const removed = wheel.remove(handles[0]);
        const updated = try wheel.updateDeadline(handles[0], makeDeadline(10));

        try testing.expect(removed == null);
        try testing.expect(!updated);
        try expectModelState(Timers, &wheel, &model);

        handles[2] = try wheel.insert(makeDeadline(70), 2);
        try model.insert(2, 70, 2);

        try expectModelState(Timers, &wheel, &model);

        const advanced = try wheel.updateDeadline(handles[1], makeDeadline(15));
        const model_advanced = try model.update(1, 15);

        try testing.expectEqual(model_advanced, advanced);
        try expectModelState(Timers, &wheel, &model);

        try testing.expectError(error.OutOfRange, wheel.updateDeadline(handles[1], makeDeadline(90)));
        try expectModelState(Timers, &wheel, &model);

        wheel.advanceTo(instant(100));
        model.advanceTo(100);

        try expectModelState(Timers, &wheel, &model);
        try popAndMirror(Timers, &wheel, &model);
        try popAndMirror(Timers, &wheel, &model);
        try popAndMirror(Timers, &wheel, &model);

        handles[3] = try wheel.insert(makeDeadline(100), 3);
        try model.insert(3, 100, 3);

        try expectModelState(Timers, &wheel, &model);
        try popAndMirror(Timers, &wheel, &model);

        handles[4] = try wheel.insert(makeDeadline(120), 4);
        try model.insert(4, 120, 4);

        handles[5] = try wheel.insert(makeDeadline(150), 5);
        try model.insert(5, 150, 5);

        try expectModelState(Timers, &wheel, &model);

        wheel.clearRetainingCapacity();
        model.clear();

        try expectModelState(Timers, &wheel, &model);

        const cleared = wheel.remove(handles[4]);
        const rescheduled = try wheel.updateDeadline(handles[5], makeDeadline(100));

        try testing.expect(cleared == null);
        try testing.expect(!rescheduled);
    }
};
