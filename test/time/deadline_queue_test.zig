//! Deadline queue behavioral tests. See `docs/specs/time/deadline_queue.md`.

const std = @import("std");
const stdx = @import("stdx");

const testing = std.testing;
const Instant = stdx.time.Instant;
const Deadline = stdx.time.Deadline;
const DeadlineQueue = stdx.time.DeadlineQueue;

fn instant(ns_value: u64) Instant {
    return Instant.fromNanos(ns_value);
}

fn deadline(ns_value: u64) Deadline {
    return Deadline.at(instant(ns_value));
}

fn deadlineKey(deadline_value: Deadline) u64 {
    return deadline_value.instant().nanos();
}

fn expectAccessors(queue: anytype, expected_len: usize, expected_capacity: usize) !void {
    try testing.expectEqual(expected_len, queue.len());
    try testing.expectEqual(expected_capacity, queue.capacity());
    try testing.expectEqual(expected_capacity - expected_len, queue.remaining());
    try testing.expectEqual(expected_len == 0, queue.isEmpty());
    try testing.expectEqual(expected_len == expected_capacity, queue.isFull());
}

fn expectDeadline(deadline_value: Deadline, expected_ns: u64) !void {
    try testing.expectEqual(expected_ns, deadlineKey(deadline_value));
}

fn QueueModel(comptime Queue: type, comptime max_records: usize) type {
    return struct {
        const Self = @This();

        const Record = struct {
            handle: Queue.Handle,
            deadline: Deadline,
            item: u16,
            live: bool,
        };

        records: [max_records]Record = undefined,
        count: usize = 0,

        fn liveCount(self: *const Self) usize {
            var live: usize = 0;
            var i: usize = 0;
            while (i < self.count) : (i += 1) {
                if (self.records[i].live) live += 1;
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
                if (self.records[i].live and self.records[i].handle == handle) return i;
            }
            return null;
        }

        fn nthLiveHandle(self: *const Self, n: usize) Queue.Handle {
            var seen: usize = 0;
            var i: usize = 0;
            while (i < self.count) : (i += 1) {
                if (!self.records[i].live) continue;
                if (seen == n) return self.records[i].handle;
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
                if (!self.records[i].live) continue;
                const key = deadlineKey(self.records[i].deadline);
                if (best == null or key < best.?) best = key;
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
                if (!self.records[i].live) continue;
                std.debug.assert(stale_len.* < stale.len);
                stale[stale_len.*] = self.records[i].handle;
                stale_len.* += 1;
            }
        }

        fn removeReturned(self: *Self, entry: Queue.Entry) bool {
            var i: usize = 0;
            while (i < self.count) : (i += 1) {
                if (!self.records[i].live) continue;
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

        fn expectAccessorsMirror(self: *const Self, queue: *const Queue) !void {
            try expectAccessors(queue, self.liveCount(), queue.capacity());
            var i: usize = 0;
            while (i < self.count) : (i += 1) {
                try testing.expectEqual(self.records[i].live, queue.contains(self.records[i].handle));
            }
        }
    };
}

comptime {
    std.debug.assert(@typeInfo(DeadlineQueue.Static(u8, 1).Handle).@"enum".tag_type == u128);
    std.debug.assert(!@typeInfo(DeadlineQueue.Static(u8, 1).Handle).@"enum".is_exhaustive);
    std.debug.assert(@typeInfo(DeadlineQueue.Bounded(u8).Handle).@"enum".tag_type == u128);
    std.debug.assert(!@typeInfo(DeadlineQueue.Bounded(u8).Handle).@"enum".is_exhaustive);
}

test "unit: Static and Bounded construction expose capacity" {
    const StaticThree = DeadlineQueue.Static(u8, 3);
    var static_three = StaticThree.init();
    try expectAccessors(&static_three, 0, 3);
    try testing.expect(static_three.peekDeadline() == null);
    static_three.assertValid();

    const Bounded = DeadlineQueue.Bounded(u8);
    var no_slots: [0]Bounded.Slot = .{};
    var no_heap: [0]usize = .{};
    var bounded_zero = Bounded.wrap(&no_slots, &no_heap);
    try expectAccessors(&bounded_zero, 0, 0);
    try testing.expect(bounded_zero.peekDeadline() == null);
    try testing.expectError(error.Full, bounded_zero.insert(deadline(1), 1));
    try expectAccessors(&bounded_zero, 0, 0);
    bounded_zero.assertValid();

    var slots: [4]Bounded.Slot = undefined;
    var heap: [4]usize = undefined;
    var bounded = Bounded.wrap(&slots, &heap);
    try expectAccessors(&bounded, 0, 4);
    bounded.assertValid();
}

test "contract: Bounded.wrap uses matching storage lengths" {
    const Queue = DeadlineQueue.Bounded(u8);
    var slots: [2]Queue.Slot = undefined;
    var heap: [2]usize = undefined;
    var queue = Queue.wrap(&slots, &heap);

    try expectAccessors(&queue, 0, 2);
    queue.assertValid();

    // Invalid storage shape is a debug-trap precondition. This suite exercises
    // the valid shape because std.debug.assert aborts without an expect-panic
    // harness.
}

test "unit: insert, insertAssumeCapacity, peekDeadline, and full no-mutation" {
    const Queue = DeadlineQueue.Static(u8, 2);
    var queue = Queue.init();

    try testing.expect(!queue.isFull());
    const later = queue.insertAssumeCapacity(deadline(20), 2);
    try testing.expect(queue.contains(later));
    try expectAccessors(&queue, 1, 2);
    try expectDeadline(queue.peekDeadline().?, 20);

    const earlier = try queue.insert(deadline(10), 1);
    try testing.expect(queue.contains(earlier));
    try expectAccessors(&queue, 2, 2);
    try expectDeadline(queue.peekDeadline().?, 10);
    queue.assertValid();

    try testing.expectError(error.Full, queue.insert(deadline(5), 99));
    try expectAccessors(&queue, 2, 2);
    try testing.expect(queue.contains(later));
    try testing.expect(queue.contains(earlier));
    try expectDeadline(queue.peekDeadline().?, 10);
    queue.assertValid();

    const first = queue.popNext().?;
    try testing.expectEqual(deadline(10), first.deadline);
    try testing.expectEqual(@as(u8, 1), first.item);
    const second = queue.popNext().?;
    try testing.expectEqual(deadline(20), second.deadline);
    try testing.expectEqual(@as(u8, 2), second.item);
    try testing.expect(queue.popNext() == null);
}

test "unit: Deadline.never orders after finite deadlines and does not expire for practical now" {
    const Queue = DeadlineQueue.Static(u8, 3);
    var queue = Queue.init();

    const never_handle = try queue.insert(Deadline.never, 9);
    try expectDeadline(queue.peekDeadline().?, std.math.maxInt(u64));

    const finite_handle = try queue.insert(deadline(100), 1);
    try testing.expect(queue.contains(never_handle));
    try testing.expect(queue.contains(finite_handle));
    try expectDeadline(queue.peekDeadline().?, 100);

    const expired = queue.popExpired(instant(std.math.maxInt(u64) - 1)).?;
    try testing.expectEqual(deadline(100), expired.deadline);
    try testing.expectEqual(@as(u8, 1), expired.item);
    try testing.expect(!queue.contains(finite_handle));
    try testing.expect(queue.contains(never_handle));
    try testing.expect(queue.popExpired(instant(std.math.maxInt(u64) - 1)) == null);
    try expectDeadline(queue.peekDeadline().?, std.math.maxInt(u64));

    const last = queue.popNext().?;
    try testing.expectEqual(Deadline.never, last.deadline);
    try testing.expectEqual(@as(u8, 9), last.item);
    try testing.expect(queue.popNext() == null);
}

test "unit: popExpired is inclusive at boundary and drains equal deadlines unordered" {
    const Queue = DeadlineQueue.Static(u8, 4);
    var queue = Queue.init();

    _ = try queue.insert(deadline(100), 1);
    _ = try queue.insert(deadline(100), 2);
    _ = try queue.insert(deadline(101), 3);
    try expectAccessors(&queue, 3, 4);

    try testing.expect(queue.popExpired(instant(99)) == null);
    try expectAccessors(&queue, 3, 4);
    try expectDeadline(queue.peekDeadline().?, 100);

    var seen = [_]bool{ false, false };
    var popped: usize = 0;
    while (queue.popExpired(instant(100))) |entry| {
        try testing.expectEqual(deadline(100), entry.deadline);
        switch (entry.item) {
            1 => seen[0] = true,
            2 => seen[1] = true,
            else => return error.UnexpectedItem,
        }
        popped += 1;
    }

    try testing.expectEqual(@as(usize, 2), popped);
    try testing.expect(seen[0]);
    try testing.expect(seen[1]);
    try expectAccessors(&queue, 1, 4);
    try expectDeadline(queue.peekDeadline().?, 101);

    const future = queue.popExpired(instant(102)).?;
    try testing.expectEqual(deadline(101), future.deadline);
    try testing.expectEqual(@as(u8, 3), future.item);
    try testing.expect(queue.popExpired(instant(102)) == null);
}

test "unit: popNext returns nondecreasing deadlines and leaves queue reusable" {
    const Queue = DeadlineQueue.Static(u8, 5);
    var queue = Queue.init();

    _ = try queue.insert(Deadline.never, 5);
    _ = try queue.insert(deadline(30), 3);
    _ = try queue.insert(deadline(10), 1);
    _ = try queue.insert(deadline(20), 2);
    _ = try queue.insert(deadline(20), 4);

    var previous: u64 = 0;
    var count: usize = 0;
    while (queue.popNext()) |entry| {
        const key = deadlineKey(entry.deadline);
        try testing.expect(key >= previous);
        previous = key;
        count += 1;
    }
    try testing.expectEqual(@as(usize, 5), count);
    try testing.expectEqual(std.math.maxInt(u64), previous);
    try expectAccessors(&queue, 0, 5);
    try testing.expect(queue.popNext() == null);

    const handle = try queue.insert(deadline(7), 7);
    try testing.expect(queue.contains(handle));
    const entry = queue.popNext().?;
    try testing.expectEqual(deadline(7), entry.deadline);
    try testing.expectEqual(@as(u8, 7), entry.item);
}

test "unit: remove invalidates only the removed handle and stale handles cannot affect reused slots" {
    const Queue = DeadlineQueue.Static(u8, 3);
    var queue = Queue.init();

    const h10 = try queue.insert(deadline(10), 10);
    const h20 = try queue.insert(deadline(20), 20);
    const h30 = try queue.insert(deadline(30), 30);

    const removed = queue.remove(h20).?;
    try testing.expectEqual(deadline(20), removed.deadline);
    try testing.expectEqual(@as(u8, 20), removed.item);
    try testing.expect(!queue.contains(h20));
    try testing.expect(queue.contains(h10));
    try testing.expect(queue.contains(h30));
    try expectAccessors(&queue, 2, 3);

    try testing.expect(queue.remove(h20) == null);
    try testing.expect(!queue.updateDeadline(h20, deadline(1)));
    try expectAccessors(&queue, 2, 3);
    try expectDeadline(queue.peekDeadline().?, 10);

    const reused = try queue.insert(deadline(5), 5);
    try testing.expect(!queue.contains(h20));
    try testing.expect(queue.contains(reused));
    try testing.expect(queue.remove(h20) == null);
    try testing.expect(!queue.updateDeadline(h20, deadline(1)));
    try testing.expect(queue.contains(reused));
    try expectDeadline(queue.peekDeadline().?, 5);

    var keys = [_]u64{0} ** 3;
    var i: usize = 0;
    while (queue.popNext()) |entry| : (i += 1) {
        keys[i] = deadlineKey(entry.deadline);
    }
    try testing.expectEqualSlices(u64, &.{ 5, 10, 30 }, keys[0..i]);
}

test "unit: updateDeadline moves entries earlier, later, same, never, and rejects stale handles" {
    const Queue = DeadlineQueue.Static(u8, 3);
    var queue = Queue.init();

    const moving = try queue.insert(deadline(50), 1);
    const fixed = try queue.insert(deadline(30), 2);

    try testing.expect(queue.updateDeadline(moving, deadline(10)));
    try testing.expect(queue.contains(moving));
    try expectDeadline(queue.peekDeadline().?, 10);

    try testing.expect(queue.updateDeadline(moving, deadline(10)));
    try expectDeadline(queue.peekDeadline().?, 10);

    try testing.expect(queue.updateDeadline(moving, deadline(40)));
    try expectDeadline(queue.peekDeadline().?, 30);

    try testing.expect(queue.updateDeadline(fixed, Deadline.never));
    try expectDeadline(queue.peekDeadline().?, 40);

    const popped = queue.popNext().?;
    try testing.expectEqual(deadline(40), popped.deadline);
    try testing.expectEqual(@as(u8, 1), popped.item);
    try testing.expect(!queue.contains(moving));
    try testing.expect(!queue.updateDeadline(moving, deadline(1)));
    try testing.expect(queue.remove(moving) == null);
    try expectAccessors(&queue, 1, 3);
    try expectDeadline(queue.peekDeadline().?, std.math.maxInt(u64));
    queue.assertValid();
}

test "unit: clearRetainingCapacity empties, preserves capacity, invalidates handles, and permits reuse" {
    const Queue = DeadlineQueue.Static(u8, 3);
    var queue = Queue.init();

    const h1 = try queue.insert(deadline(10), 1);
    const h2 = try queue.insert(deadline(20), 2);
    try expectAccessors(&queue, 2, 3);

    queue.clearRetainingCapacity();
    try expectAccessors(&queue, 0, 3);
    try testing.expect(queue.peekDeadline() == null);
    try testing.expect(!queue.contains(h1));
    try testing.expect(!queue.contains(h2));
    try testing.expect(queue.remove(h1) == null);
    try testing.expect(!queue.updateDeadline(h2, deadline(1)));

    const h3 = try queue.insert(deadline(5), 3);
    try testing.expect(queue.contains(h3));
    try testing.expect(!queue.contains(h1));
    try testing.expect(queue.remove(h1) == null);
    try expectDeadline(queue.peekDeadline().?, 5);
    queue.assertValid();
}

test "unit: void payload works" {
    const Queue = DeadlineQueue.Static(void, 2);
    var queue = Queue.init();

    const handle = try queue.insert(deadline(10), {});
    try testing.expect(queue.contains(handle));
    const entry = queue.popExpired(instant(10)).?;
    try testing.expectEqual(deadline(10), entry.deadline);
    _ = entry.item;
    try testing.expect(!queue.contains(handle));
    try testing.expect(queue.isEmpty());
}

test "unit: pointer payload values round-trip through remove and pop" {
    const Queue = DeadlineQueue.Static(*u32, 2);
    var queue = Queue.init();
    var a: u32 = 11;
    var b: u32 = 22;

    const ha = try queue.insert(deadline(20), &a);
    _ = try queue.insert(deadline(10), &b);

    const first = queue.popNext().?;
    try testing.expectEqual(deadline(10), first.deadline);
    try testing.expect(first.item == &b);

    const removed = queue.remove(ha).?;
    try testing.expectEqual(deadline(20), removed.deadline);
    try testing.expect(removed.item == &a);
    try testing.expect(queue.isEmpty());
}

test "contract: Handle is enum(u128) and DeadlineQueue is not root-promoted" {
    const Static = DeadlineQueue.Static(u8, 1);
    const Bounded = DeadlineQueue.Bounded(u8);

    try testing.expectEqual(u128, @typeInfo(Static.Handle).@"enum".tag_type);
    try testing.expect(!@typeInfo(Static.Handle).@"enum".is_exhaustive);
    try testing.expectEqual(u128, @typeInfo(Bounded.Handle).@"enum".tag_type);
    try testing.expect(!@typeInfo(Bounded.Handle).@"enum".is_exhaustive);
    try testing.expect(!@hasDecl(stdx, "DeadlineQueue"));
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
        queue.assertValid();
        try model.expectAccessorsMirror(&queue);
        try model.expectPeek(&queue);

        switch (random.uintLessThan(u8, 8)) {
            0 => {
                const key = deadline_values[random.uintLessThan(usize, deadline_values.len)];
                const d = if (key == std.math.maxInt(u64)) Deadline.never else deadline(key);
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
                if (live_count == 0) continue;
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
                if (live_count == 0) continue;
                const handle = model.nthLiveHandle(random.uintLessThan(usize, live_count));
                const key = deadline_values[random.uintLessThan(usize, deadline_values.len)];
                const d = if (key == std.math.maxInt(u64)) Deadline.never else deadline(key);
                try testing.expect(queue.updateDeadline(handle, d));
                try testing.expect(model.updateHandle(handle, d));
                try testing.expect(queue.contains(handle));
            },
            3 => {
                const now = instant(now_values[random.uintLessThan(usize, now_values.len)]);
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
                if (stale_len == 0) continue;
                const handle = stale[random.uintLessThan(usize, stale_len)];
                const before_len = queue.len();
                const before_peek = queue.peekDeadline();
                try testing.expect(queue.remove(handle) == null);
                try testing.expect(!queue.updateDeadline(handle, deadline(1)));
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

    queue.assertValid();
    try model.expectAccessorsMirror(&queue);
    try model.expectPeek(&queue);
}
