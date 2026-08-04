//! SPSC ring contract tests. See `docs/specs/concurrent/spsc-ring.md`.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const spsc = stdx.concurrent.spsc;
const testing = std.testing;

test "unit: spsc.Ring.Static initializes empty at approved capacity" {
    const Ring = spsc.Ring.Static(u8, 4);

    var ring: Ring = undefined;
    ring.init();

    try testing.expectEqual(@as(usize, 4), ring.capacity());
    try testing.expect(ring.isEmpty());
    try testing.expectEqual(@as(?u8, null), ring.popFront());
    ring.assertValid();
}

test "unit: spsc.Ring.Static single push and single pop preserve FIFO order" {
    const Ring = spsc.Ring.Static(u8, 4);

    var ring: Ring = undefined;
    ring.init();

    try ring.tryPushBack(1);
    try ring.tryPushBack(2);
    try ring.tryPushBack(3);

    try testing.expect(!ring.isEmpty());
    try testing.expectEqual(@as(?u8, 1), ring.popFront());
    try testing.expectEqual(@as(?u8, 2), ring.popFront());
    try testing.expectEqual(@as(?u8, 3), ring.popFront());
    try testing.expectEqual(@as(?u8, null), ring.popFront());
    try testing.expect(ring.isEmpty());
}

test "unit: spsc.Ring.Static full ring returns error.Full without mutation" {
    const Ring = spsc.Ring.Static(u8, 2);

    var ring: Ring = undefined;
    ring.init();

    try ring.tryPushBack(10);
    try ring.tryPushBack(20);
    try testing.expectError(error.Full, ring.tryPushBack(30));
    // Retry after Full still fails and the ring is unchanged.
    try testing.expectError(error.Full, ring.tryPushBack(40));

    try testing.expectEqual(@as(?u8, 10), ring.popFront());
    try testing.expectEqual(@as(?u8, 20), ring.popFront());
    try testing.expectEqual(@as(?u8, null), ring.popFront());
}

test "unit: spsc.Ring.Static popFront returns null for empty ring" {
    const Ring = spsc.Ring.Static(u32, 8);

    var ring: Ring = undefined;
    ring.init();

    try testing.expectEqual(@as(?u32, null), ring.popFront());
    try testing.expect(ring.isEmpty());
}

test "unit: spsc.Ring.Static wraparound preserves FIFO order" {
    const Ring = spsc.Ring.Static(u16, 4);

    var ring: Ring = undefined;
    ring.init();

    // Push 4, pop 2 to advance head, then push 2 more to force wraparound.
    try ring.tryPushBack(1);
    try ring.tryPushBack(2);
    try ring.tryPushBack(3);
    try ring.tryPushBack(4);
    try testing.expectError(error.Full, ring.tryPushBack(99));

    try testing.expectEqual(@as(?u16, 1), ring.popFront());
    try testing.expectEqual(@as(?u16, 2), ring.popFront());

    try ring.tryPushBack(5);
    try ring.tryPushBack(6);
    try testing.expectError(error.Full, ring.tryPushBack(99));

    try testing.expectEqual(@as(?u16, 3), ring.popFront());
    try testing.expectEqual(@as(?u16, 4), ring.popFront());
    try testing.expectEqual(@as(?u16, 5), ring.popFront());
    try testing.expectEqual(@as(?u16, 6), ring.popFront());
    try testing.expectEqual(@as(?u16, null), ring.popFront());
}

test "unit: spsc.Ring.Static drain-then-refill exercises head-advance path" {
    const Ring = spsc.Ring.Static(u8, 4);

    var ring: Ring = undefined;
    ring.init();

    var cycle: usize = 0;
    while (cycle < 6) : (cycle += 1) {
        try ring.tryPushBack(0);
        try ring.tryPushBack(1);
        try ring.tryPushBack(2);
        try ring.tryPushBack(3);
        try testing.expectError(error.Full, ring.tryPushBack(99));

        try testing.expectEqual(@as(?u8, 0), ring.popFront());
        try testing.expectEqual(@as(?u8, 1), ring.popFront());
        try testing.expectEqual(@as(?u8, 2), ring.popFront());
        try testing.expectEqual(@as(?u8, 3), ring.popFront());
        try testing.expectEqual(@as(?u8, null), ring.popFront());
    }
}

test "unit: spsc.Ring.Bounded borrows caller slot storage without allocation" {
    const Ring = spsc.Ring.Bounded(u8);

    var slots: [4]Ring.Slot = undefined;
    var ring: Ring = undefined;
    ring.init(slots[0..]);

    try testing.expectEqual(@as(usize, 4), ring.capacity());
    try testing.expect(ring.isEmpty());

    try ring.tryPushBack(1);
    try ring.tryPushBack(2);
    try ring.tryPushBack(3);
    try ring.tryPushBack(4);
    try testing.expectError(error.Full, ring.tryPushBack(5));

    try testing.expectEqual(@as(?u8, 1), ring.popFront());
    try ring.tryPushBack(5);

    try testing.expectEqual(@as(?u8, 2), ring.popFront());
    try testing.expectEqual(@as(?u8, 3), ring.popFront());
    try testing.expectEqual(@as(?u8, 4), ring.popFront());
    try testing.expectEqual(@as(?u8, 5), ring.popFront());
    try testing.expectEqual(@as(?u8, null), ring.popFront());
    try testing.expect(ring.isEmpty());
    ring.assertValid();
}

test "unit: spsc.Ring.Static capacity-1 ring alternates push/pop" {
    const Ring = spsc.Ring.Static(u8, 1);

    var ring: Ring = undefined;
    ring.init();

    try testing.expectEqual(@as(usize, 1), ring.capacity());

    var i: u8 = 0;
    while (i < 8) : (i += 1) {
        try ring.tryPushBack(i);
        try testing.expectError(error.Full, ring.tryPushBack(0xff));
        try testing.expectEqual(@as(?u8, i), ring.popFront());
        try testing.expectEqual(@as(?u8, null), ring.popFront());
    }
}

test "contract: spsc.Ring.Static head and tail live on distinct cache lines" {
    const Ring = spsc.Ring.Static(u32, 8);
    const head_offset = @offsetOf(Ring, "head");
    const tail_offset = @offsetOf(Ring, "tail");
    const line = std.atomic.cache_line;

    try testing.expect(head_offset % line == 0);
    try testing.expect(tail_offset % line == 0);
    const gap = if (tail_offset > head_offset)
        tail_offset - head_offset
    else
        head_offset - tail_offset;
    try testing.expect(gap >= line);
}

test "contract: spsc.Ring.Bounded head and tail live on distinct cache lines" {
    const Ring = spsc.Ring.Bounded(u32);
    const head_offset = @offsetOf(Ring, "head");
    const tail_offset = @offsetOf(Ring, "tail");
    const line = std.atomic.cache_line;

    try testing.expect(head_offset % line == 0);
    try testing.expect(tail_offset % line == 0);
    const gap = if (tail_offset > head_offset)
        tail_offset - head_offset
    else
        head_offset - tail_offset;
    try testing.expect(gap >= line);
}

test "contract: spsc.Ring exposes Bounded(T).Slot for caller storage" {
    const Ring = spsc.Ring.Bounded(u64);
    // Slot must be a concrete type that callers can allocate.
    comptime std.debug.assert(@sizeOf(Ring.Slot) >= @sizeOf(u64));
    var slots: [2]Ring.Slot = undefined;
    var ring: Ring = undefined;
    ring.init(slots[0..]);
    try testing.expectEqual(@as(usize, 2), ring.capacity());
    // Compile-time rejections (documented in src/concurrent/spsc/ring.zig):
    //   - `Ring.Static(T, 0)` -> non-power-of-two capacity @compileError
    //   - `Ring.Static(T, 3)` -> non-power-of-two capacity @compileError
    //   - `Ring.Static(struct {}, 4)` or `Ring.Bounded(struct {})` ->
    //     zero-sized element type @compileError
}

test "model: spsc.Ring.Static matches naive FIFO reference across randomized sequences" {
    const capacities = [_]usize{ 1, 2, 4, 16 };
    inline for (capacities) |cap| {
        try runModel(cap);
    }
}

test "model: spsc.Ring.Bounded matches naive FIFO reference across randomized sequences" {
    const capacities = [_]usize{ 1, 2, 4, 16 };
    inline for (capacities) |cap| {
        try runModelBounded(cap);
    }
}

fn runModel(comptime capacity_items: usize) !void {
    const Ring = spsc.Ring.Static(u32, capacity_items);

    var ring: Ring = undefined;
    ring.init();

    // Naive FIFO reference: a fixed-size buffer with an explicit length,
    // acting as a queue via shift-on-pop.
    var reference_buf: [capacity_items]u32 = undefined;
    var reference_len: usize = 0;

    var prng = std.Random.DefaultPrng.init(0x5EED_5C51 ^ capacity_items);
    const rand = prng.random();

    var next_value: u32 = 0;
    var op: usize = 0;
    while (op < 4096) : (op += 1) {
        const push = rand.boolean();
        if (push) {
            const value = next_value;
            if (reference_len == capacity_items) {
                try testing.expectError(error.Full, ring.tryPushBack(value));
            } else {
                try ring.tryPushBack(value);
                reference_buf[reference_len] = value;
                reference_len += 1;
                next_value += 1;
            }
        } else {
            const observed = ring.popFront();
            if (reference_len == 0) {
                try testing.expectEqual(@as(?u32, null), observed);
            } else {
                const expected = reference_buf[0];
                var i: usize = 1;
                while (i < reference_len) : (i += 1) {
                    reference_buf[i - 1] = reference_buf[i];
                }
                reference_len -= 1;
                try testing.expectEqual(@as(?u32, expected), observed);
            }
        }
    }

    // Drain both and verify equality of the remaining tail.
    var i: usize = 0;
    while (i < reference_len) : (i += 1) {
        try testing.expectEqual(@as(?u32, reference_buf[i]), ring.popFront());
    }
    try testing.expectEqual(@as(?u32, null), ring.popFront());
    try testing.expect(ring.isEmpty());
    ring.assertValid();
}

fn runModelBounded(comptime capacity_items: usize) !void {
    const Ring = spsc.Ring.Bounded(u32);

    var slot_storage: [capacity_items]Ring.Slot = undefined;
    var ring: Ring = undefined;
    ring.init(slot_storage[0..]);

    // Naive FIFO reference: a fixed-size buffer with an explicit length,
    // acting as a queue via shift-on-pop.
    var reference_buf: [capacity_items]u32 = undefined;
    var reference_len: usize = 0;

    var prng = std.Random.DefaultPrng.init(0x5EED_5C51 ^ capacity_items);
    const rand = prng.random();

    var next_value: u32 = 0;
    var op: usize = 0;
    while (op < 4096) : (op += 1) {
        const push = rand.boolean();
        if (push) {
            const value = next_value;
            if (reference_len == capacity_items) {
                try testing.expectError(error.Full, ring.tryPushBack(value));
            } else {
                try ring.tryPushBack(value);
                reference_buf[reference_len] = value;
                reference_len += 1;
                next_value += 1;
            }
        } else {
            const observed = ring.popFront();
            if (reference_len == 0) {
                try testing.expectEqual(@as(?u32, null), observed);
            } else {
                const expected = reference_buf[0];
                var i: usize = 1;
                while (i < reference_len) : (i += 1) {
                    reference_buf[i - 1] = reference_buf[i];
                }
                reference_len -= 1;
                try testing.expectEqual(@as(?u32, expected), observed);
            }
        }
    }

    // Drain both and verify equality of the remaining tail.
    var i: usize = 0;
    while (i < reference_len) : (i += 1) {
        try testing.expectEqual(@as(?u32, reference_buf[i]), ring.popFront());
    }
    try testing.expectEqual(@as(?u32, null), ring.popFront());
    try testing.expect(ring.isEmpty());
    ring.assertValid();
}

const Stress = struct {
    // Item count large enough to force many wraparounds through a small ring.
    const items: u32 = 10_000;

    const Item = u32;

    fn RingType(comptime capacity_items: usize) type {
        return spsc.Ring.Static(Item, capacity_items);
    }

    fn ProducerCtx(comptime capacity_items: usize) type {
        return struct {
            ring: *RingType(capacity_items),
            full_count: *std.atomic.Value(usize),
            done: *std.atomic.Value(bool),
        };
    }

    fn producerMain(comptime capacity_items: usize, ctx: *ProducerCtx(capacity_items)) void {
        var seq: u32 = 0;
        while (seq < items) {
            ctx.ring.tryPushBack(seq) catch |err| switch (err) {
                error.Full => {
                    _ = ctx.full_count.fetchAdd(1, .monotonic);
                    std.Thread.yield() catch {};
                    continue;
                },
            };
            seq += 1;
        }
        ctx.done.store(true, .release);
    }

    fn runOne(comptime capacity_items: usize) !void {
        var ring: RingType(capacity_items) = undefined;
        ring.init();

        var full_count = std.atomic.Value(usize).init(0);
        var done = std.atomic.Value(bool).init(false);

        var ctx: ProducerCtx(capacity_items) = .{
            .ring = &ring,
            .full_count = &full_count,
            .done = &done,
        };

        const thread = try std.Thread.spawn(.{}, producerMain, .{ capacity_items, &ctx });

        var expected: u32 = 0;
        while (expected < items) {
            if (ring.popFront()) |value| {
                try testing.expectEqual(expected, value);
                expected += 1;
            } else {
                std.Thread.yield() catch {};
            }
        }

        thread.join();

        try testing.expect(done.load(.acquire));
        try testing.expectEqual(@as(?Item, null), ring.popFront());
        try testing.expect(ring.isEmpty());
        // full_count is observational; the test harness retries on Full.
        _ = full_count.load(.monotonic);
    }

    const BoundedRing = spsc.Ring.Bounded(Item);

    const BoundedCtx = struct {
        ring: *BoundedRing,
        full_count: *std.atomic.Value(usize),
        done: *std.atomic.Value(bool),
    };

    fn boundedProducerMain(ctx: *BoundedCtx) void {
        var seq: u32 = 0;
        while (seq < items) {
            ctx.ring.tryPushBack(seq) catch |err| switch (err) {
                error.Full => {
                    _ = ctx.full_count.fetchAdd(1, .monotonic);
                    std.Thread.yield() catch {};
                    continue;
                },
            };
            seq += 1;
        }
        ctx.done.store(true, .release);
    }

    fn runOneBounded(comptime capacity_items: usize) !void {
        var slots: [capacity_items]BoundedRing.Slot = undefined;
        var ring: BoundedRing = undefined;
        ring.init(slots[0..]);

        var full_count = std.atomic.Value(usize).init(0);
        var done = std.atomic.Value(bool).init(false);

        var ctx: BoundedCtx = .{
            .ring = &ring,
            .full_count = &full_count,
            .done = &done,
        };

        const thread = try std.Thread.spawn(.{}, boundedProducerMain, .{&ctx});

        var expected: u32 = 0;
        while (expected < items) {
            if (ring.popFront()) |value| {
                try testing.expectEqual(expected, value);
                expected += 1;
            } else {
                std.Thread.yield() catch {};
            }
        }

        thread.join();

        try testing.expect(done.load(.acquire));
        try testing.expectEqual(@as(?Item, null), ring.popFront());
        try testing.expect(ring.isEmpty());
        _ = full_count.load(.monotonic);
    }
};

test "stress: spsc.Ring.Static single-producer/single-consumer round-trip in FIFO order" {
    if (builtin.single_threaded) return error.SkipZigTest;

    // Smallest useful capacity forces heavy wraparound.
    try Stress.runOne(2);
    // Larger capacity exercises the wraparound path multiple times too.
    try Stress.runOne(64);
}

test "stress: spsc.Ring.Bounded single-producer/single-consumer round-trip in FIFO order" {
    if (builtin.single_threaded) return error.SkipZigTest;

    try Stress.runOneBounded(2);
    try Stress.runOneBounded(64);
}
