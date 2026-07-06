//! Monotonic clock and time value-type tests. Spec: docs/specs/time/monotonic.md.

const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;

const Instant = stdx.time.Instant;
const Duration = stdx.time.Duration;

const TestBackend = struct {
    ticks: []const u64,
    index: usize = 0,

    pub fn now(self: *TestBackend) stdx.time.Instant {
        const t = stdx.time.Instant.fromNanos(self.ticks[self.index]);
        self.index += 1;
        return t;
    }
};

test "unit: Instant fromNanos/nanos round-trip covers 0, 1, and maxInt(u64)" {
    try testing.expectEqual(@as(u64, 0), Instant.fromNanos(0).nanos());
    try testing.expectEqual(@as(u64, 1), Instant.fromNanos(1).nanos());
    try testing.expectEqual(
        @as(u64, std.math.maxInt(u64)),
        Instant.fromNanos(std.math.maxInt(u64)).nanos(),
    );
}

test "unit: Instant.zero equals fromNanos(0)" {
    try testing.expectEqual(Instant.fromNanos(0), Instant.zero());
    try testing.expectEqual(@as(u64, 0), Instant.zero().nanos());
}

test "unit: Instant.add handles zero, positive, and negative durations" {
    const base = Instant.fromNanos(100);

    const same = try base.add(Duration.fromNanos(0));
    try testing.expectEqual(@as(u64, 100), same.nanos());

    const forward = try base.add(Duration.fromNanos(50));
    try testing.expectEqual(@as(u64, 150), forward.nanos());

    const backward = try base.add(Duration.fromNanos(-25));
    try testing.expectEqual(@as(u64, 75), backward.nanos());
}

test "unit: Instant.add returns Overflow past maxInt(u64) and below 0" {
    try testing.expectError(
        error.Overflow,
        Instant.fromNanos(std.math.maxInt(u64)).add(Duration.fromNanos(1)),
    );
    try testing.expectError(
        error.Overflow,
        Instant.zero().add(Duration.fromNanos(-1)),
    );
}

test "unit: Instant.since returns positive, zero, and signed-negative differences" {
    const a = Instant.fromNanos(500);
    const b = Instant.fromNanos(200);

    try testing.expectEqual(@as(i64, 300), a.since(b).nanos());
    try testing.expectEqual(@as(i64, 0), a.since(a).nanos());
    try testing.expectEqual(@as(i64, -300), b.since(a).nanos());
}

test "unit: Instant.afterOrEq covers less/equal/greater" {
    const lo = Instant.fromNanos(10);
    const hi = Instant.fromNanos(20);

    try testing.expect(hi.afterOrEq(lo));
    try testing.expect(hi.afterOrEq(hi));
    try testing.expect(!lo.afterOrEq(hi));
}

test "unit: Duration.fromNanos/nanos round-trip zero, positive, and negative" {
    try testing.expectEqual(@as(i64, 0), Duration.fromNanos(0).nanos());
    try testing.expectEqual(@as(i64, 42), Duration.fromNanos(42).nanos());
    try testing.expectEqual(@as(i64, -42), Duration.fromNanos(-42).nanos());
    try testing.expectEqual(
        @as(i64, std.math.maxInt(i64)),
        Duration.fromNanos(std.math.maxInt(i64)).nanos(),
    );
    try testing.expectEqual(
        @as(i64, std.math.minInt(i64)),
        Duration.fromNanos(std.math.minInt(i64)).nanos(),
    );
}

test "unit: Duration.zero is zero" {
    try testing.expectEqual(@as(i64, 0), Duration.zero.nanos());
    try testing.expectEqual(Duration.fromNanos(0), Duration.zero);
}

test "unit: Duration.fromMicros/fromMillis/fromSeconds multiply correctly" {
    try testing.expectEqual(@as(i64, 3_000), (try Duration.fromMicros(3)).nanos());
    try testing.expectEqual(@as(i64, -3_000), (try Duration.fromMicros(-3)).nanos());

    try testing.expectEqual(@as(i64, 5_000_000), (try Duration.fromMillis(5)).nanos());
    try testing.expectEqual(@as(i64, -5_000_000), (try Duration.fromMillis(-5)).nanos());

    try testing.expectEqual(@as(i64, 7_000_000_000), (try Duration.fromSeconds(7)).nanos());
    try testing.expectEqual(@as(i64, -7_000_000_000), (try Duration.fromSeconds(-7)).nanos());
}

test "unit: Duration.from* overflow returns Overflow" {
    try testing.expectError(
        error.Overflow,
        Duration.fromSeconds(std.math.maxInt(i64) / 1_000_000_000 + 1),
    );
    try testing.expectError(
        error.Overflow,
        Duration.fromMillis(std.math.maxInt(i64) / 1_000_000 + 1),
    );
    try testing.expectError(
        error.Overflow,
        Duration.fromMicros(std.math.maxInt(i64) / 1_000 + 1),
    );
}

test "unit: Duration.isPositive/isNegative cover positive/zero/negative" {
    const pos = Duration.fromNanos(1);
    const zero = Duration.fromNanos(0);
    const neg = Duration.fromNanos(-1);

    try testing.expect(pos.isPositive());
    try testing.expect(!pos.isNegative());

    try testing.expect(!zero.isPositive());
    try testing.expect(!zero.isNegative());

    try testing.expect(!neg.isPositive());
    try testing.expect(neg.isNegative());
}

test "unit: Clock.Monotonic.init and now return the backend's values verbatim" {
    const Wrapper = stdx.time.Clock.Monotonic(TestBackend);
    var clock = Wrapper.init(TestBackend{ .ticks = &.{ 100, 200, 300 } });

    try testing.expectEqual(Instant.fromNanos(100), clock.now());
    try testing.expectEqual(Instant.fromNanos(200), clock.now());
    try testing.expectEqual(Instant.fromNanos(300), clock.now());
}

test "unit: Clock.Monotonic release build has sizeof equal to backend" {
    if (stdx.core.debug.checksEnabled(.build_mode)) return;
    try testing.expectEqual(
        @sizeOf(TestBackend),
        @sizeOf(stdx.time.Clock.Monotonic(TestBackend)),
    );
}

const SleepingBackend = struct {
    now_ticks: []const u64,
    now_index: usize = 0,
    sleeps_buf: [8]Duration = undefined,
    sleeps_len: usize = 0,

    pub fn now(self: *SleepingBackend) Instant {
        const t = Instant.fromNanos(self.now_ticks[self.now_index]);
        self.now_index += 1;
        return t;
    }

    pub fn sleep(self: *SleepingBackend, delta: Duration) void {
        self.sleeps_buf[self.sleeps_len] = delta;
        self.sleeps_len += 1;
    }

    pub fn sleeps(self: *const SleepingBackend) []const Duration {
        return self.sleeps_buf[0..self.sleeps_len];
    }
};

test "unit: Clock.Monotonic without backend.sleep exposes no wrapper.sleep" {
    const Wrapper = stdx.time.Clock.Monotonic(TestBackend);
    try testing.expect(!@hasDecl(Wrapper, "sleep"));
}

test "unit: Clock.Monotonic with backend.sleep exposes wrapper.sleep" {
    const Wrapper = stdx.time.Clock.Monotonic(SleepingBackend);
    try testing.expect(@hasDecl(Wrapper, "sleep"));
}

test "unit: Clock.Monotonic.sleep forwards delta to backend verbatim" {
    const Wrapper = stdx.time.Clock.Monotonic(SleepingBackend);
    var clock = Wrapper.init(SleepingBackend{ .now_ticks = &.{0} });

    clock.sleep(Duration.fromNanos(1_000));
    clock.sleep(try Duration.fromMicros(5));
    clock.sleep(Duration.zero);

    const log = clock.backend.sleeps();
    try testing.expectEqual(@as(usize, 3), log.len);
    try testing.expectEqual(Duration.fromNanos(1_000), log[0]);
    try testing.expectEqual(Duration.fromNanos(5_000), log[1]);
    try testing.expectEqual(Duration.zero, log[2]);
}

test "unit: Clock.Monotonic.sleep(Duration.zero) forwards to backend and returns" {
    const Wrapper = stdx.time.Clock.Monotonic(SleepingBackend);
    var clock = Wrapper.init(SleepingBackend{ .now_ticks = &.{0} });

    clock.sleep(Duration.zero);

    try testing.expectEqual(@as(usize, 1), clock.backend.sleeps_len);
    try testing.expectEqual(Duration.zero, clock.backend.sleeps_buf[0]);
}

test "unit: Clock.Monotonic sleeping wrapper preserves now monotonicity semantics" {
    const Wrapper = stdx.time.Clock.Monotonic(SleepingBackend);
    var clock = Wrapper.init(SleepingBackend{ .now_ticks = &.{ 10, 20, 30 } });

    try testing.expectEqual(Instant.fromNanos(10), clock.now());
    try testing.expectEqual(Instant.fromNanos(20), clock.now());
    try testing.expectEqual(Instant.fromNanos(30), clock.now());
}
