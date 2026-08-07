//! Deadline anchor for poll loops. See `docs/specs/time/deadline.md`.

const std = @import("std");

const monotonic = @import("monotonic.zig");

const Duration = monotonic.Duration;
const Instant = monotonic.Instant;

/// Monotonic-nanosecond deadline value. It only reads the supplied clock
/// through `now`.
pub const Deadline = enum(u64) {
    _,

    pub const Raw = u64;
    pub const OverflowError = error{Overflow};
    pub const TimeoutError = error{Timeout};

    /// Represents no expiry. It uses `maxInt(u64)`, so `expired` is false
    /// unless the clock returns `maxInt(u64)`.
    pub const never: Deadline = @enumFromInt(std.math.maxInt(u64));

    pub fn at(instant_value: Instant) Deadline {
        return @enumFromInt(instant_value.nanos());
    }

    pub fn now(clock: anytype, delta: Duration) OverflowError!Deadline {
        comptime requireClock(@TypeOf(clock));
        const target = try clock.now().add(delta);
        return @enumFromInt(target.nanos());
    }

    pub fn instant(self: Deadline) Instant {
        return Instant.fromNanos(@intFromEnum(self));
    }

    pub fn isNever(self: Deadline) bool {
        return @intFromEnum(self) == std.math.maxInt(u64);
    }

    /// Reports true at or after the deadline.
    pub fn expired(self: Deadline, clock: anytype) bool {
        comptime requireClock(@TypeOf(clock));
        return clock.now().afterOrEq(self.instant());
    }

    /// Returns a signed duration: positive before, zero at, and negative
    /// after the deadline. `never` returns `maxInt(i64)`.
    pub fn remaining(self: Deadline, clock: anytype) Duration {
        comptime requireClock(@TypeOf(clock));
        if (self.isNever()) return Duration.fromNanos(std.math.maxInt(i64));
        return self.instant().since(clock.now());
    }

    pub fn expireBy(self: Deadline, clock: anytype) TimeoutError!void {
        comptime requireClock(@TypeOf(clock));
        if (self.expired(clock)) return error.Timeout;
    }

    comptime {
        std.debug.assert(@sizeOf(Deadline) == 8);
    }
};

/// Validates the compile-time `clock: anytype` seam. Accepts `C` or `*C`;
/// rejects a missing or incompatible `now` method and error-union returns.
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
