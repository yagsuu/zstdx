const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const spsc = stdx.concurrent.spsc;
const testing = std.testing;

const items: u32 = 10_000;

test "integration: spsc.Ring.Static transfers every sequence value between threads" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    inline for (.{ 2, 64 }) |count| {
        var ring: spsc.Ring.Static(u32, count) = undefined;
        ring.init();

        try runThreaded(&ring);
    }
}

test "integration: spsc.Ring.Bounded transfers every sequence value between threads" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    const Ring = spsc.Ring.Bounded(u32);
    inline for (.{ 2, 64 }) |count| {
        var slots: [count]Ring.Slot = undefined;
        var ring: Ring = undefined;
        ring.init(&slots);

        try runThreaded(&ring);
    }
}

fn runThreaded(ring: anytype) !void {
    {
        var stop = std.atomic.Value(bool).init(false);
        const thread = try std.Thread.spawn(.{}, producerMain, .{ ring, &stop });
        defer {
            stop.store(true, .monotonic);
            thread.join();
        }

        var expected: u32 = 0;
        while (expected < items) {
            if (ring.popFront()) |value| {
                try testing.expectEqual(expected, value);
                expected += 1;
            } else {
                std.Thread.yield() catch {};
            }
        }
    }

    const remaining = ring.popFront();

    try testing.expectEqual(@as(?u32, null), remaining);
    try testing.expect(ring.isEmpty());
    try testing.expect(ring.isValid());
}

fn producerMain(ring: anytype, stop: *std.atomic.Value(bool)) void {
    var sequence: u32 = 0;
    while (sequence < items and !stop.load(.monotonic)) {
        ring.tryPushBack(sequence) catch |err| switch (err) {
            error.Full => {
                std.Thread.yield() catch {};
                continue;
            },
        };
        sequence += 1;
    }
}
