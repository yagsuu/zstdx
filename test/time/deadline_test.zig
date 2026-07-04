//! Deadline value-type tests. Spec: docs/specs/time/deadline.md.

const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;

const Instant = stdx.time.Instant;
const Duration = stdx.time.Duration;
const Deadline = stdx.time.Deadline;

comptime {
    std.debug.assert(@sizeOf(Deadline) == 8);
}

const FakeClock = struct {
    current: Instant,

    pub fn now(self: *FakeClock) Instant {
        return self.current;
    }

    pub fn set(self: *FakeClock, at_ns: u64) void {
        self.current = Instant.fromNanos(at_ns);
    }
};

fn fakeAt(at_ns: u64) FakeClock {
    return .{ .current = Instant.fromNanos(at_ns) };
}

test "unit: Deadline size is one u64 word" {
    try testing.expectEqual(@as(usize, 8), @sizeOf(Deadline));
}

test "unit: Deadline.at round-trips Instant at 0, mid, and maxInt(u64)-1" {
    const zero = Instant.fromNanos(0);
    try testing.expectEqual(zero, Deadline.at(zero).instant());

    const mid = Instant.fromNanos(1_234_567_890);
    try testing.expectEqual(mid, Deadline.at(mid).instant());

    const near_max = Instant.fromNanos(std.math.maxInt(u64) - 1);
    try testing.expectEqual(near_max, Deadline.at(near_max).instant());
}

test "unit: Deadline.now anchors 10ms past fake_clock.now()" {
    var clock = fakeAt(1_000);
    const d = try Deadline.now(&clock, try Duration.fromMillis(10));

    try testing.expectEqual(@as(u64, 1_000 + 10_000_000), d.instant().nanos());
}

test "unit: Deadline.now with negative delta lands one ns before now and is expired" {
    var clock = fakeAt(1_000);
    const d = try Deadline.now(&clock, Duration.fromNanos(-1));

    try testing.expectEqual(@as(u64, 999), d.instant().nanos());
    try testing.expect(d.expired(&clock));
}

test "unit: Deadline.now returns Overflow when delta overshoots maxInt(u64)" {
    var clock = fakeAt(std.math.maxInt(u64) - 10);
    try testing.expectError(
        error.Overflow,
        Deadline.now(&clock, Duration.fromNanos(std.math.maxInt(i64))),
    );
}

test "unit: Deadline.instant projects nanos verbatim" {
    const d = Deadline.at(Instant.fromNanos(42));
    try testing.expectEqual(@as(u64, 42), d.instant().nanos());
}

test "unit: Deadline.never.isNever is true and finite deadlines are not" {
    try testing.expect(Deadline.never.isNever());
    try testing.expect(!Deadline.at(Instant.zero()).isNever());
    try testing.expect(!Deadline.at(Instant.fromNanos(1)).isNever());
}

test "unit: Deadline.never.expired is false for any practical clock reading" {
    var early = fakeAt(0);
    var mid = fakeAt(1_000_000_000);
    var late = fakeAt(std.math.maxInt(u64) - 1);

    try testing.expect(!Deadline.never.expired(&early));
    try testing.expect(!Deadline.never.expired(&mid));
    try testing.expect(!Deadline.never.expired(&late));
}

test "unit: Deadline.never.remaining saturates at Duration maxInt(i64)" {
    var early = fakeAt(0);
    var mid = fakeAt(1_000_000_000);
    var late = fakeAt(std.math.maxInt(u64) - 1);

    const saturated = Duration.fromNanos(std.math.maxInt(i64));
    try testing.expectEqual(saturated, Deadline.never.remaining(&early));
    try testing.expectEqual(saturated, Deadline.never.remaining(&mid));
    try testing.expectEqual(saturated, Deadline.never.remaining(&late));
}

test "unit: Deadline.never.expireBy returns void for any live clock reading" {
    var clock = fakeAt(1_000_000_000);
    try Deadline.never.expireBy(&clock);
}

test "unit: expired transitions false -> true at the boundary" {
    const d = Deadline.at(Instant.fromNanos(1_000));

    var before = fakeAt(999);
    var boundary = fakeAt(1_000);
    var after = fakeAt(1_001);

    try testing.expect(!d.expired(&before));
    try testing.expect(d.expired(&boundary));
    try testing.expect(d.expired(&after));
}

test "unit: remaining returns positive/zero/negative around the boundary" {
    const d = Deadline.at(Instant.fromNanos(1_000));

    var before = fakeAt(400);
    var boundary = fakeAt(1_000);
    var after = fakeAt(1_500);

    try testing.expectEqual(@as(i64, 600), d.remaining(&before).nanos());
    try testing.expectEqual(Duration.zero, d.remaining(&boundary));
    try testing.expectEqual(@as(i64, -500), d.remaining(&after).nanos());
}

test "unit: expireBy returns Timeout at and after the boundary, void before" {
    const d = Deadline.at(Instant.fromNanos(1_000));

    var before = fakeAt(999);
    var boundary = fakeAt(1_000);
    var after = fakeAt(1_001);

    try d.expireBy(&before);
    try testing.expectError(error.Timeout, d.expireBy(&boundary));
    try testing.expectError(error.Timeout, d.expireBy(&after));
}

test "contract: expireBy return type is TimeoutError!void and excludes Overflow" {
    const info = @typeInfo(@TypeOf(Deadline.expireBy)).@"fn";
    const Ret = info.return_type.?;
    try testing.expect(Ret == Deadline.TimeoutError!void);

    const err_info = @typeInfo(Ret).error_union;
    const ErrSet = err_info.error_set;
    // error.Overflow is not a member of TimeoutError.
    try testing.expect(ErrSet == error{Timeout});
}

test "contract: Deadline.now return type is OverflowError!Deadline" {
    const info = @typeInfo(@TypeOf(Deadline.now)).@"fn";
    const Ret = info.return_type.?;
    try testing.expect(Ret == Deadline.OverflowError!Deadline);
}

// Compile-only positive shapes: `requireClock` accepts a pointer to a type
// whose `now(*Self) Instant` matches the backend contract.
comptime {
    // FakeClock satisfies the contract via `pub fn now(*FakeClock) Instant`.
    var clock: FakeClock = .{ .current = Instant.fromNanos(0) };
    _ = Deadline.at(Instant.zero()).expired(&clock);
    _ = Deadline.at(Instant.zero()).remaining(&clock);
    _ = Deadline.at(Instant.zero()).expireBy(&clock) catch {};
}

// Compile-only rejection shapes, guarded by `@compileError` inside
// `requireClock` in `src/time/deadline.zig`. Zig has no runtime probe for
// `@compileError`, so these are pinned by inspection of the source:
//   * missing `now` decl                → "is missing pub fn now(*Self) Instant"
//   * `now` returns `anyerror!Instant`  → "must return Instant, not an error union or anyerror"
//   * `now` returns a plain error union → same message
//   * wrong receiver (e.g. `now()` with no self) → "must take exactly one argument (*Self)"
//   * wrong receiver type (e.g. `now(Self)`)     → "must take *<Self>, got <type>"
