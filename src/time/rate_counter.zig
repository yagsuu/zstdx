//! Fixed-rate projection of `Instant`; detects wrap edges below 64 bits.
//! See `docs/specs/time/rate_counter.md`.

const std = @import("std");

const debug = @import("core").debug;
const monotonic = @import("monotonic.zig");

const Instant = monotonic.Instant;
const ClockImpl = monotonic.Clock.Impl;

const nanos_per_second: u128 = 1_000_000_000;

/// Single-owner counter; callers serialize access.
pub const RateCounter = struct {
    base: Instant,
    rate_hz: u64,
    width: u7,
    wraps: u64,

    /// Changing base, rate, or width requires constructing a new counter.
    pub const Config = struct {
        base: Instant,
        rate_hz: u64,
        width: u7,

        pub fn assertValid(self: Config) void {
            Impl.assertConfig(self.rate_hz, self.width);
        }
    };

    pub const Sample = struct {
        value: u64,
        wrapped: bool,
    };

    const Self = @This();

    comptime {
        std.debug.assert(@sizeOf(Self) == 32);
    }

    pub fn init(config: Config) Self {
        if (debug.checksEnabled()) {
            config.assertValid();
        }
        return .{
            .base = config.base,
            .rate_hz = config.rate_hz,
            .width = config.width,
            .wraps = 0,
        };
    }

    /// Re-anchors `base` to `clock.now()` and clears wrap state. The next
    /// `sample` reports `wrapped = false`; rate and width are preserved.
    pub fn reset(self: *Self, clock: anytype) void {
        comptime ClockImpl.requireClock(@TypeOf(clock), "RateCounter");
        self.base = clock.now();
        self.wraps = 0;
    }

    pub fn peek(self: *const Self, clock: anytype) u64 {
        comptime ClockImpl.requireClock(@TypeOf(clock), "RateCounter");
        return Impl.project(self, clock.now()).value;
    }

    /// Advances wrap state. For widths below 64, `wrapped` is true exactly
    /// when the unbounded tick count crossed a `1 << width` boundary
    /// since `init`, `reset`, or the previous `sample`.
    pub fn sample(self: *Self, clock: anytype) Sample {
        comptime ClockImpl.requireClock(@TypeOf(clock), "RateCounter");
        const p = Impl.project(self, clock.now());
        const wrapped = p.wraps > self.wraps;
        self.wraps = p.wraps;
        return .{ .value = p.value, .wrapped = wrapped };
    }

    pub fn assertValid(self: *const Self) void {
        Impl.assertConfig(self.rate_hz, self.width);
    }
};

const Projection = struct {
    value: u64,
    wraps: u64,
};

const Impl = struct {
    fn project(self: *const RateCounter, now: Instant) Projection {
        if (debug.checksEnabled()) {
            std.debug.assert(now.isAtOrAfter(self.base));
        }

        // Unchecked builds clamp readings before base to keep the cast total.
        const elapsed = now.since(self.base).nanos();
        const elapsed_ns: u128 = if (elapsed < 0) 0 else @intCast(elapsed);
        const unbounded = @divFloor(elapsed_ns * @as(u128, self.rate_hz), nanos_per_second);

        if (self.width == 64) {
            return .{ .value = @truncate(unbounded), .wraps = 0 };
        }

        const mask = (@as(u128, 1) << self.width) - 1;
        return .{
            .value = @intCast(unbounded & mask),
            .wraps = @intCast(unbounded >> self.width),
        };
    }

    fn assertConfig(rate_hz: u64, width: u7) void {
        std.debug.assert(rate_hz > 0);
        std.debug.assert(width >= 1);
        std.debug.assert(width <= 64);
    }
};

pub const unit = struct {
    const testing = std.testing;

    const FakeClock = struct {
        current: Instant,

        pub fn now(self: *@This()) Instant {
            return self.current;
        }
    };

    test "projection floors ticks and crosses the width boundary" {
        const counter = RateCounter.init(.{
            .base = Instant.fromNanos(1_000),
            .rate_hz = 100,
            .width = 8,
        });

        const base = Impl.project(&counter, counter.base);
        const fractional = Impl.project(&counter, Instant.fromNanos(10_000_999));
        const before = Impl.project(&counter, Instant.fromNanos(2_550_001_000));
        const boundary = Impl.project(&counter, Instant.fromNanos(2_560_001_000));
        const after = Impl.project(&counter, Instant.fromNanos(2_570_001_000));

        try testing.expectEqual(Projection{ .value = 0, .wraps = 0 }, base);
        try testing.expectEqual(Projection{ .value = 0, .wraps = 0 }, fractional);
        try testing.expectEqual(Projection{ .value = 255, .wraps = 0 }, before);
        try testing.expectEqual(Projection{ .value = 0, .wraps = 1 }, boundary);
        try testing.expectEqual(Projection{ .value = 1, .wraps = 1 }, after);
    }

    test "projection masks PM ticks and preserves wide intermediates" {
        const pm = RateCounter.init(.{
            .base = Instant.zero,
            .rate_hz = 3_579_545,
            .width = 24,
        });
        const wide = RateCounter.init(.{
            .base = Instant.zero,
            .rate_hz = std.math.maxInt(u64),
            .width = 64,
        });

        const masked = Impl.project(&pm, Instant.fromNanos(10_000_000_000));
        const overflow = Impl.project(&wide, Instant.fromNanos(2_000_000_000));
        const maximum = Impl.project(&wide, Instant.fromNanos(std.math.maxInt(i64)));

        try testing.expectEqual(Projection{ .value = 2_241_018, .wraps = 2 }, masked);
        try testing.expectEqual(Projection{ .value = std.math.maxInt(u64) - 1, .wraps = 0 }, overflow);
        try testing.expectEqual(Projection{ .value = 15_767_830_542_904_177_429, .wraps = 0 }, maximum);
    }

    test "peek preserves pending wraps and sample consumes them" {
        var counter = RateCounter.init(.{
            .base = Instant.zero,
            .rate_hz = 100,
            .width = 8,
        });
        var clock: FakeClock = .{ .current = Instant.zero };

        const initial = counter.sample(&clock);
        clock.current = Instant.fromNanos(3_000_000_000);
        const peeked = counter.peek(&clock);
        const pending = counter.wraps;
        const crossed = counter.sample(&clock);
        clock.current = Instant.fromNanos(3_500_000_000);
        const same_window = counter.sample(&clock);
        clock.current = Instant.fromNanos(10_000_000_000);
        const multiple = counter.sample(&clock);
        const consumed = counter.sample(&clock);

        try testing.expectEqual(RateCounter.Sample{ .value = 0, .wrapped = false }, initial);
        try testing.expectEqual(@as(u64, 44), peeked);
        try testing.expectEqual(@as(u64, 0), pending);
        try testing.expectEqual(RateCounter.Sample{ .value = 44, .wrapped = true }, crossed);
        try testing.expectEqual(RateCounter.Sample{ .value = 94, .wrapped = false }, same_window);
        try testing.expectEqual(RateCounter.Sample{ .value = 232, .wrapped = true }, multiple);
        try testing.expectEqual(RateCounter.Sample{ .value = 232, .wrapped = false }, consumed);
        try testing.expectEqual(@as(u64, 3), counter.wraps);
    }

    test "reset clears consumed wraps and preserves projection geometry" {
        var counter = RateCounter.init(.{
            .base = Instant.zero,
            .rate_hz = 100,
            .width = 8,
        });
        var clock: FakeClock = .{ .current = Instant.fromNanos(3_000_000_000) };

        const before = counter.sample(&clock);
        counter.reset(&clock);
        const reset_wraps = counter.wraps;
        const reset_base = counter.base;
        const initial = counter.sample(&clock);
        clock.current = Instant.fromNanos(5_560_000_000);
        const boundary = counter.sample(&clock);

        try testing.expect(before.wrapped);
        try testing.expectEqual(@as(u64, 0), reset_wraps);
        try testing.expectEqual(Instant.fromNanos(3_000_000_000), reset_base);
        try testing.expectEqual(RateCounter.Sample{ .value = 0, .wrapped = false }, initial);
        try testing.expectEqual(RateCounter.Sample{ .value = 0, .wrapped = true }, boundary);
    }

    test "64-bit samples never report wraps" {
        var counter = RateCounter.init(.{
            .base = Instant.zero,
            .rate_hz = std.math.maxInt(u64),
            .width = 64,
        });
        var clock: FakeClock = .{ .current = Instant.fromNanos(std.math.maxInt(i64)) };

        const sample = counter.sample(&clock);

        try testing.expect(!sample.wrapped);
        try testing.expectEqual(@as(u64, 0), counter.wraps);
    }
};
