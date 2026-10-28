const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const qsbr = stdx.concurrent.qsbr;
const Participant = qsbr.Participant;
const testing = std.testing;

test "stress: concurrent beginGracePeriod returns unique monotonic generations" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    const Domain = qsbr.Domain.Static(1);
    const writer_count: usize = 4;
    const iterations: usize = 256;
    const total = writer_count * iterations;
    const Ctx = struct {
        domain: *Domain,
        out: []u64,
        stop: *std.atomic.Value(bool),

        fn run(ctx: @This()) void {
            for (ctx.out) |*generation| {
                if (ctx.stop.load(.acquire)) {
                    return;
                }
                generation.* = ctx.domain.beginGracePeriod().generation();
            }
        }
    };

    var domain = Domain.init();
    var generations: [total]u64 = undefined;
    var stop = std.atomic.Value(bool).init(false);
    var threads: [writer_count]std.Thread = undefined;
    var started: usize = 0;
    defer {
        stop.store(true, .release);
        for (threads[0..started]) |thread| {
            thread.join();
        }
    }

    while (started < writer_count) : (started += 1) {
        const start = started * iterations;
        threads[started] = try std.Thread.spawn(.{}, Ctx.run, .{Ctx{
            .domain = &domain,
            .out = generations[start .. start + iterations],
            .stop = &stop,
        }});
    }

    for (threads[0..started]) |thread| {
        thread.join();
    }
    started = 0;

    var seen: [total + 1]bool = [_]bool{false} ** (total + 1);
    var writer: usize = 0;
    while (writer < writer_count) : (writer += 1) {
        const start = writer * iterations;
        var prior: u64 = 0;
        for (generations[start .. start + iterations]) |generation| {
            try testing.expect(generation > prior);
            try testing.expect(generation >= 1);
            try testing.expect(generation <= @as(u64, @intCast(total)));
            const index: usize = @intCast(generation);
            try testing.expect(!seen[index]);
            seen[index] = true;
            prior = generation;
        }
    }
    for (seen[1..]) |observed| {
        try testing.expect(observed);
    }
    try testing.expectEqual(@as(u64, @intCast(total)), domain.generation());
}

test "stress: concurrent quiescent on distinct slots lets writer complete rounds" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    const Domain = qsbr.Domain.Static(4);
    const participant_count: usize = 4;
    const rounds: usize = 128;
    const Ctx = struct {
        domain: *Domain,
        token: Participant,
        stop: *std.atomic.Value(bool),

        fn run(ctx: @This()) void {
            var last_generation: u64 = 0;
            var report_count: usize = 0;
            while (report_count < rounds) {
                if (ctx.stop.load(.acquire)) {
                    return;
                }
                const observed = ctx.domain.generation();
                if (observed > last_generation) {
                    ctx.domain.quiescent(ctx.token);
                    last_generation = observed;
                    report_count += 1;
                } else {
                    std.atomic.spinLoopHint();
                }
            }
        }
    };

    var domain = Domain.init();
    var stop = std.atomic.Value(bool).init(false);
    var threads: [participant_count]std.Thread = undefined;
    var started: usize = 0;
    defer {
        stop.store(true, .release);
        for (threads[0..started]) |thread| {
            thread.join();
        }
    }

    while (started < participant_count) : (started += 1) {
        const token = domain.participant(started);
        domain.online(token);
        threads[started] = try std.Thread.spawn(.{}, Ctx.run, .{Ctx{
            .domain = &domain,
            .token = token,
            .stop = &stop,
        }});
    }

    var round: u64 = 0;
    while (round < rounds) : (round += 1) {
        const period = domain.beginGracePeriod();
        var polls: usize = 0;
        while (!domain.isComplete(period)) : (polls += 1) {
            if (polls > 10_000_000) {
                return error.TestUnexpectedResult;
            }
            if ((polls & 0x3f) == 0) {
                std.Thread.yield() catch {};
            }
            std.atomic.spinLoopHint();
        }

        try testing.expectEqual(round + 1, period.generation());
        try testing.expect(domain.isComplete(period));
    }

    for (threads[0..started]) |thread| {
        thread.join();
    }
    started = 0;

    try testing.expectEqual(@as(u64, @intCast(rounds)), domain.generation());
}

test "model: quiescent after observing grace generation completes through acquire scan" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    const Domain = qsbr.Domain.Static(1);
    const Ctx = struct {
        domain: *Domain,
        token: Participant,
        target: u64,
        stop: *std.atomic.Value(bool),

        fn run(ctx: @This()) void {
            while (ctx.domain.generation() < ctx.target) {
                if (ctx.stop.load(.acquire)) {
                    return;
                }
                std.atomic.spinLoopHint();
            }
            ctx.domain.quiescent(ctx.token);
        }
    };

    var domain = Domain.init();
    const token = domain.participant(0);
    domain.online(token);
    var stop = std.atomic.Value(bool).init(false);

    const thread = try std.Thread.spawn(.{}, Ctx.run, .{Ctx{
        .domain = &domain,
        .token = token,
        .target = 1,
        .stop = &stop,
    }});
    defer {
        stop.store(true, .release);
        thread.join();
    }

    const period = domain.beginGracePeriod();
    var polls: usize = 0;
    while (!domain.isComplete(period)) : (polls += 1) {
        if (polls > 10_000_000) {
            return error.TestUnexpectedResult;
        }
        if ((polls & 0x3f) == 0) {
            std.Thread.yield() catch {};
        }
        std.atomic.spinLoopHint();
    }

    try testing.expectEqual(@as(u64, 1), period.generation());
    try testing.expectEqual(@as(u64, 1), domain.generation());
    try testing.expect(domain.isComplete(period));
}
