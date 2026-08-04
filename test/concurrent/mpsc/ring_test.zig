//! MPSC ring contract tests. See `docs/specs/concurrent/mpsc-ring.md`.

const std = @import("std");

const stdx = @import("stdx");

const mpsc = stdx.concurrent.mpsc;
const testing = std.testing;

test "unit: mpsc.Ring.Static initializes in place, enforces capacity, and drains FIFO" {
    const Ring = mpsc.Ring.Static(u8, 2);

    var ring: Ring = undefined;
    ring.init();

    try testing.expectEqual(@as(usize, 2), ring.capacity());
    try testing.expect(ring.isEmpty());

    try ring.tryPushBack(1);
    try ring.tryPushBack(2);
    try testing.expectError(error.Full, ring.tryPushBack(3));

    try testing.expectEqual(@as(?u8, 1), ring.popFront());
    try testing.expectEqual(@as(?u8, 2), ring.popFront());
    try testing.expectEqual(@as(?u8, null), ring.popFront());
    try testing.expect(ring.isEmpty());
}

test "unit: mpsc.Ring.Static preserves FIFO across wraparound" {
    const Ring = mpsc.Ring.Static(u8, 2);

    var ring: Ring = undefined;
    ring.init();

    try ring.tryPushBack(1);
    try testing.expectEqual(@as(?u8, 1), ring.popFront());
    try ring.tryPushBack(2);
    try ring.tryPushBack(3);

    try testing.expectEqual(@as(?u8, 2), ring.popFront());
    try testing.expectEqual(@as(?u8, 3), ring.popFront());
    try testing.expectEqual(@as(?u8, null), ring.popFront());
}

test "unit: mpsc.Ring.Bounded enforces capacity and preserves FIFO across wraparound" {
    const Ring = mpsc.Ring.Bounded(u8);

    var slots: [2]Ring.Slot = undefined;
    var ring: Ring = undefined;
    ring.init(slots[0..]);

    try testing.expectEqual(@as(usize, 2), ring.capacity());
    try testing.expect(ring.isEmpty());

    try ring.tryPushBack(1);
    try ring.tryPushBack(2);
    try testing.expectError(error.Full, ring.tryPushBack(3));

    try testing.expectEqual(@as(?u8, 1), ring.popFront());
    try ring.tryPushBack(3);

    try testing.expectEqual(@as(?u8, 2), ring.popFront());
    try testing.expectEqual(@as(?u8, 3), ring.popFront());
    try testing.expectEqual(@as(?u8, null), ring.popFront());
    try testing.expect(ring.isEmpty());
}

const Stress = struct {
    const producer_count = 4;
    const items_per_producer = 256;
    const capacity = 64;
    const produced_total = producer_count * items_per_producer;

    const Item = struct {
        producer: u8,
        seq: u16,
    };

    const Ring = mpsc.Ring.Static(Item, capacity);

    const ProducerContext = struct {
        ring: *Ring,
        producer: u8,
        pushed_count: *std.atomic.Value(usize),
        full_count: *std.atomic.Value(usize),
        contended_count: *std.atomic.Value(usize),
    };

    fn producerMain(context: *ProducerContext) void {
        var seq: u16 = 0;
        while (seq < items_per_producer) : (seq += 1) {
            const item = Item{
                .producer = context.producer,
                .seq = seq,
            };

            while (true) {
                context.ring.tryPushBack(item) catch |err| switch (err) {
                    error.Full => {
                        _ = context.full_count.fetchAdd(1, .monotonic);
                        std.Thread.yield() catch {};
                        continue;
                    },
                    error.Contended => {
                        _ = context.contended_count.fetchAdd(1, .monotonic);
                        std.Thread.yield() catch {};
                        continue;
                    },
                };

                _ = context.pushed_count.fetchAdd(1, .release);
                break;
            }
        }
    }
};

test "threaded: mpsc.Ring.Static delivers all producer items exactly once in per-producer order" {
    var ring: Stress.Ring = undefined;
    ring.init();

    var pushed_count = std.atomic.Value(usize).init(0);
    var full_count = std.atomic.Value(usize).init(0);
    var contended_count = std.atomic.Value(usize).init(0);

    var contexts: [Stress.producer_count]Stress.ProducerContext = undefined;
    var threads: [Stress.producer_count]std.Thread = undefined;

    for (&contexts, 0..) |*context, producer_index| {
        context.* = .{
            .ring = &ring,
            .producer = @intCast(producer_index),
            .pushed_count = &pushed_count,
            .full_count = &full_count,
            .contended_count = &contended_count,
        };
        threads[producer_index] = try std.Thread.spawn(.{}, Stress.producerMain, .{context});
    }

    var expected: [Stress.producer_count]u16 = [_]u16{0} ** Stress.producer_count;
    var popped_count: usize = 0;
    while (popped_count < Stress.produced_total) {
        if (ring.popFront()) |item| {
            try testing.expect(item.producer < Stress.producer_count);
            const producer_index: usize = @intCast(item.producer);
            try testing.expectEqual(expected[producer_index], item.seq);
            expected[producer_index] += 1;
            popped_count += 1;
        } else {
            std.Thread.yield() catch {};
        }
    }

    for (threads) |thread| {
        thread.join();
    }

    try testing.expectEqual(@as(usize, Stress.produced_total), popped_count);
    try testing.expectEqual(@as(usize, Stress.produced_total), pushed_count.load(.acquire));
    for (expected) |seq| {
        try testing.expectEqual(@as(u16, Stress.items_per_producer), seq);
    }
    try testing.expectEqual(@as(?Stress.Item, null), ring.popFront());
}
