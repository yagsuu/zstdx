//! Deadline anchor for poll loops. Spec: docs/specs/time/deadline.md.

const std = @import("std");

const monotonic = @import("monotonic.zig");

const Instant = monotonic.Instant;
const Duration = monotonic.Duration;

/// Monotonic-nanosecond deadline anchor. A value type that composes with any
/// clock exposing `pub fn now(*Self) Instant`. `Deadline` never sleeps,
/// parks, or touches the backend beyond calling `Backend.now()`.
pub const Deadline = enum(u64) {
    _,

    /// Underlying unsigned nanosecond representation.
    pub const Raw = u64;

    /// `Overflow`: `Deadline.now` addition of `delta` would push past
    /// `maxInt(u64)` or below `0`.
    pub const OverflowError = error{Overflow};

    /// `Timeout`: `Deadline.expireBy` observed the deadline already reached.
    pub const TimeoutError = error{Timeout};

    /// Sentinel meaning "never expires". Represented as `maxInt(u64)` so
    /// `expired` naturally reports `false` against any clock reading in the
    /// practical domain.
    pub const never: Deadline = @enumFromInt(std.math.maxInt(u64));

    /// Anchor at an explicit instant. Infallible.
    pub fn at(instant_value: Instant) Deadline {
        return @enumFromInt(instant_value.nanos());
    }

    /// Anchor at `clock.now() + delta`. Propagates `error.Overflow` from
    /// `Instant.add`.
    pub fn now(clock: anytype, delta: Duration) OverflowError!Deadline {
        comptime requireClock(@TypeOf(clock));
        const target = try clock.now().add(delta);
        return @enumFromInt(target.nanos());
    }

    /// Project back to the underlying `Instant`. Infallible.
    pub fn instant(self: Deadline) Instant {
        return Instant.fromNanos(@intFromEnum(self));
    }

    /// True when `self` is the `never` sentinel.
    pub fn isNever(self: Deadline) bool {
        return @intFromEnum(self) == std.math.maxInt(u64);
    }

    /// True when `clock.now() >= self.instant()`. Boundary: at equality
    /// returns `true`.
    pub fn expired(self: Deadline, clock: anytype) bool {
        comptime requireClock(@TypeOf(clock));
        return clock.now().afterOrEq(self.instant());
    }

    /// Signed remaining duration. Positive before the deadline, zero at the
    /// exact boundary, negative after. `never` saturates at `maxInt(i64)`.
    pub fn remaining(self: Deadline, clock: anytype) Duration {
        comptime requireClock(@TypeOf(clock));
        if (self.isNever()) return Duration.fromNanos(std.math.maxInt(i64));
        return self.instant().since(clock.now());
    }

    /// `error.Timeout` when the deadline is expired against `clock`, else
    /// `void`. The composition point for bounded poll loops.
    pub fn expireBy(self: Deadline, clock: anytype) TimeoutError!void {
        comptime requireClock(@TypeOf(clock));
        if (self.expired(clock)) return error.Timeout;
    }

    comptime {
        std.debug.assert(@sizeOf(Deadline) == 8);
    }
};

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
            "Deadline: clock type " ++ @typeName(C) ++
                " is missing pub fn now(*Self) Instant",
        );
    }
    const NowFn = @TypeOf(@field(T, "now"));
    const info = switch (@typeInfo(NowFn)) {
        .@"fn" => |f| f,
        else => @compileError(
            "Deadline: " ++ @typeName(T) ++ ".now must be a function",
        ),
    };
    if (info.params.len != 1) {
        @compileError(
            "Deadline: " ++ @typeName(T) ++
                ".now must take exactly one argument (*Self)",
        );
    }
    const P0 = info.params[0].type orelse @compileError(
        "Deadline: " ++ @typeName(T) ++ ".now must take (*Self), not anytype",
    );
    if (P0 != *T) {
        @compileError(
            "Deadline: " ++ @typeName(T) ++
                ".now must take *" ++ @typeName(T) ++
                ", got " ++ @typeName(P0),
        );
    }
    const Ret = info.return_type orelse @compileError(
        "Deadline: " ++ @typeName(T) ++ ".now must return Instant",
    );
    if (Ret != Instant) {
        @compileError(
            "Deadline: " ++ @typeName(T) ++
                ".now must return Instant, not an error union or anyerror; got " ++
                @typeName(Ret),
        );
    }
}
