const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");

const testing = std.testing;
const Barrier = stdx.sync.Rendezvous(stdx.sync.spin.Backend).Bounded;

test "bounded rendezvous publishes per-thread payload across generations" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    const parties = 4;
    const rounds = 8;
    const Shared = struct {
        barrier: Barrier = Barrier.init(parties, .{}),
        gate: std.atomic.Value(enum(u8) { waiting, start, abort }) = .init(.waiting),
        payload: [parties]usize = @splat(0),
        failed: [parties]bool = @splat(false),

        fn run(shared: *@This(), id: usize) void {
            while (true) {
                switch (shared.gate.load(.acquire)) {
                    .waiting => std.atomic.spinLoopHint(),
                    .start => break,
                    .abort => return,
                }
            }

            var failed = false;
            for (1..rounds + 1) |round| {
                shared.payload[id] = round * parties + id;
                shared.barrier.arrive() catch unreachable;

                for (shared.payload, 0..) |value, writer| {
                    failed = failed or value != round * parties + writer;
                }

                // all readers finish before the next round writes
                shared.barrier.arrive() catch unreachable;
            }
            shared.failed[id] = failed;
        }
    };

    var shared: Shared = .{};
    var threads: [parties]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer {
        shared.gate.store(.abort, .release);
        for (threads[0..spawned]) |thread| {
            thread.join();
        }
    }
    for (&threads, 0..) |*thread, id| {
        thread.* = try std.Thread.spawn(.{}, Shared.run, .{ &shared, id });
        spawned += 1;
    }
    shared.gate.store(.start, .release);
    for (threads) |thread| {
        thread.join();
    }
    spawned = 0;

    for (shared.failed) |failed| {
        try testing.expect(!failed);
    }
    try testing.expectEqual(@as(u32, parties), shared.barrier.capacity());
    try testing.expectEqual(@as(u32, parties), shared.barrier.pending());
    try testing.expectEqual(@as(u32, rounds * 2), shared.barrier.generation());
}
