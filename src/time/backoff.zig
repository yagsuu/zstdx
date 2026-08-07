//! Retry-delay generator. See `docs/specs/time/backoff.md`.

const std = @import("std");

const debug = @import("../core/debug.zig");
const deadline = @import("deadline.zig");
const monotonic = @import("monotonic.zig");

const Deadline = deadline.Deadline;
const Duration = monotonic.Duration;
const Instant = monotonic.Instant;

/// Retry-delay state machine. The caller performs each returned action. This
/// single-owner value type neither allocates nor sleeps; it reads time only
/// through the supplied `Deadline`.
pub const Backoff = struct {
    policy: Policy,
    attempt: u32,
    next_wait: Duration,

    /// Field order matches the specification's Approved API.
    pub const Policy = struct {
        spin_iterations: u32,
        yield_iterations: u32,
        yield: ?*const fn () void,
        initial_wait: Duration,
        max_wait: Duration,
        growth_shift: u3,

        /// Asserts `initial_wait >= 0`, `max_wait >= 0`, and
        /// `initial_wait <= max_wait`. Runs unconditionally.
        pub fn assertValid(self: Policy) void {
            std.debug.assert(self.initial_wait.nanos() >= 0);
            std.debug.assert(self.max_wait.nanos() >= 0);
            std.debug.assert(self.initial_wait.nanos() <= self.max_wait.nanos());
        }
    };

    pub const Step = union(enum) {
        spin,
        yield,
        sleep: Duration,
        timeout,
    };

    /// In build-mode checks, invokes `policy.assertValid()`.
    pub fn init(policy: Policy) Backoff {
        if (debug.checksEnabled(.build_mode)) policy.assertValid();
        return .{
            .policy = policy,
            .attempt = 0,
            .next_wait = policy.initial_wait,
        };
    }

    pub fn reset(self: *Backoff) void {
        self.attempt = 0;
        self.next_wait = self.policy.initial_wait;
    }

    /// `clock` must provide `pub fn now(*Self) Instant`; error unions are
    /// rejected at compile time. An expired `dl` returns `.timeout` before
    /// spin or yield. Sleep duration is limited to the remaining time.
    /// `attempt` increments only for `.spin`, `.yield`, and `.sleep`.
    pub fn next(self: *Backoff, dl: Deadline, clock: anytype) Step {
        comptime requireClock(@TypeOf(clock));

        if (dl.expired(clock)) return .timeout;

        if (self.attempt < self.policy.spin_iterations) {
            self.attempt += 1;
            return .spin;
        }

        const yield_end = self.policy.spin_iterations + self.policy.yield_iterations;
        if (self.policy.yield != null and self.attempt < yield_end) {
            self.attempt += 1;
            return .yield;
        }

        return self.sleepStep(dl, clock);
    }

    fn sleepStep(self: *Backoff, dl: Deadline, clock: anytype) Step {
        const remaining_ns = dl.remaining(clock).nanos();
        if (remaining_ns <= 0) return .timeout;

        const wait_ns_i64 = @min(self.next_wait.nanos(), remaining_ns);
        std.debug.assert(wait_ns_i64 >= 0);

        self.next_wait = growWait(self.next_wait, self.policy);
        self.attempt += 1;
        return .{ .sleep = Duration.fromNanos(wait_ns_i64) };
    }

    pub fn attempts(self: *const Backoff) u32 {
        return self.attempt;
    }

    /// Asserts the policy invariant and `next_wait` bounds. Runs
    /// unconditionally.
    pub fn assertValid(self: *const Backoff) void {
        self.policy.assertValid();
        std.debug.assert(self.next_wait.nanos() >= 0);
        std.debug.assert(self.next_wait.nanos() <= self.policy.max_wait.nanos());
    }
};

/// Uses `i128` so shifting an `i64` by `growth_shift` cannot overflow before
/// the result is clamped to `max_wait`.
fn growWait(wait: Duration, policy: Backoff.Policy) Duration {
    const shifted: i128 = @as(i128, wait.nanos()) << policy.growth_shift;
    const ceiling: i128 = @as(i128, policy.max_wait.nanos());
    const clamped: i64 = if (shifted > ceiling) @intCast(ceiling) else @intCast(shifted);
    return Duration.fromNanos(clamped);
}

/// Validates the compile-time `clock: anytype` seam. Accepts `C` or `*C`;
/// rejects a missing or incompatible `now` method and error-union returns.
fn requireClock(comptime C: type) void {
    const T = switch (@typeInfo(C)) {
        .pointer => |p| p.child,
        else => C,
    };

    if (!@hasDecl(T, "now")) {
        @compileError(
            "Backoff: clock type " ++ @typeName(C) ++
                " is missing pub fn now(*Self) Instant",
        );
    }

    const NowFn = @TypeOf(@field(T, "now"));
    const info = switch (@typeInfo(NowFn)) {
        .@"fn" => |f| f,
        else => @compileError(
            "Backoff: " ++ @typeName(T) ++ ".now must be a function",
        ),
    };

    if (info.params.len != 1) {
        @compileError(
            "Backoff: " ++ @typeName(T) ++
                ".now must take exactly one argument (*Self)",
        );
    }

    const P0 = info.params[0].type orelse @compileError(
        "Backoff: " ++ @typeName(T) ++ ".now must take (*Self), not anytype",
    );

    if (P0 != *T) {
        @compileError(
            "Backoff: " ++ @typeName(T) ++
                ".now must take *" ++ @typeName(T) ++
                ", got " ++ @typeName(P0),
        );
    }

    const Ret = info.return_type orelse @compileError(
        "Backoff: " ++ @typeName(T) ++ ".now must return Instant",
    );

    if (Ret != Instant) {
        @compileError(
            "Backoff: " ++ @typeName(T) ++
                ".now must return Instant, not an error union or anyerror; got " ++
                @typeName(Ret),
        );
    }
}
