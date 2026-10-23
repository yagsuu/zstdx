//! retry-delay generator

const std = @import("std");

const debug = @import("core").debug;
const deadline = @import("deadline.zig");
const monotonic = @import("monotonic.zig");

const Deadline = deadline.Deadline;
const Duration = monotonic.Duration;
const Instant = monotonic.Instant;

pub const Backoff = struct {
    policy: Policy,
    attempt: u32,
    next_wait: Duration,

    pub const Spin = struct {
        iterations: u32,
    };

    pub const Yield = struct {
        iterations: u32,
        hook: *const fn () void,
    };

    pub const Wait = struct {
        initial: Duration,
        max: Duration,
        growth_shift: u3,

        pub fn assertValid(self: Wait) void {
            std.debug.assert(self.initial.nanos() >= 0);
            std.debug.assert(self.max.nanos() >= 0);
            std.debug.assert(self.initial.nanos() <= self.max.nanos());
        }
    };

    pub const Policy = struct {
        spin: Spin,
        yield: ?Yield,
        wait: Wait,
    };

    pub const Step = union(enum) {
        spin,
        yield,
        sleep: Duration,
        timeout,
    };

    const Self = @This();

    pub fn init(policy: Policy) Self {
        if (debug.checksEnabled()) {
            policy.wait.assertValid();
        }

        return .{
            .policy = policy,
            .attempt = 0,
            .next_wait = policy.wait.initial,
        };
    }

    pub fn reset(self: *Self) void {
        self.attempt = 0;
        self.next_wait = self.policy.wait.initial;
    }

    /// timeout leaves attempts and wait state unchanged
    /// sleep is limited to the remaining time
    pub fn next(self: *Self, dl: Deadline, clock: anytype) Step {
        if (dl.isExpired(clock)) {
            return .timeout;
        }

        if (self.attempt < self.policy.spin.iterations) {
            self.attempt += 1;
            return .spin;
        }

        if (self.policy.yield) |*yield| {
            const yield_end = self.policy.spin.iterations + yield.iterations;
            if (self.attempt < yield_end) {
                self.attempt += 1;
                return .yield;
            }
        }

        const remaining_ns = dl.remaining(clock).nanos();
        if (remaining_ns <= 0) {
            return .timeout;
        }

        const wait_ns = @min(self.next_wait.nanos(), remaining_ns);
        std.debug.assert(wait_ns >= 0);

        const grown = self.next_wait.nanos() <<| self.policy.wait.growth_shift;
        self.next_wait = Duration.fromNanos(@min(grown, self.policy.wait.max.nanos()));
        self.attempt += 1;

        return .{ .sleep = Duration.fromNanos(wait_ns) };
    }

    pub fn attempts(self: *const Self) u32 {
        return self.attempt;
    }

    pub fn assertValid(self: *const Self) void {
        self.policy.wait.assertValid();
        std.debug.assert(self.next_wait.nanos() >= 0);
        std.debug.assert(self.next_wait.nanos() <= self.policy.wait.max.nanos());
    }
};

pub const unit = struct {
    const testing = std.testing;

    const FakeClock = struct {
        current: Instant = Instant.fromNanos(0),

        pub fn now(self: *@This()) Instant {
            return self.current;
        }
    };

    var yield_calls: usize = 0;

    fn yieldHook() void {
        yield_calls += 1;
    }

    test "spin and yield phases lead to sleep and reset restarts them" {
        yield_calls = 0;

        var bo = Backoff.init(.{
            .spin = .{ .iterations = 2 },
            .yield = .{ .iterations = 1, .hook = &yieldHook },
            .wait = .{
                .initial = Duration.fromNanos(100),
                .max = Duration.fromNanos(400),
                .growth_shift = 1,
            },
        });
        var clock: FakeClock = .{};

        try testing.expectEqual(Backoff.Step.spin, bo.next(Deadline.never, &clock));
        try testing.expectEqual(Backoff.Step.spin, bo.next(Deadline.never, &clock));
        try testing.expectEqual(Backoff.Step.yield, bo.next(Deadline.never, &clock));
        try testing.expectEqual(Backoff.Step{ .sleep = Duration.fromNanos(100) }, bo.next(Deadline.never, &clock));
        try testing.expectEqual(@as(u32, 4), bo.attempts());
        try testing.expectEqual(@as(usize, 0), yield_calls);
        bo.assertValid();

        bo.reset();

        try testing.expectEqual(@as(u32, 0), bo.attempts());
        try testing.expectEqual(Duration.fromNanos(100), bo.next_wait);
        try testing.expectEqual(Backoff.Step.spin, bo.next(Deadline.never, &clock));
        bo.assertValid();
    }

    test "absent yield skips its phase and sleep growth stops at the bound" {
        var bo = Backoff.init(.{
            .spin = .{ .iterations = 1 },
            .yield = null,
            .wait = .{
                .initial = Duration.fromNanos(100),
                .max = Duration.fromNanos(400),
                .growth_shift = 1,
            },
        });
        var clock: FakeClock = .{};

        try testing.expectEqual(Backoff.Step.spin, bo.next(Deadline.never, &clock));
        for ([_]i64{ 100, 200, 400, 400 }) |wait| {
            try testing.expectEqual(
                Backoff.Step{ .sleep = Duration.fromNanos(wait) },
                bo.next(Deadline.never, &clock),
            );
            bo.assertValid();
        }
        try testing.expectEqual(@as(u32, 5), bo.attempts());
    }

    test "zero shift keeps waits constant and large growth saturates at the limit" {
        var bo = Backoff.init(.{
            .spin = .{ .iterations = 0 },
            .yield = null,
            .wait = .{
                .initial = Duration.fromNanos(500),
                .max = Duration.fromNanos(std.math.maxInt(i64)),
                .growth_shift = 0,
            },
        });
        var clock: FakeClock = .{};

        for (0..3) |_| {
            try testing.expectEqual(
                Backoff.Step{ .sleep = Duration.fromNanos(500) },
                bo.next(Deadline.never, &clock),
            );
            bo.assertValid();
        }

        bo.policy.wait.initial = Duration.fromNanos(std.math.maxInt(i64) / 4);
        bo.policy.wait.growth_shift = 7;
        bo.reset();
        const first = bo.next(Deadline.never, &clock);
        const second = bo.next(Deadline.never, &clock);

        try testing.expectEqual(Backoff.Step{ .sleep = bo.policy.wait.initial }, first);
        try testing.expectEqual(Backoff.Step{ .sleep = bo.policy.wait.max }, second);
        bo.assertValid();
    }

    test "deadline clips sleep and timeout preserves attempts and wait state" {
        var bo = Backoff.init(.{
            .spin = .{ .iterations = 1 },
            .yield = null,
            .wait = .{
                .initial = Duration.fromNanos(100),
                .max = Duration.fromNanos(400),
                .growth_shift = 1,
            },
        });
        var clock: FakeClock = .{ .current = Instant.fromNanos(30) };
        const dl = Deadline.from(Instant.fromNanos(30));

        try testing.expectEqual(Backoff.Step.timeout, bo.next(dl, &clock));
        try testing.expectEqual(@as(u32, 0), bo.attempts());
        try testing.expectEqual(Duration.fromNanos(100), bo.next_wait);

        clock.current = Instant.fromNanos(0);

        try testing.expectEqual(Backoff.Step.spin, bo.next(dl, &clock));
        try testing.expectEqual(Backoff.Step{ .sleep = Duration.fromNanos(30) }, bo.next(dl, &clock));
        try testing.expectEqual(@as(u32, 2), bo.attempts());
        try testing.expectEqual(Duration.fromNanos(200), bo.next_wait);
        bo.assertValid();

        clock.current = Instant.fromNanos(30);

        try testing.expectEqual(Backoff.Step.timeout, bo.next(dl, &clock));
        try testing.expectEqual(Backoff.Step.timeout, bo.next(dl, &clock));
        try testing.expectEqual(@as(u32, 2), bo.attempts());
        try testing.expectEqual(Duration.fromNanos(200), bo.next_wait);
        bo.assertValid();
    }
};
