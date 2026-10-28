//! fixed-capacity deadline priority queue

const std = @import("std");

const debug = @import("core").debug;

const Deadline = @import("deadline.zig").Deadline;
const Instant = @import("monotonic.zig").Instant;

pub const DeadlineQueue = struct {
    pub fn Static(comptime T: type, comptime count: usize) type {
        comptime {
            if (count == 0) {
                @compileError("DeadlineQueue.Static count must be non-zero");
            }
        }

        return struct {
            slots: [count]Slot,
            heap: [count]usize,
            count: usize,
            free: usize,

            pub const bound = count;

            const Self = @This();
            const Slot = Impl.Slot(T);

            pub const Handle = Impl.Handle(Self);
            pub const Entry = Impl.Entry(T);
            pub const Error = Impl.Error;

            pub fn init() Self {
                var self: Self = undefined;
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

            pub fn clearRetainingCapacity(self: *Self) void {
                Impl.clear(self);
            }

            pub fn insert(self: *Self, deadline: Deadline, item: T) Error!Handle {
                if (self.isFull()) {
                    return error.Full;
                }
                return Impl.insert(T, self, deadline, item);
            }

            pub fn insertAssumeCapacity(self: *Self, deadline: Deadline, item: T) Handle {
                if (debug.checksEnabled()) {
                    std.debug.assert(!self.isFull());
                }
                return Impl.insert(T, self, deadline, item);
            }

            pub fn peekDeadline(self: *const Self) ?Deadline {
                if (self.count == 0) {
                    return null;
                }
                return self.slots[self.heap[0]].deadline;
            }

            pub fn popExpired(self: *Self, now: Instant) ?Entry {
                return Impl.popExpired(self, now);
            }

            pub fn popNext(self: *Self) ?Entry {
                if (self.count == 0) {
                    return null;
                }
                return Impl.removeAt(self, 0);
            }

            pub fn remove(self: *Self, handle: Handle) ?Entry {
                return Impl.remove(self, handle);
            }

            pub fn updateDeadline(self: *Self, handle: Handle, deadline: Deadline) bool {
                return Impl.updateDeadline(self, handle, deadline);
            }

            pub fn contains(self: *const Self, handle: Handle) bool {
                return Impl.resolve(self, handle) != null;
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(self);
            }
        };
    }

    pub fn Bounded(comptime T: type) type {
        return struct {
            slots: []Slot,
            heap: []usize,
            count: usize,
            free: usize,

            const Self = @This();

            pub const Slot = Impl.Slot(T);
            pub const Handle = Impl.Handle(Self);
            pub const Entry = Impl.Entry(T);
            pub const Error = Impl.Error;

            /// borrows and reinitializes both slices; lengths must match
            /// storage must remain valid and exclusively used by this queue
            pub fn wrap(slots: []Slot, heap: []usize) Self {
                if (debug.checksEnabled()) {
                    std.debug.assert(slots.len == heap.len);
                }

                var self: Self = .{
                    .slots = slots,
                    .heap = heap,
                    .count = undefined,
                    .free = undefined,
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

            pub fn clearRetainingCapacity(self: *Self) void {
                Impl.clear(self);
            }

            pub fn insert(self: *Self, deadline: Deadline, item: T) Error!Handle {
                if (self.isFull()) {
                    return error.Full;
                }
                return Impl.insert(T, self, deadline, item);
            }

            pub fn insertAssumeCapacity(self: *Self, deadline: Deadline, item: T) Handle {
                if (debug.checksEnabled()) {
                    std.debug.assert(!self.isFull());
                }
                return Impl.insert(T, self, deadline, item);
            }

            pub fn peekDeadline(self: *const Self) ?Deadline {
                if (self.count == 0) {
                    return null;
                }
                return self.slots[self.heap[0]].deadline;
            }

            pub fn popExpired(self: *Self, now: Instant) ?Entry {
                return Impl.popExpired(self, now);
            }

            pub fn popNext(self: *Self) ?Entry {
                if (self.count == 0) {
                    return null;
                }
                return Impl.removeAt(self, 0);
            }

            pub fn remove(self: *Self, handle: Handle) ?Entry {
                return Impl.remove(self, handle);
            }

            pub fn updateDeadline(self: *Self, handle: Handle, deadline: Deadline) bool {
                return Impl.updateDeadline(self, handle, deadline);
            }

            pub fn contains(self: *const Self, handle: Handle) bool {
                return Impl.resolve(self, handle) != null;
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(self);
            }
        };
    }
};

const Impl = struct {
    const Error = error{Full};

    const none: usize = std.math.maxInt(usize);

    fn Slot(comptime T: type) type {
        return struct {
            deadline: Deadline,
            item: T,
            generation: u64,
            position: usize,
            next: usize,
            occupied: bool,

            const Self = @This();

            fn invalidate(self: *Self, next: usize) void {
                self.generation +%= 1;
                if (self.generation == 0) {
                    self.generation = 1;
                }
                self.deadline = Deadline.never;
                self.item = undefined;
                self.position = none;
                self.next = next;
                self.occupied = false;
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

            const Parts = struct {
                index: usize,
                generation: u64,
            };

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

    fn initialize(queue: anytype) void {
        for (queue.slots[0..], 0..) |*slot, index| {
            var next = none;
            if (index + 1 < queue.slots.len) {
                next = index + 1;
            }

            slot.* = .{
                .deadline = Deadline.never,
                .item = undefined,
                .generation = 1,
                .position = none,
                .next = next,
                .occupied = false,
            };
        }

        for (queue.heap[0..]) |*entry| {
            entry.* = none;
        }

        queue.count = 0;
        queue.free = switch (queue.slots.len) {
            0 => none,
            else => 0,
        };
    }

    fn clear(queue: anytype) void {
        for (queue.heap[0..queue.count]) |*entry| {
            const index = entry.*;
            queue.slots[index].invalidate(queue.free);
            queue.free = index;
            entry.* = none;
        }
        queue.count = 0;
    }

    fn insert(comptime T: type, queue: anytype, deadline: Deadline, item: T) @TypeOf(queue.*).Handle {
        const Queue = @TypeOf(queue.*);

        const index = queue.free;
        const slot = &queue.slots[index];
        queue.free = slot.next;
        slot.deadline = deadline;
        slot.item = item;
        slot.position = queue.count;
        slot.next = none;
        slot.occupied = true;
        queue.heap[queue.count] = index;
        queue.count += 1;
        siftUp(queue, slot.position);
        return Queue.Handle.init(index, slot.generation);
    }

    fn popExpired(queue: anytype, now: Instant) ?@TypeOf(queue.*).Entry {
        if (queue.count == 0) {
            return null;
        }
        if (!now.isAtOrAfter(queue.slots[queue.heap[0]].deadline.instant())) {
            return null;
        }
        return removeAt(queue, 0);
    }

    fn remove(queue: anytype, handle: @TypeOf(queue.*).Handle) ?@TypeOf(queue.*).Entry {
        const index = resolve(queue, handle) orelse return null;
        return removeAt(queue, queue.slots[index].position);
    }

    fn updateDeadline(queue: anytype, handle: @TypeOf(queue.*).Handle, deadline: Deadline) bool {
        const index = resolve(queue, handle) orelse return false;
        const slot = &queue.slots[index];
        const previous = slot.deadline;
        if (deadline == previous) {
            return true;
        }

        slot.deadline = deadline;
        if (deadline.instant().nanos() < previous.instant().nanos()) {
            siftUp(queue, slot.position);
        } else {
            siftDown(queue, slot.position);
        }
        return true;
    }

    fn resolve(queue: anytype, handle: @TypeOf(queue.*).Handle) ?usize {
        const parts = handle.decode() orelse return null;
        if (parts.index >= queue.slots.len) {
            return null;
        }

        const slot = &queue.slots[parts.index];
        if (!slot.occupied or slot.generation != parts.generation) {
            return null;
        }

        return parts.index;
    }

    fn removeAt(queue: anytype, position: usize) @TypeOf(queue.*).Entry {
        const index = queue.heap[position];
        const slot = &queue.slots[index];
        const entry: @TypeOf(queue.*).Entry = .{ .deadline = slot.deadline, .item = slot.item };

        queue.count -= 1;

        if (position != queue.count) {
            const moved = queue.heap[queue.count];
            queue.heap[position] = moved;
            queue.slots[moved].position = position;
        }

        queue.heap[queue.count] = none;

        if (position != queue.count) {
            repair(queue, position);
        }

        slot.invalidate(queue.free);
        queue.free = index;
        return entry;
    }

    fn repair(queue: anytype, position: usize) void {
        if (position > 0 and less(queue, position, (position - 1) / 2)) {
            siftUp(queue, position);
        } else {
            siftDown(queue, position);
        }
    }

    fn siftUp(queue: anytype, start: usize) void {
        var position = start;
        while (position > 0) {
            const parent = (position - 1) / 2;
            if (!less(queue, position, parent)) {
                break;
            }
            swap(queue, position, parent);
            position = parent;
        }
    }

    fn siftDown(queue: anytype, start: usize) void {
        var position = start;
        while (position < queue.count / 2) {
            const left = position * 2 + 1;
            const right = left + 1;
            var best = left;

            if (right < queue.count and less(queue, right, left)) {
                best = right;
            }

            if (!less(queue, best, position)) {
                break;
            }

            swap(queue, position, best);
            position = best;
        }
    }

    fn swap(queue: anytype, a: usize, b: usize) void {
        const a_index = queue.heap[a];
        const b_index = queue.heap[b];
        queue.heap[a] = b_index;
        queue.heap[b] = a_index;
        queue.slots[a_index].position = b;
        queue.slots[b_index].position = a;
    }

    fn less(queue: anytype, a: usize, b: usize) bool {
        return queue.slots[queue.heap[a]].deadline.instant().nanos() <
            queue.slots[queue.heap[b]].deadline.instant().nanos();
    }

    fn isValid(queue: anytype) bool {
        if (queue.slots.len != queue.heap.len or queue.count > queue.slots.len) {
            return false;
        }

        var occupied: usize = 0;
        for (queue.slots[0..], 0..) |*slot, index| {
            if (slot.generation == 0) {
                return false;
            }

            if (slot.occupied) {
                if (slot.position >= queue.count or slot.next != none) {
                    return false;
                }
                if (queue.heap[slot.position] != index) {
                    return false;
                }
                occupied += 1;
            } else if (slot.position != none) {
                return false;
            }
        }

        if (occupied != queue.count) {
            return false;
        }

        for (queue.heap[0..queue.count], 0..) |index, position| {
            if (index >= queue.slots.len) {
                return false;
            }

            const slot = &queue.slots[index];
            if (!slot.occupied or slot.position != position) {
                return false;
            }

            if (position > 0 and less(queue, position, (position - 1) / 2)) {
                return false;
            }
        }

        for (queue.heap[queue.count..]) |index| {
            if (index != none) {
                return false;
            }
        }

        var free: usize = 0;
        var next = queue.free;
        while (next != none) {
            if (next >= queue.slots.len or free >= queue.slots.len - occupied) {
                return false;
            }

            const slot = &queue.slots[next];
            if (slot.occupied) {
                return false;
            }

            free += 1;
            next = slot.next;
        }

        return free + occupied == queue.slots.len;
    }
};

pub const unit = struct {
    const testing = std.testing;

    fn makeInstant(ns: u64) Instant {
        return Instant.fromNanos(ns);
    }

    fn makeDeadline(ns: u64) Deadline {
        return Deadline.from(makeInstant(ns));
    }

    fn deadlineKey(value: Deadline) u64 {
        return value.instant().nanos();
    }

    fn expectAccessors(queue: anytype, count: usize, capacity: usize) !void {
        try testing.expectEqual(count, queue.len());
        try testing.expectEqual(capacity, queue.capacity());
        try testing.expectEqual(capacity - count, queue.remaining());
        try testing.expectEqual(count == 0, queue.isEmpty());
        try testing.expectEqual(count == capacity, queue.isFull());
        try testing.expect(queue.isValid());
    }

    test "storage initialization and Full preserve live entries" {
        var first: u8 = 1;
        var second: u8 = 2;
        var owned = DeadlineQueue.Static(*u8, 2).init();
        const Queue = DeadlineQueue.Bounded(*u8);
        var slots: [2]Queue.Slot = undefined;
        var heap: [2]usize = undefined;
        var borrowed = Queue.wrap(&slots, &heap);
        var no_slots: [0]Queue.Slot = .{};
        var no_heap: [0]usize = .{};
        var empty = Queue.wrap(&no_slots, &no_heap);

        try expectAccessors(&owned, 0, 2);
        try expectAccessors(&borrowed, 0, 2);
        try expectAccessors(&empty, 0, 0);
        try testing.expect(empty.popNext() == null);
        try testing.expect(empty.peekDeadline() == null);
        try testing.expectError(error.Full, empty.insert(makeDeadline(1), &first));
        inline for (.{ &owned, &borrowed }) |queue| {
            const later = queue.insertAssumeCapacity(makeDeadline(20), &second);
            const earlier = try queue.insert(makeDeadline(10), &first);

            try testing.expectError(error.Full, queue.insert(makeDeadline(0), &first));
            try expectAccessors(queue, 2, 2);
            try testing.expect(queue.contains(later));
            try testing.expect(queue.contains(earlier));
            try testing.expectEqual(&first, queue.popNext().?.item);
            try testing.expectEqual(&second, queue.remove(later).?.item);
            try expectAccessors(queue, 0, 2);
        }
    }

    test "expiration is inclusive, ties unordered, and never orders last" {
        var queue = DeadlineQueue.Static(u8, 4).init();
        _ = Impl.insert(u8, &queue, Deadline.never, 3);
        _ = Impl.insert(u8, &queue, makeDeadline(100), 1);
        _ = Impl.insert(u8, &queue, makeDeadline(100), 2);
        _ = Impl.insert(u8, &queue, makeDeadline(101), 0);

        try testing.expect(Impl.popExpired(&queue, makeInstant(99)) == null);
        var seen = [_]bool{ false, false, false };
        for (0..2) |_| {
            const entry = Impl.popExpired(&queue, makeInstant(100)).?;

            try testing.expectEqual(makeDeadline(100), entry.deadline);
            try testing.expect(entry.item == 1 or entry.item == 2);
            try testing.expect(!seen[entry.item]);
            seen[entry.item] = true;
            try testing.expect(Impl.isValid(&queue));
        }
        try testing.expect(seen[1] and seen[2]);
        try testing.expect(Impl.popExpired(&queue, makeInstant(100)) == null);
        try testing.expectEqual(@as(u8, 0), Impl.popExpired(&queue, makeInstant(101)).?.item);
        try testing.expect(Impl.popExpired(&queue, makeInstant(std.math.maxInt(u64) - 1)) == null);
        try testing.expectEqual(Deadline.never, queue.peekDeadline().?);
        try testing.expectEqual(Deadline.never, Impl.popExpired(&queue, makeInstant(std.math.maxInt(u64))).?.deadline);
        try expectAccessors(&queue, 0, 4);
    }

    test "removing root, interior, and tail repairs in both directions" {
        const keys = [_]u64{ 1, 10, 2, 11, 12, 3, 4 };
        const sorted = [_]usize{ 0, 2, 5, 6, 1, 3, 4 };
        inline for (.{ @as(usize, 0), 1, 3, 6 }) |removed_index| {
            const Queue = DeadlineQueue.Static(u8, keys.len);
            var queue = Queue.init();
            var handles: [keys.len]Queue.Handle = undefined;
            for (keys, 0..) |key, index| {
                handles[index] = Impl.insert(u8, &queue, makeDeadline(key), @intCast(index));
            }

            const removed = Impl.remove(&queue, handles[removed_index]).?;

            try testing.expectEqual(keys[removed_index], deadlineKey(removed.deadline));
            try testing.expectEqual(@as(u8, @intCast(removed_index)), removed.item);
            try testing.expect(Impl.resolve(&queue, handles[removed_index]) == null);
            try testing.expect(Impl.isValid(&queue));
            for (sorted) |index| {
                if (index == removed_index) {
                    continue;
                }
                const entry = queue.popNext().?;

                try testing.expectEqual(makeDeadline(keys[index]), entry.deadline);
                try testing.expectEqual(@as(u8, @intCast(index)), entry.item);
                try testing.expect(Impl.isValid(&queue));
            }
            try testing.expect(queue.popNext() == null);
        }
    }

    test "deadline updates move earlier, later, unchanged, and to never" {
        var queue = DeadlineQueue.Static(u8, 3).init();
        const moving = Impl.insert(u8, &queue, makeDeadline(50), 1);
        const fixed = Impl.insert(u8, &queue, makeDeadline(30), 2);

        try testing.expect(Impl.updateDeadline(&queue, moving, makeDeadline(10)));
        try testing.expectEqual(makeDeadline(10), queue.peekDeadline().?);
        try testing.expect(Impl.updateDeadline(&queue, moving, makeDeadline(10)));
        try testing.expect(Impl.isValid(&queue));
        try testing.expect(Impl.updateDeadline(&queue, moving, makeDeadline(40)));
        try testing.expectEqual(makeDeadline(30), queue.peekDeadline().?);
        try testing.expect(Impl.updateDeadline(&queue, fixed, Deadline.never));
        try testing.expectEqual(makeDeadline(40), queue.peekDeadline().?);
        try testing.expectEqual(@as(u8, 1), queue.popNext().?.item);
        try testing.expectEqual(@as(u8, 2), queue.popNext().?.item);
        try testing.expect(Impl.isValid(&queue));
    }

    test "pop, remove, clear, and generation rollover reject stale handles after reuse" {
        const Queue = DeadlineQueue.Static(void, 1);
        var queue = Queue.init();
        queue.slots[0].generation = 100;
        var stale: [3]Queue.Handle = undefined;
        stale[0] = Impl.insert(void, &queue, makeDeadline(1), {});
        _ = queue.popNext().?;

        try testing.expect(!queue.contains(stale[0]));
        stale[1] = Impl.insert(void, &queue, makeDeadline(2), {});
        _ = Impl.remove(&queue, stale[1]).?;

        try testing.expect(!queue.contains(stale[1]));
        stale[2] = Impl.insert(void, &queue, makeDeadline(3), {});
        Impl.clear(&queue);
        const reused = Impl.insert(void, &queue, makeDeadline(5), {});

        try testing.expect(queue.contains(reused));
        for (stale) |handle| {
            try testing.expect(Impl.resolve(&queue, handle) == null);
            try testing.expect(Impl.remove(&queue, handle) == null);
            try testing.expect(!Impl.updateDeadline(&queue, handle, makeDeadline(0)));
        }
        Impl.clear(&queue);
        queue.slots[0].generation = std.math.maxInt(u64);
        const wrapping = Impl.insert(void, &queue, makeDeadline(4), {});
        _ = Impl.remove(&queue, wrapping).?;
        const current = Impl.insert(void, &queue, makeDeadline(5), {});

        try testing.expect(queue.slots[0].generation != 0);
        try testing.expect(Impl.resolve(&queue, wrapping) == null);
        const invalid: Queue.Handle = @enumFromInt(0);
        const out_of_bounds: Queue.Handle = @enumFromInt((@as(u128, 1) << 64) | std.math.maxInt(u64));

        try testing.expect(!queue.contains(invalid));
        try testing.expect(!queue.contains(out_of_bounds));
        try testing.expect(queue.contains(current));
        try testing.expectEqual(makeDeadline(5), queue.peekDeadline().?);
        try expectAccessors(&queue, 1, 1);
    }

    test "validator rejects corrupt heap, slot, and free-chain metadata" {
        var queue = DeadlineQueue.Static(u8, 4).init();
        _ = Impl.insert(u8, &queue, makeDeadline(1), 1);
        _ = Impl.insert(u8, &queue, makeDeadline(2), 2);
        const root = queue.heap[0];
        const child = queue.heap[1];
        const free = queue.free;

        try testing.expect(Impl.isValid(&queue));
        queue.count = 5;
        try testing.expect(!Impl.isValid(&queue));
        queue.count = 2;
        queue.heap[0] = queue.slots.len;
        try testing.expect(!Impl.isValid(&queue));
        queue.heap[0] = root;
        queue.slots[root].position = 1;
        try testing.expect(!Impl.isValid(&queue));
        queue.slots[root].position = 0;
        queue.slots[root].occupied = false;
        try testing.expect(!Impl.isValid(&queue));
        queue.slots[root].occupied = true;
        queue.slots[child].deadline = makeDeadline(0);
        try testing.expect(!Impl.isValid(&queue));
        queue.slots[child].deadline = makeDeadline(2);
        const next = queue.slots[free].next;
        queue.slots[free].next = free;
        try testing.expect(!Impl.isValid(&queue));
        queue.slots[free].next = queue.slots.len;
        try testing.expect(!Impl.isValid(&queue));
        queue.slots[free].next = next;
        queue.free = root;
        try testing.expect(!Impl.isValid(&queue));
        queue.free = free;
        queue.slots[root].generation = 0;
        try testing.expect(!Impl.isValid(&queue));
        queue.slots[root].generation = 1;
        try testing.expect(Impl.isValid(&queue));
    }

    fn QueueModel(comptime Queue: type, comptime max_records: usize) type {
        return struct {
            records: [max_records]Record = undefined,
            count: usize = 0,

            const Self = @This();

            const Record = struct {
                handle: Queue.Handle,
                deadline: Deadline,
                item: u16,
                live: bool,
            };

            fn liveCount(self: *const Self) usize {
                var live: usize = 0;
                var i: usize = 0;
                while (i < self.count) : (i += 1) {
                    if (self.records[i].live) {
                        live += 1;
                    }
                }
                return live;
            }

            fn add(self: *Self, handle: Queue.Handle, deadline_value: Deadline, item: u16) void {
                std.debug.assert(self.count < self.records.len);
                self.records[self.count] = .{
                    .handle = handle,
                    .deadline = deadline_value,
                    .item = item,
                    .live = true,
                };
                self.count += 1;
            }

            fn findByHandle(self: *const Self, handle: Queue.Handle) ?usize {
                var i: usize = 0;
                while (i < self.count) : (i += 1) {
                    if (self.records[i].live and self.records[i].handle == handle) {
                        return i;
                    }
                }
                return null;
            }

            fn nthLiveHandle(self: *const Self, n: usize) Queue.Handle {
                var seen: usize = 0;
                var i: usize = 0;
                while (i < self.count) : (i += 1) {
                    if (!self.records[i].live) {
                        continue;
                    }
                    if (seen == n) {
                        return self.records[i].handle;
                    }
                    seen += 1;
                }
                unreachable;
            }

            fn removeHandle(self: *Self, handle: Queue.Handle) ?Record {
                if (self.findByHandle(handle)) |index| {
                    self.records[index].live = false;
                    return self.records[index];
                }
                return null;
            }

            fn updateHandle(self: *Self, handle: Queue.Handle, deadline_value: Deadline) bool {
                if (self.findByHandle(handle)) |index| {
                    self.records[index].deadline = deadline_value;
                    return true;
                }
                return false;
            }

            fn minKey(self: *const Self) ?u64 {
                var best: ?u64 = null;
                var i: usize = 0;
                while (i < self.count) : (i += 1) {
                    if (!self.records[i].live) {
                        continue;
                    }
                    const key = deadlineKey(self.records[i].deadline);
                    if (best == null or key < best.?) {
                        best = key;
                    }
                }
                return best;
            }

            fn clear(self: *Self) void {
                var i: usize = 0;
                while (i < self.count) : (i += 1) {
                    self.records[i].live = false;
                }
            }

            fn appendLiveHandles(self: *const Self, stale: []Queue.Handle, stale_len: *usize) void {
                var i: usize = 0;
                while (i < self.count) : (i += 1) {
                    if (!self.records[i].live) {
                        continue;
                    }
                    std.debug.assert(stale_len.* < stale.len);
                    stale[stale_len.*] = self.records[i].handle;
                    stale_len.* += 1;
                }
            }

            fn removeReturned(self: *Self, entry: Queue.Entry) bool {
                var i: usize = 0;
                while (i < self.count) : (i += 1) {
                    if (!self.records[i].live) {
                        continue;
                    }
                    if (self.records[i].deadline == entry.deadline and self.records[i].item == entry.item) {
                        self.records[i].live = false;
                        return true;
                    }
                }
                return false;
            }

            fn expectPeek(self: *const Self, queue: *const Queue) !void {
                const peeked = queue.peekDeadline();
                if (self.minKey()) |expected_key| {
                    try testing.expect(peeked != null);
                    try testing.expectEqual(expected_key, deadlineKey(peeked.?));
                } else {
                    try testing.expect(peeked == null);
                }
            }

            fn expectLiveEntries(self: *const Self, queue: *const Queue) !void {
                try testing.expectEqual(self.liveCount(), queue.len());
                var i: usize = 0;
                while (i < self.count) : (i += 1) {
                    try testing.expectEqual(self.records[i].live, queue.contains(self.records[i].handle));
                }
            }
        };
    }

    test "model: deterministic operations match reference and equal deadlines are unordered" {
        const Queue = DeadlineQueue.Static(u16, 8);

        var queue = Queue.init();
        var model = QueueModel(Queue, 512){};
        var stale: [512]Queue.Handle = undefined;
        var stale_len: usize = 0;
        var next_item: u16 = 1;

        const deadline_values = [_]u64{ 10, 10, 20, 30, 30, 40, 60, std.math.maxInt(u64) };
        const now_values = [_]u64{ 0, 9, 10, 20, 29, 30, 45, 59, 60 };

        var prng = std.Random.DefaultPrng.init(0xD1EA_D11E_5EED);
        const random = prng.random();

        var step: usize = 0;
        while (step < 300) : (step += 1) {
            try testing.expect(queue.isValid());
            try model.expectLiveEntries(&queue);
            try model.expectPeek(&queue);

            switch (random.uintLessThan(u8, 8)) {
                0 => {
                    const key = deadline_values[random.uintLessThan(usize, deadline_values.len)];
                    const d = switch (key) {
                        std.math.maxInt(u64) => Deadline.never,
                        else => makeDeadline(key),
                    };

                    const item = next_item;
                    next_item += 1;

                    if (queue.isFull()) {
                        const before_len = queue.len();
                        const before_peek = queue.peekDeadline();
                        try testing.expectError(error.Full, queue.insert(d, item));
                        try testing.expectEqual(before_len, queue.len());
                        try testing.expectEqual(before_peek, queue.peekDeadline());
                    } else {
                        const handle = try queue.insert(d, item);
                        model.add(handle, d, item);
                        try testing.expect(queue.contains(handle));
                    }
                },
                1 => {
                    const live_count = model.liveCount();
                    if (live_count == 0) {
                        continue;
                    }

                    const handle = model.nthLiveHandle(random.uintLessThan(usize, live_count));
                    const expected = model.removeHandle(handle).?;
                    const got = queue.remove(handle).?;

                    try testing.expectEqual(expected.deadline, got.deadline);
                    try testing.expectEqual(expected.item, got.item);

                    stale[stale_len] = handle;
                    stale_len += 1;

                    try testing.expect(queue.remove(handle) == null);
                },
                2 => {
                    const live_count = model.liveCount();
                    if (live_count == 0) {
                        continue;
                    }

                    const handle = model.nthLiveHandle(random.uintLessThan(usize, live_count));
                    const key = deadline_values[random.uintLessThan(usize, deadline_values.len)];
                    const d = switch (key) {
                        std.math.maxInt(u64) => Deadline.never,
                        else => makeDeadline(key),
                    };

                    try testing.expect(queue.updateDeadline(handle, d));
                    try testing.expect(model.updateHandle(handle, d));
                    try testing.expect(queue.contains(handle));
                },
                3 => {
                    const now = makeInstant(now_values[random.uintLessThan(usize, now_values.len)]);
                    const min_key = model.minKey();
                    if (min_key != null and now.nanos() >= min_key.?) {
                        const got = queue.popExpired(now).?;
                        try testing.expectEqual(min_key.?, deadlineKey(got.deadline));
                        try testing.expect(deadlineKey(got.deadline) <= now.nanos());
                        try testing.expect(model.removeReturned(got));
                    } else {
                        const before_len = queue.len();
                        const before_peek = queue.peekDeadline();
                        try testing.expect(queue.popExpired(now) == null);
                        try testing.expectEqual(before_len, queue.len());
                        try testing.expectEqual(before_peek, queue.peekDeadline());
                    }
                },
                4 => {
                    if (model.minKey()) |min_key| {
                        const got = queue.popNext().?;
                        try testing.expectEqual(min_key, deadlineKey(got.deadline));
                        try testing.expect(model.removeReturned(got));
                    } else {
                        try testing.expect(queue.popNext() == null);
                    }
                },
                5 => {
                    model.appendLiveHandles(&stale, &stale_len);
                    queue.clearRetainingCapacity();
                    model.clear();
                    try testing.expect(queue.isEmpty());
                    try testing.expectEqual(@as(usize, 8), queue.capacity());
                },
                6 => {
                    if (stale_len == 0) {
                        continue;
                    }
                    const handle = stale[random.uintLessThan(usize, stale_len)];
                    const before_len = queue.len();
                    const before_peek = queue.peekDeadline();
                    try testing.expect(queue.remove(handle) == null);
                    try testing.expect(!queue.updateDeadline(handle, makeDeadline(1)));
                    try testing.expectEqual(before_len, queue.len());
                    try testing.expectEqual(before_peek, queue.peekDeadline());
                },
                else => {
                    const live_count = model.liveCount();
                    if (live_count > 0) {
                        const handle = model.nthLiveHandle(random.uintLessThan(usize, live_count));
                        try testing.expect(queue.contains(handle));
                    }
                    if (stale_len > 0) {
                        const handle = stale[random.uintLessThan(usize, stale_len)];
                        try testing.expect(!queue.contains(handle));
                    }
                },
            }
        }

        try testing.expect(queue.isValid());
        try model.expectLiveEntries(&queue);
        try model.expectPeek(&queue);
    }
};
