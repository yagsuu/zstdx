const builtin = @import("builtin");
const std = @import("std");

const stdx = @import("stdx");

const mpsc = stdx.concurrent.mpsc;
const testing = std.testing;

const Integration = struct {
    const producer_count = 4;
    const items_per_producer = 256;
    const capacity = 64;
    const item_count = producer_count * items_per_producer;

    const Item = struct {
        producer: u8,
        seq: u16,
    };

    const Ring = mpsc.Ring.Static(Item, capacity);

    const ProducerContext = struct {
        ring: *Ring,
        producer: u8,
        stop: *std.atomic.Value(bool),
    };

    fn producerMain(context: *ProducerContext) void {
        var seq: u16 = 0;
        while (seq < items_per_producer) : (seq += 1) {
            const item = Item{
                .producer = context.producer,
                .seq = seq,
            };

            while (true) {
                if (context.stop.load(.monotonic)) {
                    return;
                }
                context.ring.tryPushBack(item) catch |err| switch (err) {
                    error.Full, error.Contended => {
                        std.Thread.yield() catch {};
                        continue;
                    },
                };
                break;
            }
        }
    }
};

test "threaded: mpsc.Ring.Static delivers all producer items exactly once in per-producer order" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var ring: Integration.Ring = undefined;
    ring.init();

    var stop = std.atomic.Value(bool).init(false);
    var contexts: [Integration.producer_count]Integration.ProducerContext = undefined;
    var threads: [Integration.producer_count]std.Thread = undefined;
    var spawned: usize = 0;
    defer {
        stop.store(true, .monotonic);
        for (threads[0..spawned]) |thread| {
            thread.join();
        }
    }

    for (&contexts, 0..) |*context, producer_index| {
        context.* = .{
            .ring = &ring,
            .producer = @intCast(producer_index),
            .stop = &stop,
        };
        threads[producer_index] = try std.Thread.spawn(.{}, Integration.producerMain, .{context});
        spawned += 1;
    }

    var expected: [Integration.producer_count]u16 = [_]u16{0} ** Integration.producer_count;
    var popped: usize = 0;
    while (popped < Integration.item_count) {
        if (ring.popFront()) |item| {
            try testing.expect(item.producer < Integration.producer_count);
            const producer_index: usize = @intCast(item.producer);
            try testing.expect(expected[producer_index] < Integration.items_per_producer);
            try testing.expectEqual(expected[producer_index], item.seq);

            expected[producer_index] += 1;
            popped += 1;
        } else {
            std.Thread.yield() catch {};
        }
    }

    for (threads[0..spawned]) |thread| {
        thread.join();
    }
    spawned = 0;

    for (expected) |seq| {
        try testing.expectEqual(@as(u16, Integration.items_per_producer), seq);
    }

    const remaining = ring.popFront();

    try testing.expectEqual(@as(?Integration.Item, null), remaining);
    try testing.expect(ring.isEmpty());
    try testing.expect(ring.isValid());
}
