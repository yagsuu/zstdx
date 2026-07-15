//! QSBR contract tests. Spec: docs/specs/concurrent/qsbr.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const qsbr = stdx.concurrent.qsbr;
const GracePeriod = qsbr.GracePeriod;
const Participant = qsbr.Participant;
const testing = std.testing;
const offline_bit: u64 = @as(u64, 1) << 63;
const generation_mask: u64 = offline_bit - 1;

// Compile-fail and assert-trap contracts are guarded in src/concurrent/qsbr.zig.
// The current test runner has no @compileError or crash harness.

test "unit: Static init exposes capacity generation and offline participants" {
    const Domain = qsbr.Domain.Static(4);
    var domain = Domain.init();

    try testing.expectEqual(@as(usize, 4), Domain.participant_capacity);
    try testing.expectEqual(@as(usize, 4), domain.capacity());
    try testing.expectEqual(@as(u64, 0), domain.generation());

    var index: usize = 0;
    while (index < domain.capacity()) : (index += 1) {
        try expectSlotOffline(&domain.slots[index]);
    }
}

test "unit: Bounded.wrap borrows capacity resets generation and marks slots offline" {
    const Bounded = qsbr.Domain.Bounded;
    var slots: [3]Bounded.Slot = undefined;
    var domain = Bounded.wrap(slots[0..]);

    const p0 = domain.participant(0);
    domain.online(p0);
    _ = domain.beginGracePeriod();

    domain = Bounded.wrap(slots[0..]);

    try testing.expectEqual(@as(usize, 3), domain.capacity());
    try testing.expectEqual(@as(u64, 0), domain.generation());
    for (&slots) |*slot| {
        try expectSlotOffline(slot);
    }
}

test "unit: Participant.index and GracePeriod.generation expose token values" {
    const Domain = qsbr.Domain.Static(3);
    var domain = Domain.init();

    const participant = domain.participant(2);
    const grace_period = domain.beginGracePeriod();

    try testing.expectEqual(@as(u32, 2), participant.index());
    try testing.expectEqual(@as(u64, 1), grace_period.generation());
}

test "unit: all-offline domain completes every new grace period immediately" {
    const Domain = qsbr.Domain.Static(3);
    var domain = Domain.init();

    const first = domain.beginGracePeriod();
    const second = domain.beginGracePeriod();

    try testing.expect(domain.isComplete(first));
    try testing.expect(domain.isComplete(second));
    try testing.expectEqual(@as(u64, 2), domain.generation());
}

test "unit: online participant blocks a grace period until quiescent" {
    const Domain = qsbr.Domain.Static(2);
    var domain = Domain.init();
    const participant = domain.participant(0);

    domain.online(participant);
    const grace_period = domain.beginGracePeriod();

    try testing.expect(!domain.isComplete(grace_period));
    domain.quiescent(participant);
    try testing.expect(domain.isComplete(grace_period));
}

test "unit: offline participant unblocks current and future grace periods" {
    const Domain = qsbr.Domain.Static(2);
    var domain = Domain.init();
    const participant = domain.participant(0);

    domain.online(participant);
    const current = domain.beginGracePeriod();
    try testing.expect(!domain.isComplete(current));

    domain.offline(participant);
    try testing.expect(domain.isComplete(current));

    const future = domain.beginGracePeriod();
    try testing.expect(domain.isComplete(future));
}

test "unit: online after grace-period start does not block that grace period" {
    const Domain = qsbr.Domain.Static(1);
    var domain = Domain.init();
    const participant = domain.participant(0);

    const already_started = domain.beginGracePeriod();
    domain.online(participant);

    try testing.expect(domain.isComplete(already_started));

    const after_online = domain.beginGracePeriod();
    try testing.expect(!domain.isComplete(after_online));
}

test "unit: multiple participants must each report quiescent or offline" {
    const Domain = qsbr.Domain.Static(3);
    var domain = Domain.init();
    const p0 = domain.participant(0);
    const p1 = domain.participant(1);

    domain.online(p0);
    domain.online(p1);
    const grace_period = domain.beginGracePeriod();

    domain.quiescent(p0);
    try testing.expect(!domain.isComplete(grace_period));

    domain.offline(p1);
    try testing.expect(domain.isComplete(grace_period));
}

test "unit: completing a later grace period completes earlier periods" {
    const Domain = qsbr.Domain.Static(1);
    var domain = Domain.init();
    const participant = domain.participant(0);

    domain.online(participant);
    const earlier = domain.beginGracePeriod();
    const later = domain.beginGracePeriod();

    try testing.expect(!domain.isComplete(earlier));
    try testing.expect(!domain.isComplete(later));

    domain.quiescent(participant);

    try testing.expect(domain.isComplete(later));
    try testing.expect(domain.isComplete(earlier));
}

test "unit: capacity-one domain blocks and completes on its only slot" {
    const Domain = qsbr.Domain.Static(1);
    var domain = Domain.init();
    const participant = domain.participant(0);

    domain.online(participant);
    const blocked = domain.beginGracePeriod();
    try testing.expect(!domain.isComplete(blocked));

    domain.quiescent(participant);
    try testing.expect(domain.isComplete(blocked));

    domain.offline(participant);
    const offline_period = domain.beginGracePeriod();
    try testing.expect(domain.isComplete(offline_period));
}

test "unit: repeated offline remains idempotent for a caller-owned slot" {
    const Domain = qsbr.Domain.Static(1);
    var domain = Domain.init();
    const participant = domain.participant(0);

    domain.offline(participant);
    domain.offline(participant);
    try testing.expect(domain.isComplete(domain.beginGracePeriod()));

    domain.online(participant);
    const blocked = domain.beginGracePeriod();
    try testing.expect(!domain.isComplete(blocked));

    domain.offline(participant);
    domain.offline(participant);
    try testing.expect(domain.isComplete(blocked));
}

test "unit: repeated online updates reported generation without nested state" {
    const Domain = qsbr.Domain.Static(1);
    var domain = Domain.init();
    const participant = domain.participant(0);

    domain.online(participant);
    const first = domain.beginGracePeriod();
    try testing.expect(!domain.isComplete(first));

    domain.online(participant);
    try testing.expect(domain.isComplete(first));

    const second = domain.beginGracePeriod();
    try testing.expect(!domain.isComplete(second));

    domain.online(participant);
    try testing.expect(domain.isComplete(second));
}

test "unit: first-only report leaves overlapping later period incomplete" {
    const Domain = qsbr.Domain.Static(1);
    var domain = Domain.init();
    const participant = domain.participant(0);

    domain.online(participant);
    const first = domain.beginGracePeriod();
    domain.quiescent(participant);
    const second = domain.beginGracePeriod();

    try testing.expect(domain.isComplete(first));
    try testing.expect(!domain.isComplete(second));

    domain.quiescent(participant);
    try testing.expect(domain.isComplete(first));
    try testing.expect(domain.isComplete(second));
}

// Runs a deterministic random operation stream against an independent reference model.
test "model: small QSBR domain matches deterministic reference state" {
    try runReferenceModel(3);
}

// Runs contending writers and validates each CAS winner receives a unique generation.
test "stress: concurrent beginGracePeriod returns unique monotonic generations" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const Domain = qsbr.Domain.Static(1);
    const writer_count: usize = 4;
    const iterations: usize = 256;
    const total = writer_count * iterations;
    const Ctx = struct {
        domain: *Domain,
        out: []u64,

        fn run(ctx: @This()) void {
            for (ctx.out) |*generation| {
                generation.* = ctx.domain.beginGracePeriod().generation();
            }
        }
    };

    var domain = Domain.init();
    var generations: [total]u64 = undefined;
    var threads: [writer_count]std.Thread = undefined;

    var writer: usize = 0;
    while (writer < writer_count) : (writer += 1) {
        const start = writer * iterations;
        const end = start + iterations;
        threads[writer] = try std.Thread.spawn(.{}, Ctx.run, .{Ctx{
            .domain = &domain,
            .out = generations[start..end],
        }});
    }

    for (threads) |thread| {
        thread.join();
    }

    var seen: [total + 1]bool = [_]bool{false} ** (total + 1);
    writer = 0;
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

// Runs participant-owned slots concurrently while one writer polls each grace period.
test "stress: concurrent quiescent on distinct slots lets writer complete rounds" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const Domain = qsbr.Domain.Static(4);
    const participant_count: usize = 4;
    const rounds: usize = 128;
    const Ctx = struct {
        domain: *Domain,
        participant: Participant,
        reports: *std.atomic.Value(usize),

        fn run(ctx: @This()) void {
            var last_generation: u64 = 0;
            var report_count: usize = 0;
            while (report_count < rounds) {
                const observed = ctx.domain.generation();
                if (observed > last_generation) {
                    ctx.domain.quiescent(ctx.participant);
                    last_generation = observed;
                    report_count += 1;
                } else {
                    std.atomic.spinLoopHint();
                }
            }
            _ = ctx.reports.fetchAdd(report_count, .release);
        }
    };

    var domain = Domain.init();
    var reports = std.atomic.Value(usize).init(0);
    var threads: [participant_count]std.Thread = undefined;

    var index: usize = 0;
    while (index < participant_count) : (index += 1) {
        const participant = domain.participant(index);
        domain.online(participant);
        threads[index] = try std.Thread.spawn(.{}, Ctx.run, .{Ctx{
            .domain = &domain,
            .participant = participant,
            .reports = &reports,
        }});
    }

    var round: u64 = 0;
    while (round < rounds) : (round += 1) {
        const grace_period = domain.beginGracePeriod();
        var polls: usize = 0;
        while (!domain.isComplete(grace_period)) : (polls += 1) {
            if (polls > 10_000_000) return error.TestUnexpectedResult;
            if ((polls & 0x3f) == 0) std.Thread.yield() catch {};
            std.atomic.spinLoopHint();
        }
    }

    for (threads) |thread| {
        thread.join();
    }

    try testing.expectEqual(@as(u64, @intCast(rounds)), domain.generation());
    try testing.expectEqual(@as(usize, participant_count * rounds), reports.load(.acquire));
}

test "unit: isComplete stays non-blocking false for a stuck participant" {
    const Domain = qsbr.Domain.Static(1);
    var domain = Domain.init();
    const participant = domain.participant(0);

    domain.online(participant);
    const grace_period = domain.beginGracePeriod();

    var poll: usize = 0;
    while (poll < 1024) : (poll += 1) {
        try testing.expect(!domain.isComplete(grace_period));
    }
}

// Worker reports after observing the target; writer waits through acquire scans.
test "model: quiescent after observing grace generation completes through acquire scan" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const Domain = qsbr.Domain.Static(1);
    const Ctx = struct {
        domain: *Domain,
        participant: Participant,
        target: u64,

        fn run(ctx: @This()) void {
            while (ctx.domain.generation() < ctx.target) {
                std.atomic.spinLoopHint();
            }
            ctx.domain.quiescent(ctx.participant);
        }
    };

    var domain = Domain.init();
    const participant = domain.participant(0);
    domain.online(participant);

    const grace_period = domain.beginGracePeriod();
    const thread = try std.Thread.spawn(.{}, Ctx.run, .{Ctx{
        .domain = &domain,
        .participant = participant,
        .target = grace_period.generation(),
    }});

    var polls: usize = 0;
    while (!domain.isComplete(grace_period)) : (polls += 1) {
        if (polls > 10_000_000) return error.TestUnexpectedResult;
        if ((polls & 0x3f) == 0) std.Thread.yield() catch {};
        std.atomic.spinLoopHint();
    }
    thread.join();

    try testing.expect(domain.isComplete(grace_period));
}

test "model: quiescent before begin does not complete the next generation" {
    const Domain = qsbr.Domain.Static(1);
    var domain = Domain.init();
    const participant = domain.participant(0);

    domain.online(participant);
    domain.quiescent(participant);
    const grace_period = domain.beginGracePeriod();

    try testing.expect(!domain.isComplete(grace_period));

    domain.quiescent(participant);
    try testing.expect(domain.isComplete(grace_period));
}

// Compares public Slot aliases with the required cache-padded atomic word type.
test "contract: Slot types are cache-padded atomic u64 words" {
    const Static = qsbr.Domain.Static(2);
    const Bounded = qsbr.Domain.Bounded;
    const ExpectedSlot = stdx.mem.CachePad(std.atomic.Value(u64));

    try testing.expect(Static.Slot == ExpectedSlot);
    try testing.expect(Bounded.Slot == ExpectedSlot);
    try testing.expectEqual(@sizeOf(ExpectedSlot), @sizeOf(Static.Slot));
    try testing.expectEqual(@sizeOf(ExpectedSlot), @sizeOf(Bounded.Slot));
    try testing.expectEqual(@as(usize, std.atomic.cache_line), @alignOf(Static.Slot));
    try testing.expectEqual(@as(usize, std.atomic.cache_line), @alignOf(Bounded.Slot));
}

// Inspects field and element addresses to confirm static slot isolation by cache line.
test "contract: Static slots and global generation occupy distinct cache lines" {
    const Domain = qsbr.Domain.Static(3);
    var domain = Domain.init();
    const line = std.atomic.cache_line;

    const global_offset = @offsetOf(Domain, "global_generation");
    const slots_offset = @offsetOf(Domain, "slots");
    try testing.expectEqual(@as(usize, 0), global_offset % line);
    try testing.expectEqual(@as(usize, 0), slots_offset % line);
    try testing.expect(distance(global_offset, slots_offset) >= line);

    const first = @intFromPtr(&domain.slots[0]);
    const second = @intFromPtr(&domain.slots[1]);
    const third = @intFromPtr(&domain.slots[2]);
    try testing.expectEqual(@as(usize, 0), first % line);
    try testing.expectEqual(@as(usize, 0), second % line);
    try testing.expectEqual(@as(usize, 0), third % line);
    try testing.expectEqual(@sizeOf(Domain.Slot), second - first);
    try testing.expectEqual(@sizeOf(Domain.Slot), third - second);
    try testing.expect(second - first >= line);
    try testing.expect(third - second >= line);
}

// Reads encoded slot words through implementation fields to check offline and online encodings.
test "contract: encoded slot words distinguish offline and online generations" {
    const Domain = qsbr.Domain.Static(2);
    var domain = Domain.init();
    const p0 = domain.participant(0);
    const p1 = domain.participant(1);

    try expectSlotOffline(&domain.slots[0]);
    try expectSlotOffline(&domain.slots[1]);

    domain.online(p0);
    try expectSlotOnlineGeneration(&domain.slots[0], 0);

    const grace_period = domain.beginGracePeriod();
    domain.quiescent(p0);
    try expectSlotOnlineGeneration(&domain.slots[0], grace_period.generation());

    domain.offline(p0);
    domain.offline(p1);
    try expectSlotOffline(&domain.slots[0]);
    try expectSlotOffline(&domain.slots[1]);
}

// Begins repeated periods and checks the global word never uses the offline marker bit.
test "contract: global generation never uses the offline encoding bit" {
    const Domain = qsbr.Domain.Static(1);
    var domain = Domain.init();

    var iteration: usize = 0;
    while (iteration < 64) : (iteration += 1) {
        _ = domain.beginGracePeriod();
        const encoded = domain.global_generation.value.load(.acquire);
        try testing.expectEqual(@as(u64, 0), encoded & offline_bit);
        try testing.expectEqual(domain.generation(), encoded & generation_mask);
    }
}

fn runReferenceModel(comptime participant_count: usize) !void {
    const Domain = qsbr.Domain.Static(participant_count);
    var domain = Domain.init();
    var online = [_]bool{false} ** participant_count;
    var reported = [_]u64{0} ** participant_count;
    var periods: [64]GracePeriod = undefined;
    var period_count: usize = 0;
    var model_generation: u64 = 0;
    var prng = std.Random.Xoshiro256.init(0xA51C_0FFE_EE12_3456);
    const random = prng.random();

    var step: usize = 0;
    while (step < 512) : (step += 1) {
        const participant_index = random.uintLessThan(usize, participant_count);
        const participant = domain.participant(participant_index);
        switch (random.uintLessThan(u8, 5)) {
            0 => {
                domain.online(participant);
                online[participant_index] = true;
                reported[participant_index] = model_generation;
            },
            1 => {
                domain.offline(participant);
                online[participant_index] = false;
            },
            2 => if (online[participant_index]) {
                domain.quiescent(participant);
                reported[participant_index] = model_generation;
            },
            3 => if (period_count < periods.len) {
                const grace_period = domain.beginGracePeriod();
                model_generation += 1;
                try testing.expectEqual(model_generation, grace_period.generation());
                periods[period_count] = grace_period;
                period_count += 1;
            },
            else => {},
        }
        try expectReferenceMatches(participant_count, &domain, &online, &reported, periods[0..period_count]);
    }
}

fn expectReferenceMatches(
    comptime participant_count: usize,
    domain: anytype,
    online: *const [participant_count]bool,
    reported: *const [participant_count]u64,
    periods: []const GracePeriod,
) !void {
    for (periods) |grace_period| {
        const expected = referenceComplete(participant_count, online, reported, grace_period.generation());
        try testing.expectEqual(expected, domain.isComplete(grace_period));
    }
}

fn referenceComplete(
    comptime participant_count: usize,
    online: *const [participant_count]bool,
    reported: *const [participant_count]u64,
    target: u64,
) bool {
    var index: usize = 0;
    while (index < participant_count) : (index += 1) {
        if (online[index] and reported[index] < target) return false;
    }
    return true;
}

fn expectSlotOffline(slot: anytype) !void {
    const word = slot.value.load(.acquire);

    try testing.expect(word & offline_bit != 0);
}

fn expectSlotOnlineGeneration(slot: anytype, expected_generation: u64) !void {
    const word = slot.value.load(.acquire);

    try testing.expectEqual(@as(u64, 0), word & offline_bit);
    try testing.expectEqual(expected_generation, word & generation_mask);
}

fn distance(a: usize, b: usize) usize {
    return if (a > b) a - b else b - a;
}
