//! Wait-for-value poll-loop composition. See `docs/specs/io/poll-until.md`.

const std = @import("std");

const debug = @import("../core/debug.zig");
const monotonic = @import("../time/monotonic.zig");
const deadline = @import("../time/deadline.zig");
const backoff = @import("../time/backoff.zig");

const Deadline = deadline.Deadline;
const Backoff = backoff.Backoff;
const Duration = monotonic.Duration;
const Instant = monotonic.Instant;

/// Concrete return type derived from a predicate's shape. For a predicate
/// whose call returns `PredicateError!?T`, the return type is
/// `(Deadline.TimeoutError || PredicateError)!T`. Exported so callers can
/// name the return type in intermediate signatures.
pub fn PollReturnType(comptime Predicate: type) type {
    const shape = analyzePredicate(Predicate);
    return (Deadline.TimeoutError || shape.error_set)!shape.payload;
}

/// Polls `predicate` until it returns a payload, propagates an error, or the
/// deadline expires.
/// Ordering: The predicate runs first on every iteration, and only `null`
/// advances the backoff.
/// Deadline: `Backoff.next` owns the deadline check per
/// `docs/specs/time/backoff.md`.
/// Effects: Does not allocate or lock. It accesses the clock and backoff only
/// through their public contracts. The caller owns `*Backoff`.
pub fn until(
    clock: anytype,
    dl: Deadline,
    bo: *Backoff,
    predicate: anytype,
) PollReturnType(@TypeOf(predicate)) {
    comptime requireClock(@TypeOf(clock));

    while (true) {
        if (try callPredicate(predicate)) |payload| return payload;

        switch (bo.next(dl, clock)) {
            .spin => std.atomic.spinLoopHint(),
            .yield => {
                if (debug.checksEnabled(.build_mode)) {
                    std.debug.assert(bo.policy.yield != null);
                }

                bo.policy.yield.?();
            },
            .sleep => |d| clock.sleep(d),
            .timeout => return error.Timeout,
        }
    }
}

const PredicateShape = struct {
    error_set: type,
    payload: type,
};

fn analyzePredicate(comptime Predicate: type) PredicateShape {
    switch (@typeInfo(Predicate)) {
        .@"fn" => return analyzeCallable(Predicate, 0),
        .pointer => |ptr| switch (@typeInfo(ptr.child)) {
            .@"fn" => return analyzeCallable(ptr.child, 0),
            .@"struct" => return analyzeCallStruct(ptr.child),
            else => @compileError(
                "poll.until: predicate must be a callable function or a struct exposing " ++
                    "`pub fn call(...)`; got " ++ @typeName(Predicate),
            ),
        },
        .@"struct" => return analyzeCallStruct(Predicate),
        else => @compileError(
            "poll.until: predicate must be a callable function or a struct exposing " ++
                "`pub fn call(...)`; got " ++ @typeName(Predicate),
        ),
    }
}

fn analyzeCallStruct(comptime T: type) PredicateShape {
    if (!@hasDecl(T, "call")) {
        @compileError(
            "poll.until: predicate " ++ @typeName(T) ++
                " has no `call` method and is not a callable function",
        );
    }
    const CallFn = @TypeOf(@field(T, "call"));
    return analyzeCallable(CallFn, 1);
}

fn analyzeCallable(comptime F: type, comptime expected_params: usize) PredicateShape {
    const info = switch (@typeInfo(F)) {
        .@"fn" => |f| f,
        else => @compileError(
            "poll.until: expected function type, got " ++ @typeName(F),
        ),
    };
    if (info.params.len != expected_params) {
        const arity_msg = if (expected_params == 0)
            "callable function must take no parameters"
        else
            "predicate `call` must take exactly one parameter (the receiver)";
        @compileError("poll.until: " ++ arity_msg ++ "; got " ++ @typeName(F));
    }
    const Ret = info.return_type orelse @compileError(
        "poll.until: predicate return type is not known (generic return); got " ++
            @typeName(F),
    );
    return analyzeReturn(Ret, F);
}

fn analyzeReturn(comptime Ret: type, comptime Owner: type) PredicateShape {
    switch (@typeInfo(Ret)) {
        .error_union => |eu| {
            if (eu.error_set == anyerror) {
                @compileError(
                    "poll.until: predicate must declare an explicit error set, not `anyerror`; " ++
                        "on " ++ @typeName(Owner),
                );
            }
            const payload_info = @typeInfo(eu.payload);
            if (payload_info != .optional) {
                @compileError(
                    "poll.until: predicate payload must be optional (E!?T); " ++
                        "got non-optional payload in " ++ @typeName(Ret),
                );
            }
            return .{
                .error_set = eu.error_set,
                .payload = payload_info.optional.child,
            };
        },
        .optional => @compileError(
            "poll.until: predicate must return an error union (E!?T); got bare optional " ++
                @typeName(Ret),
        ),
        else => @compileError(
            "poll.until: predicate must return E!?T with optional payload; got " ++
                @typeName(Ret),
        ),
    }
}

fn CallReturn(comptime Predicate: type) type {
    const shape = analyzePredicate(Predicate);
    return shape.error_set!?shape.payload;
}

inline fn callPredicate(predicate: anytype) CallReturn(@TypeOf(predicate)) {
    const Predicate = @TypeOf(predicate);
    switch (@typeInfo(Predicate)) {
        .@"fn" => return predicate(),
        .pointer => |ptr| switch (@typeInfo(ptr.child)) {
            .@"fn" => return predicate(),
            else => return predicate.call(),
        },
        else => return predicate.call(),
    }
}

fn requireClock(comptime C: type) void {
    const T = switch (@typeInfo(C)) {
        .pointer => |ptr| ptr.child,
        else => C,
    };
    requireClockNow(C, T);
    requireClockSleep(C, T);
}

fn requireClockNow(comptime C: type, comptime T: type) void {
    if (!@hasDecl(T, "now")) {
        @compileError(
            "poll.until: clock type " ++ @typeName(C) ++
                " is missing pub fn now(*Self) Instant",
        );
    }
    const info = switch (@typeInfo(@TypeOf(@field(T, "now")))) {
        .@"fn" => |f| f,
        else => @compileError(
            "poll.until: " ++ @typeName(T) ++ ".now must be a function",
        ),
    };
    if (info.params.len != 1) {
        @compileError(
            "poll.until: " ++ @typeName(T) ++
                ".now must take exactly one argument (*Self)",
        );
    }
    const P0 = info.params[0].type orelse @compileError(
        "poll.until: " ++ @typeName(T) ++ ".now must take (*Self), not anytype",
    );
    if (P0 != *T) {
        @compileError(
            "poll.until: " ++ @typeName(T) ++ ".now must take *" ++ @typeName(T) ++
                ", got " ++ @typeName(P0),
        );
    }
    const Ret = info.return_type orelse @compileError(
        "poll.until: " ++ @typeName(T) ++ ".now must return Instant",
    );
    if (Ret != Instant) {
        @compileError(
            "poll.until: " ++ @typeName(T) ++
                ".now must return Instant, not an error union or anyerror; got " ++
                @typeName(Ret),
        );
    }
}

fn requireClockSleep(comptime C: type, comptime T: type) void {
    if (!@hasDecl(T, "sleep")) {
        @compileError(
            "poll.until: clock type " ++ @typeName(C) ++
                " is missing pub fn sleep(*Self, Duration) void",
        );
    }
    const info = switch (@typeInfo(@TypeOf(@field(T, "sleep")))) {
        .@"fn" => |f| f,
        else => @compileError(
            "poll.until: " ++ @typeName(T) ++ ".sleep must be a function",
        ),
    };
    if (info.params.len != 2) {
        @compileError(
            "poll.until: " ++ @typeName(T) ++
                ".sleep must take exactly two arguments (*Self, Duration)",
        );
    }
    const P0 = info.params[0].type orelse @compileError(
        "poll.until: " ++ @typeName(T) ++ ".sleep must take (*Self, Duration)",
    );
    if (P0 != *T) {
        @compileError(
            "poll.until: " ++ @typeName(T) ++ ".sleep must take *" ++ @typeName(T) ++
                " as first parameter, got " ++ @typeName(P0),
        );
    }
    const P1 = info.params[1].type orelse @compileError(
        "poll.until: " ++ @typeName(T) ++ ".sleep must take Duration as second parameter",
    );
    if (P1 != Duration) {
        @compileError(
            "poll.until: " ++ @typeName(T) ++
                ".sleep must take Duration as second parameter, got " ++ @typeName(P1),
        );
    }
    const Ret = info.return_type orelse @compileError(
        "poll.until: " ++ @typeName(T) ++ ".sleep must return void",
    );
    if (Ret != void) {
        @compileError(
            "poll.until: " ++ @typeName(T) ++
                ".sleep must return void, not an error union or anyerror; got " ++
                @typeName(Ret),
        );
    }
}
