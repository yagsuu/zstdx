const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const PerCpu = @import("stdx").cpu.PerCpu;

const count = 4;
const iterations = 5_000;
const Values = PerCpu.Static(u64, count);

fn increment(values: *Values, index: usize) void {
    const value = values.getMut(index);
    for (0..iterations) |_| {
        value.* += 1;
    }
}

test "threads independently update disjoint per-CPU payloads" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }
    var values = Values.init(0);
    var threads: [count]std.Thread = undefined;
    var started: usize = 0;
    defer {
        for (threads[0..started]) |thread| {
            thread.join();
        }
    }
    for (0..count) |index| {
        threads[index] = try std.Thread.spawn(.{}, increment, .{ &values, index });
        started += 1;
    }
    for (threads) |thread| {
        thread.join();
    }
    started = 0;

    for (0..count) |index| {
        try testing.expectEqual(@as(u64, iterations), values.get(index).*);
    }
}
