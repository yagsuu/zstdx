//! Monotonic clock, `Instant`, and `Duration` value types.
//! See `docs/specs/time/monotonic.md`.

const std = @import("std");

const debug = @import("../core/debug.zig");

/// Monotonic point in time with a `u64` nanosecond range of approximately
/// 584 years from the backend epoch.
pub const Instant = enum(u64) {
    _,

    pub const Raw = u64;

    pub const Error = error{Overflow};

    pub fn fromNanos(ns: u64) Instant {
        return @enumFromInt(ns);
    }

    pub fn nanos(self: Instant) u64 {
        return @intFromEnum(self);
    }

    /// Returns nanosecond zero. The backend defines its epoch.
    pub fn zero() Instant {
        return fromNanos(0);
    }

    /// Returns `error.Overflow` if the result falls outside the `u64` range.
    pub fn add(self: Instant, delta: Duration) Error!Instant {
        const wide = @as(i128, self.nanos()) + @as(i128, delta.nanos());
        const narrowed = std.math.cast(u64, wide) orelse return error.Overflow;
        return fromNanos(narrowed);
    }

    /// Returns `self - base`. The separation must fit within `i64` (±292
    /// years); wider gaps are outside the contract.
    pub fn since(self: Instant, base: Instant) Duration {
        const wide = @as(i128, self.nanos()) - @as(i128, base.nanos());
        const narrowed = std.math.cast(i64, wide) orelse unreachable;
        return Duration.fromNanos(narrowed);
    }

    pub fn afterOrEq(self: Instant, other: Instant) bool {
        return self.nanos() >= other.nanos();
    }
};

/// Signed nanosecond duration with an `i64` range of approximately ±292 years.
/// Negative values represent earlier instants.
pub const Duration = enum(i64) {
    _,

    pub const Raw = i64;

    pub const Error = error{Overflow};

    pub const zero: Duration = @enumFromInt(0);

    pub fn fromNanos(ns: i64) Duration {
        return @enumFromInt(ns);
    }

    pub fn nanos(self: Duration) i64 {
        return @intFromEnum(self);
    }

    /// Returns `error.Overflow` if `us * 1_000` exceeds `i64`.
    pub fn fromMicros(us: i64) Error!Duration {
        return fromNanos(std.math.mul(i64, us, 1_000) catch return error.Overflow);
    }

    /// Returns `error.Overflow` if `ms * 1_000_000` exceeds `i64`.
    pub fn fromMillis(ms: i64) Error!Duration {
        return fromNanos(std.math.mul(i64, ms, 1_000_000) catch return error.Overflow);
    }

    /// Returns `error.Overflow` if `s * 1_000_000_000` exceeds `i64`.
    pub fn fromSeconds(s: i64) Error!Duration {
        return fromNanos(std.math.mul(i64, s, 1_000_000_000) catch return error.Overflow);
    }

    pub fn isPositive(self: Duration) bool {
        return self.nanos() > 0;
    }

    pub fn isNegative(self: Duration) bool {
        return self.nanos() < 0;
    }
};

pub const Clock = struct {
    /// Wraps a caller-supplied `Backend` in the monotonic-reader contract.
    ///
    /// `Backend` must provide `pub fn now(*Backend) Instant`. If it provides
    /// `pub fn sleep(*Backend, Duration) void`, the wrapper forwards `sleep`.
    /// Both signatures are validated at compile time; error unions are rejected.
    ///
    /// The wrapper stores `Backend` by value and is single-owner. In build-mode
    /// checks, `now` asserts monotonicity and `sleep` asserts a non-negative duration.
    pub fn Monotonic(comptime Backend: type) type {
        requireBackendNow(Backend);

        const check_monotonic = debug.checksEnabled(.build_mode);

        if (!@hasDecl(Backend, "sleep")) {
            return struct {
                backend: Backend,
                last: if (check_monotonic) Instant else void,

                const Self = @This();

                pub fn init(backend: Backend) Self {
                    return .{
                        .backend = backend,
                        .last = if (check_monotonic) Instant.zero() else {},
                    };
                }

                /// In build-mode checks, asserts that time never moves backwards.
                pub fn now(self: *Self) Instant {
                    const t = self.backend.now();
                    if (check_monotonic) {
                        std.debug.assert(t.nanos() >= self.last.nanos());
                        self.last = t;
                    }
                    return t;
                }
            };
        }

        requireBackendSleep(Backend);

        return struct {
            backend: Backend,
            last: if (check_monotonic) Instant else void,

            const Self = @This();

            pub fn init(backend: Backend) Self {
                return .{
                    .backend = backend,
                    .last = if (check_monotonic) Instant.zero() else {},
                };
            }

            /// In build-mode checks, asserts that time never moves backwards.
            pub fn now(self: *Self) Instant {
                const t = self.backend.now();
                if (check_monotonic) {
                    std.debug.assert(t.nanos() >= self.last.nanos());
                    self.last = t;
                }
                return t;
            }

            /// The backend seam permits negative `delta`; build-mode checks
            /// assert a non-negative duration.
            pub fn sleep(self: *Self, delta: Duration) void {
                if (check_monotonic) std.debug.assert(delta.nanos() >= 0);
                self.backend.sleep(delta);
            }
        };
    }
};

fn requireBackendNow(comptime Backend: type) void {
    if (!@hasDecl(Backend, "now")) {
        @compileError("Clock.Monotonic backend: missing pub fn now(*Backend) Instant");
    }
    const info = @typeInfo(@TypeOf(Backend.now)).@"fn";
    if (info.return_type.? != Instant) {
        @compileError(
            "Clock.Monotonic backend: now must return Instant, " ++
                "not an error union or another type",
        );
    }
}

fn requireBackendSleep(comptime Backend: type) void {
    const info = @typeInfo(@TypeOf(Backend.sleep)).@"fn";
    if (info.params.len != 2) {
        @compileError("Clock.Monotonic backend: sleep must be fn(*Backend, Duration) void");
    }
    if (info.params[0].type.? != *Backend) {
        @compileError("Clock.Monotonic backend: sleep first parameter must be *Backend");
    }
    if (info.params[1].type.? != Duration) {
        @compileError("Clock.Monotonic backend: sleep second parameter must be Duration");
    }
    if (info.return_type.? != void) {
        @compileError(
            "Clock.Monotonic backend: sleep must return void, " ++
                "not an error union or another type",
        );
    }
}
