//! deadlines for poll loops

const std = @import("std");

const monotonic = @import("monotonic.zig");

const Duration = monotonic.Duration;
const Instant = monotonic.Instant;
const ClockImpl = monotonic.Clock.Impl;

pub const Deadline = enum(u64) {
    _,

    /// expires only when the clock reaches maxInt(u64)
    pub const never: Self = @enumFromInt(std.math.maxInt(Int));

    pub const Int = u64;
    pub const OverflowError = error{Overflow};
    pub const TimeoutError = error{Timeout};

    const Self = @This();

    pub fn from(value: Instant) Self {
        return @enumFromInt(value.nanos());
    }

    pub fn after(clock: anytype, delta: Duration) OverflowError!Self {
        comptime ClockImpl.requireClock(@TypeOf(clock), "Deadline");
        const target = try clock.now().add(delta);
        return @enumFromInt(target.nanos());
    }

    pub fn instant(self: Self) Instant {
        return Instant.fromNanos(@intFromEnum(self));
    }

    pub fn isNever(self: Self) bool {
        return @intFromEnum(self) == std.math.maxInt(Int);
    }

    pub fn isExpired(self: Self, clock: anytype) bool {
        comptime ClockImpl.requireClock(@TypeOf(clock), "Deadline");
        return clock.now().isAtOrAfter(self.instant());
    }

    pub fn remaining(self: Self, clock: anytype) Duration {
        comptime ClockImpl.requireClock(@TypeOf(clock), "Deadline");

        if (self.isNever()) {
            return Duration.fromNanos(std.math.maxInt(i64));
        }

        return self.instant().since(clock.now());
    }

    pub fn check(self: Self, clock: anytype) TimeoutError!void {
        if (self.isExpired(clock)) {
            return error.Timeout;
        }
    }
};

pub const unit = struct {
    const testing = std.testing;

    const FakeClock = struct {
        current: Instant,
        reads: usize = 0,

        pub fn now(self: *@This()) Instant {
            self.reads += 1;
            return self.current;
        }
    };

    test "finite deadline transitions across its boundary" {
        const dl = Deadline.from(Instant.fromNanos(1_000));
        var clock: FakeClock = .{ .current = Instant.fromNanos(999) };

        try testing.expect(!dl.isNever());
        try testing.expect(!dl.isExpired(&clock));
        try testing.expectEqual(@as(i64, 1), dl.remaining(&clock).nanos());
        try dl.check(&clock);

        clock.current = Instant.fromNanos(1_000);

        try testing.expect(dl.isExpired(&clock));
        try testing.expectEqual(@as(i64, 0), dl.remaining(&clock).nanos());
        try testing.expectError(error.Timeout, dl.check(&clock));

        clock.current = Instant.fromNanos(1_500);

        try testing.expect(dl.isExpired(&clock));
        try testing.expectEqual(@as(i64, -500), dl.remaining(&clock).nanos());
        try testing.expectError(error.Timeout, dl.check(&clock));
    }

    test "relative deadlines preserve signed deltas and reject overflow" {
        var clock: FakeClock = .{ .current = Instant.fromNanos(1_000) };

        const future = try Deadline.after(&clock, Duration.fromNanos(10));
        const past = try Deadline.after(&clock, Duration.fromNanos(-1));

        try testing.expectEqual(@as(u64, 1_010), future.instant().nanos());
        try testing.expectEqual(@as(u64, 999), past.instant().nanos());
        try testing.expect(past.isExpired(&clock));

        clock.current = Instant.fromNanos(std.math.maxInt(u64) - 10);

        try testing.expectError(error.Overflow, Deadline.after(&clock, Duration.fromNanos(11)));

        clock.current = Instant.fromNanos(0);

        try testing.expectError(error.Overflow, Deadline.after(&clock, Duration.fromNanos(-1)));
    }

    test "never skips remaining reads but expires at the maximum instant" {
        var clock: FakeClock = .{ .current = Instant.fromNanos(std.math.maxInt(u64) - 1) };

        const remaining = Deadline.never.remaining(&clock);

        try testing.expect(Deadline.never.isNever());
        try testing.expectEqual(@as(i64, std.math.maxInt(i64)), remaining.nanos());
        try testing.expectEqual(@as(usize, 0), clock.reads);
        try testing.expect(!Deadline.never.isExpired(&clock));
        try Deadline.never.check(&clock);

        clock.current = Instant.fromNanos(std.math.maxInt(u64));

        try testing.expect(Deadline.never.isExpired(&clock));
        try testing.expectError(error.Timeout, Deadline.never.check(&clock));
        try testing.expectEqual(@as(i64, std.math.maxInt(i64)), Deadline.never.remaining(&clock).nanos());
        try testing.expectEqual(@as(usize, 4), clock.reads);
    }
};
