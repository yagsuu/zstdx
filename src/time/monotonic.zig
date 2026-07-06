//! Monotonic clock, Instant, and Duration value types. See
//! docs/specs/time/monotonic.md.

const std = @import("std");

const debug = @import("../core/debug.zig");

/// Monotonic point-in-time value with `u64` nanoseconds of range. The domain
/// covers approximately 584 years relative to the backend's epoch.
pub const Instant = enum(u64) {
    _,

    /// Underlying unsigned nanosecond representation.
    pub const Raw = u64;

    /// `Overflow`: `Instant.add` would push the result below `0` or above
    /// `maxInt(u64)`.
    pub const Error = error{Overflow};

    pub fn fromNanos(ns: u64) Instant {
        return @enumFromInt(ns);
    }

    pub fn nanos(self: Instant) u64 {
        return @intFromEnum(self);
    }

    /// Sentinel at nanosecond `0`. Epoch semantics are backend-defined.
    pub fn zero() Instant {
        return fromNanos(0);
    }

    /// Signed offset from `self` by `delta`. Returns `error.Overflow` when
    /// the result would fall below `0` or exceed `maxInt(u64)`.
    pub fn add(self: Instant, delta: Duration) Error!Instant {
        const wide = @as(i128, self.nanos()) + @as(i128, delta.nanos());
        const narrowed = std.math.cast(u64, wide) orelse return error.Overflow;
        return fromNanos(narrowed);
    }

    /// Signed difference `self - base`. Negative when `self < base`. The
    /// primitive's contract requires separation fit within `i64` (`±292`
    /// years); wider gaps are outside the contract.
    pub fn since(self: Instant, base: Instant) Duration {
        const wide = @as(i128, self.nanos()) - @as(i128, base.nanos());
        const narrowed = std.math.cast(i64, wide) orelse unreachable;
        return Duration.fromNanos(narrowed);
    }

    /// True when `self` is at or after `other`. Equality uses `==`.
    pub fn afterOrEq(self: Instant, other: Instant) bool {
        return self.nanos() >= other.nanos();
    }
};

/// Signed nanosecond difference with `i64` range (`±292` years). Negative
/// durations model "before" relationships.
pub const Duration = enum(i64) {
    _,

    /// Underlying signed nanosecond representation.
    pub const Raw = i64;

    /// `Overflow`: `Duration.from{Micros,Millis,Seconds}` multiplication
    /// exceeds `i64` range.
    pub const Error = error{Overflow};

    /// The zero-length duration.
    pub const zero: Duration = @enumFromInt(0);

    pub fn fromNanos(ns: i64) Duration {
        return @enumFromInt(ns);
    }

    pub fn nanos(self: Duration) i64 {
        return @intFromEnum(self);
    }

    /// `us * 1_000` as a `Duration`. Returns `error.Overflow` when the
    /// multiplication overflows `i64`.
    pub fn fromMicros(us: i64) Error!Duration {
        return fromNanos(std.math.mul(i64, us, 1_000) catch return error.Overflow);
    }

    /// `ms * 1_000_000` as a `Duration`. Returns `error.Overflow` when the
    /// multiplication overflows `i64`.
    pub fn fromMillis(ms: i64) Error!Duration {
        return fromNanos(std.math.mul(i64, ms, 1_000_000) catch return error.Overflow);
    }

    /// `s * 1_000_000_000` as a `Duration`. Returns `error.Overflow` when the
    /// multiplication overflows `i64`.
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

/// Clock family namespace. Owns the monotonic-clock wrapper factory.
pub const Clock = struct {
    /// Wrap a caller-supplied `Backend` with the monotonic-reader
    /// contract.
    ///
    /// `Backend` must expose `pub fn now(*Backend) Instant`. It may also
    /// expose `pub fn sleep(*Backend, Duration) void`; when present, the
    /// wrapper exposes a forwarding `sleep` method. Both signatures are
    /// validated at compile time; error unions are rejected.
    ///
    /// `Backend` is stored by value. Not thread-safe; single-owner.
    ///
    /// Under `core.debug.checksEnabled(.build_mode)` `now` asserts
    /// monotonicity against the previous return and `sleep` asserts
    /// `delta.nanos() >= 0`. In release builds both methods compile to
    /// one backend call plus a return.
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

                /// Return the backend's current instant. Under
                /// `.build_mode` safety, assert monotonicity against the
                /// previous return.
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

            /// Return the backend's current instant. Under `.build_mode`
            /// safety, assert monotonicity against the previous return.
            pub fn now(self: *Self) Instant {
                const t = self.backend.now();
                if (check_monotonic) {
                    std.debug.assert(t.nanos() >= self.last.nanos());
                    self.last = t;
                }
                return t;
            }

            /// Forward `delta` to the backend. Under `.build_mode` safety,
            /// assert `delta.nanos() >= 0`; non-positive deltas are legal
            /// on the backend seam.
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
