//! Retry-delay generator. Spec: docs/specs/time/backoff.md.

const std = @import("std");

const debug = @import("../core/debug.zig");
const deadline = @import("deadline.zig");
const monotonic = @import("monotonic.zig");

const Deadline = deadline.Deadline;
const Duration = monotonic.Duration;
const Instant = monotonic.Instant;

/// Structured retry-delay state machine. The primitive owns the phase
/// progression and per-step deadline clipping; the caller executes the
/// returned action (spin, yield, sleep, timeout). Never allocates, never
/// sleeps, never touches the clock beyond querying the supplied
/// `Deadline`. Single-owner value type.
pub const Backoff = struct {
    /// Tuning knobs. Field order matches the spec's Approved API.
    pub const Policy = struct {
        spin_iterations: u32,
        yield_iterations: u32,
        yield: ?*const fn () void,
        initial_wait: Duration,
        max_wait: Duration,
        growth_shift: u3,

        /// Assert `initial_wait` and `max_wait` are non-negative and
        /// `initial_wait <= max_wait`. Runs unconditionally.
        pub fn assertValid(self: Policy) void {
            std.debug.assert(self.initial_wait.nanos() >= 0);
            std.debug.assert(self.max_wait.nanos() >= 0);
            std.debug.assert(self.initial_wait.nanos() <= self.max_wait.nanos());
        }
    };

    /// Phase result returned by `next`.
    pub const Step = union(enum) {
        spin,
        yield,
        sleep: Duration,
        timeout,
    };

    policy: Policy,
    attempt: u32,
    next_wait: Duration,

    /// Construct a `Backoff` seeded with `policy.initial_wait`. Under
    /// `stdx.core.debug.checksEnabled(.build_mode)`, `policy.assertValid()`
    /// runs.
    pub fn init(policy: Policy) Backoff {
        if (debug.checksEnabled(.build_mode)) policy.assertValid();
        return .{
            .policy = policy,
            .attempt = 0,
            .next_wait = policy.initial_wait,
        };
    }

    /// Restore `attempt = 0` and `next_wait = policy.initial_wait`.
    /// `policy` is untouched.
    pub fn reset(self: *Backoff) void {
        self.attempt = 0;
        self.next_wait = self.policy.initial_wait;
    }

    /// Advance the backoff by one step. `clock` must expose
    /// `pub fn now(*Self) Instant`; error unions are rejected at compile
    /// time. Deadline check runs first; a caller past `deadline` never
    /// enters spin or yield. Sleep steps are clipped to the remaining
    /// deadline. `attempt` increments on productive results only
    /// (`.spin`, `.yield`, `.sleep`); `.timeout` leaves it unchanged.
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

    /// Return the running productive-attempt count.
    pub fn attempts(self: *const Backoff) u32 {
        return self.attempt;
    }

    /// Assert `policy.assertValid()` and that `next_wait` sits in
    /// `[0, policy.max_wait]`. Runs unconditionally; consumers gate the
    /// call under `checksEnabled(.build_mode)`.
    pub fn assertValid(self: *const Backoff) void {
        self.policy.assertValid();
        std.debug.assert(self.next_wait.nanos() >= 0);
        std.debug.assert(self.next_wait.nanos() <= self.policy.max_wait.nanos());
    }
};

/// Left-shift `wait.nanos()` by `policy.growth_shift`, clamped to
/// `policy.max_wait`. `wait.nanos()` and `max_wait.nanos()` are
/// non-negative by policy invariant, so the widened arithmetic never
/// underflows. `i128` fully contains any `i64 << 7`, so overflow of the
/// shift itself cannot occur; the only clamp point is the `max_wait`
/// ceiling.
fn growWait(wait: Duration, policy: Backoff.Policy) Duration {
    const shifted: i128 = @as(i128, wait.nanos()) << policy.growth_shift;
    const ceiling: i128 = @as(i128, policy.max_wait.nanos());
    const clamped: i64 = if (shifted > ceiling) @intCast(ceiling) else @intCast(shifted);
    return Duration.fromNanos(clamped);
}

/// Compile-time signature check for the `clock: anytype` seam. Accepts a
/// value type `C` or a single-pointer wrapper `*C`. Rejects: missing `now`,
/// wrong arity, non-`*Self` receiver, and `anyerror` / error-union returns.
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
