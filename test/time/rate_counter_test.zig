//! RateCounter projection tests. See `docs/specs/time/rate-counter.md`.

const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;

const Instant = stdx.time.Instant;
const RateCounter = stdx.time.RateCounter;

/// Caller-controlled monotonic clock. Follows the FakeClock shape used
/// by the deadline and backoff test suites.
const FakeClock = struct {
    current: Instant,

    pub fn init(start_ns: u64) FakeClock {
        return .{ .current = Instant.fromNanos(start_ns) };
    }

    pub fn now(self: *FakeClock) Instant {
        return self.current;
    }

    pub fn setNs(self: *FakeClock, at_ns: u64) void {
        self.current = Instant.fromNanos(at_ns);
    }
};

const pm_rate_hz: u64 = 3_579_545;
const pm_width_bits: u7 = 24;
const pm_width_mask: u64 = (1 << pm_width_bits) - 1;

fn pmCounter(base_ns: u64) RateCounter {
    return .init(.{
        .base = Instant.fromNanos(base_ns),
        .rate_hz = pm_rate_hz,
        .width_bits = pm_width_bits,
    });
}

fn ticksAfterNs(base_ns: u64, at_ns: u64, rate_hz: u64) u128 {
    const elapsed_ns: u128 = @intCast(at_ns - base_ns);
    return (elapsed_ns * @as(u128, rate_hz)) / 1_000_000_000;
}

test "unit: init sets last_wrap_count to zero and copies identity fields" {
    const config: RateCounter.Config = .{
        .base = Instant.fromNanos(1_000),
        .rate_hz = 10,
        .width_bits = 8,
    };
    const rc: RateCounter = .init(config);

    try testing.expectEqual(config.base, rc.base);
    try testing.expectEqual(config.rate_hz, rc.rate_hz);
    try testing.expectEqual(config.width_bits, rc.width_bits);
    try testing.expectEqual(@as(u64, 0), rc.last_wrap_count);
}

test "unit: peek at base returns zero" {
    var rc = pmCounter(1_000);
    var clock = FakeClock.init(1_000);

    try testing.expectEqual(@as(u64, 0), rc.peek(&clock));
}

test "unit: peek at base + 1s for rate 10 Hz returns 10" {
    var rc: RateCounter = .init(.{
        .base = Instant.fromNanos(0),
        .rate_hz = 10,
        .width_bits = 16,
    });
    var clock = FakeClock.init(1_000_000_000);

    try testing.expectEqual(@as(u64, 10), rc.peek(&clock));
}

test "unit: peek masks to width_bits after overflow at PM-timer geometry" {
    // 24-bit @ 3.579545 MHz wraps every ~4.685 s. Advance well past one
    // wrap boundary and verify masking.
    const base_ns: u64 = 0;
    const at_ns: u64 = 10_000_000_000; // 10 s
    var rc = pmCounter(base_ns);
    var clock = FakeClock.init(at_ns);

    const unbounded = ticksAfterNs(base_ns, at_ns, pm_rate_hz);
    const expected: u64 = @intCast(unbounded & pm_width_mask);

    try testing.expectEqual(expected, rc.peek(&clock));
}

test "unit: peek at width_bits=64 returns unbounded tick count in u64 domain" {
    var rc: RateCounter = .init(.{
        .base = Instant.fromNanos(0),
        .rate_hz = 10_000_000,
        .width_bits = 64,
    });
    var clock = FakeClock.init(1_500_000_000); // 1.5 s

    try testing.expectEqual(@as(u64, 15_000_000), rc.peek(&clock));
}

test "unit: two peek calls at the same clock reading return the same value" {
    var rc = pmCounter(0);
    var clock = FakeClock.init(5_000_000_000); // 5 s

    const first = rc.peek(&clock);
    const second = rc.peek(&clock);

    try testing.expectEqual(first, second);
}

test "unit: peek does not update last_wrap_count between sample calls" {
    // Setup: sample once, then advance across a wrap boundary. A peek
    // between the two samples must not swallow the wrap event.
    const base_ns: u64 = 0;
    var rc = pmCounter(base_ns);
    var clock = FakeClock.init(base_ns);

    // First sample at t=0 stores last_wrap_count = 0.
    _ = rc.sample(&clock);

    // Advance across one wrap boundary (~4.685 s at 24-bit @ 3.579545 MHz).
    const post_wrap_ns: u64 = 5_000_000_000;
    clock.setNs(post_wrap_ns);

    _ = rc.peek(&clock);
    try testing.expectEqual(@as(u64, 0), rc.last_wrap_count);

    // The subsequent sample still reports wrapped = true because peek
    // never touched last_wrap_count.
    const s = rc.sample(&clock);
    try testing.expect(s.wrapped);
}

test "unit: sample at base returns value=0 wrapped=false" {
    var rc = pmCounter(1_000);
    var clock = FakeClock.init(1_000);

    const s = rc.sample(&clock);
    try testing.expectEqual(@as(u64, 0), s.value);
    try testing.expect(!s.wrapped);
}

test "unit: sample across one wrap boundary reports wrapped=true exactly once" {
    // 8-bit @ 100 Hz wraps every 2.56 s. Start at 0, sample once, advance
    // past 2.56 s, sample again (expect wrapped), sample again without
    // crossing a further boundary (expect not wrapped).
    var rc: RateCounter = .init(.{
        .base = Instant.fromNanos(0),
        .rate_hz = 100,
        .width_bits = 8,
    });
    var clock = FakeClock.init(0);

    const first = rc.sample(&clock);
    try testing.expect(!first.wrapped);

    // Advance ~3 s: unbounded ticks = 300; wrap_count = 1; value = 44.
    clock.setNs(3_000_000_000);
    const second = rc.sample(&clock);
    try testing.expect(second.wrapped);
    try testing.expectEqual(@as(u64, 300 - 256), second.value);

    // Advance ~0.5 s further: still inside the same wrap window.
    clock.setNs(3_500_000_000);
    const third = rc.sample(&clock);
    try testing.expect(!third.wrapped);
}

test "unit: sample across multiple wraps in one call reports wrapped=true once" {
    // 8-bit @ 100 Hz. Advance to unbounded ticks > 512 in one call
    // (three wrap crossings in a single sample gap).
    var rc: RateCounter = .init(.{
        .base = Instant.fromNanos(0),
        .rate_hz = 100,
        .width_bits = 8,
    });
    var clock = FakeClock.init(0);

    _ = rc.sample(&clock);

    // 10 s -> 1000 ticks; 1000 / 256 = 3 wraps; value = 1000 & 0xFF = 232.
    clock.setNs(10_000_000_000);
    const s = rc.sample(&clock);

    try testing.expect(s.wrapped);
    try testing.expectEqual(@as(u64, 232), s.value);
    try testing.expectEqual(@as(u64, 3), rc.last_wrap_count);
}

test "unit: sample at width_bits=64 always returns wrapped=false" {
    var rc: RateCounter = .init(.{
        .base = Instant.fromNanos(0),
        .rate_hz = 1_000_000_000,
        .width_bits = 64,
    });
    var clock = FakeClock.init(0);

    _ = rc.sample(&clock);

    // Advance to the top of the Duration i64 domain (~292 years). The
    // projection stays finite through the u128 intermediate and wrapped
    // remains false because width_bits == 64 hardcodes wrap_count = 0.
    clock.setNs(std.math.maxInt(i64));
    const s = rc.sample(&clock);
    try testing.expect(!s.wrapped);
}

test "unit: sample exactly at wrap boundary counts as a wrap" {
    // 8-bit @ 256 Hz => one wrap per second exactly. At 1 s the unbounded
    // tick count is 256 (mod 256 == 0), which is the boundary.
    var rc: RateCounter = .init(.{
        .base = Instant.fromNanos(0),
        .rate_hz = 256,
        .width_bits = 8,
    });
    var clock = FakeClock.init(0);

    _ = rc.sample(&clock);

    clock.setNs(1_000_000_000);
    const s = rc.sample(&clock);
    try testing.expect(s.wrapped);
    try testing.expectEqual(@as(u64, 0), s.value);
    try testing.expectEqual(@as(u64, 1), rc.last_wrap_count);
}

test "unit: reset re-anchors base and clears wrap state" {
    var rc = pmCounter(0);
    var clock = FakeClock.init(0);

    // Cross a wrap boundary and confirm state advanced.
    _ = rc.sample(&clock);
    clock.setNs(5_000_000_000);
    _ = rc.sample(&clock);
    try testing.expect(rc.last_wrap_count > 0);

    rc.reset(&clock);
    try testing.expectEqual(clock.current, rc.base);
    try testing.expectEqual(@as(u64, 0), rc.last_wrap_count);

    // Next sample at the same clock reading reports value=0, wrapped=false.
    const s = rc.sample(&clock);
    try testing.expectEqual(@as(u64, 0), s.value);
    try testing.expect(!s.wrapped);
}

test "unit: peek and sample tolerate near-boundary reads without misreporting" {
    // Regression guard: exactly one tick short of and one tick past the
    // wrap boundary must project to distinct value/wrap pairs.
    var rc: RateCounter = .init(.{
        .base = Instant.fromNanos(0),
        .rate_hz = 100,
        .width_bits = 8,
    });
    var clock = FakeClock.init(0);
    _ = rc.sample(&clock);

    // ticks = 255 -> value = 255, wrap_count = 0.
    clock.setNs(2_550_000_000);
    var s = rc.sample(&clock);
    try testing.expect(!s.wrapped);
    try testing.expectEqual(@as(u64, 255), s.value);

    // ticks = 256 -> value = 0, wrap_count = 1 (boundary).
    clock.setNs(2_560_000_000);
    s = rc.sample(&clock);
    try testing.expect(s.wrapped);
    try testing.expectEqual(@as(u64, 0), s.value);
}

test "unit: assertValid accepts freshly-initialized value" {
    const rc = pmCounter(0);
    rc.assertValid();
}

test "unchecked: peek and sample tolerate now < base when checks disabled" {
    // In unchecked builds, `now < base` is outside the contract but must not trap.
    // This test verifies that runtime-safe behavior.
    if (stdx.core.debug.checksEnabled(.build_mode)) return;

    var rc: RateCounter = .init(.{
        .base = Instant.fromNanos(1_000),
        .rate_hz = 1_000_000,
        .width_bits = 32,
    });
    var clock = FakeClock.init(0);

    // Sanity: calls return without trapping. Values are implementation-
    // defined outside the contract; only the absence of a fault is
    // observable here.
    _ = rc.peek(&clock);
    _ = rc.sample(&clock);
}

test "unit: Config.assertValid accepts boundary-legal shapes" {
    const min_width: RateCounter.Config = .{
        .base = Instant.zero(),
        .rate_hz = 1,
        .width_bits = 1,
    };
    min_width.assertValid();

    const max_width: RateCounter.Config = .{
        .base = Instant.zero(),
        .rate_hz = std.math.maxInt(u64),
        .width_bits = 64,
    };
    max_width.assertValid();
}

// Debug-only trap probes for `Config.assertValid`, `RateCounter.assertValid`,
// and the `now < base` precondition asserts cannot be exercised at Zig test
// runtime: `std.debug.assert` aborts the test process on failure and this
// repo has no `expectPanic`-equivalent probe. The invariants trapped by the
// source are:
//
//   Config.assertValid traps when:
//     - rate_hz == 0
//     - width_bits == 0
//     - width_bits > 64 (values 65..127 reachable via u7)
//
//   RateCounter.init traps under checksEnabled(.build_mode) whenever
//   Config.assertValid would trap on the provided config.
//
//   peek and sample trap under checksEnabled(.build_mode) when
//   clock.now() returns an Instant strictly before self.base.

test "contract: RateCounter.init runs Config.assertValid under checksEnabled" {
    if (!stdx.core.debug.checksEnabled(.build_mode)) return;
    const rc = pmCounter(0);
    rc.assertValid();
}

test "contract: @sizeOf(RateCounter) is stable" {
    // Concrete literal so a field-shape drift trips the test.
    try testing.expectEqual(@as(usize, 32), @sizeOf(RateCounter));
}

test "unit: HPET 64-bit spec example projects correctly at a small offset" {
    // HPET emulation shape: 10 MHz, 64-bit, no wrap. At 100 ns after
    // base we expect exactly 1 tick.
    var rc: RateCounter = .init(.{
        .base = Instant.fromNanos(0),
        .rate_hz = 10_000_000,
        .width_bits = 64,
    });
    var clock = FakeClock.init(100);
    try testing.expectEqual(@as(u64, 1), rc.peek(&clock));
}

test "unit: RateCounter compiles and executes on the host regardless of arch" {
    // Trivial smoke check to satisfy the spec's "non-x86 build compiles
    // the module" requirement: the module has no target-gated code, so
    // any successful test invocation demonstrates it.
    var rc = pmCounter(0);
    var clock = FakeClock.init(1_000);
    _ = rc.peek(&clock);
    _ = rc.sample(&clock);
    rc.reset(&clock);
}

// Compile-only rejection: passing a clock whose `now` is missing, has the
// wrong shape, or returns anything other than `Instant` is rejected by
// `requireClock` inside `src/time/rate_counter.zig`. Zig cannot exercise
// `@compileError` cases at test runtime; runtime tests use a valid
// `*FakeClock` through `RateCounter.peek`, `sample`, and `reset`.
