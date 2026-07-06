//! Fixed-rate counter projection of `Instant` with wrap-edge detection.
//! Spec: docs/specs/time/rate-counter.md.

const std = @import("std");

const debug = @import("../core/debug.zig");
const monotonic = @import("monotonic.zig");

const Instant = monotonic.Instant;

const nanos_per_second: u128 = 1_000_000_000;

/// Projects a monotonic-clock reading into a fixed-rate integer counter of
/// configurable bit width, tracking wrap events across `sample` calls.
/// Never allocates, never touches the clock beyond `Backend.now()`.
/// Single-owner value type; concurrent callers serialize externally.
pub const RateCounter = struct {
    /// Identity of a `RateCounter`: anchor instant, tick rate, counter
    /// width. Callers who want to change any field discard the value and
    /// construct a fresh `RateCounter`.
    pub const Config = struct {
        base: Instant,
        rate_hz: u64,
        width_bits: u7,

        /// Assert `rate_hz > 0` and `width_bits` in `1..=64`. Runs
        /// unconditionally.
        pub fn assertValid(self: Config) void {
            std.debug.assert(self.rate_hz > 0);
            std.debug.assert(self.width_bits >= 1);
            std.debug.assert(self.width_bits <= 64);
        }
    };

    /// Result of `sample`: projected counter value and whether the
    /// unbounded tick count crossed a `1 << width_bits` boundary since
    /// the previous `sample`.
    pub const Sample = struct {
        value: u64,
        wrapped: bool,
    };

    base: Instant,
    rate_hz: u64,
    width_bits: u7,
    last_wrap_count: u64,

    const Self = @This();

    comptime {
        std.debug.assert(@sizeOf(Self) == 32);
    }

    /// Construct with `last_wrap_count = 0`. Under
    /// `stdx.core.debug.checksEnabled(.build_mode)`, runs
    /// `config.assertValid()`.
    pub fn init(config: Config) Self {
        if (debug.checksEnabled(.build_mode)) config.assertValid();
        return .{
            .base = config.base,
            .rate_hz = config.rate_hz,
            .width_bits = config.width_bits,
            .last_wrap_count = 0,
        };
    }

    /// Re-anchor `base` to `clock.now()` and clear the wrap-edge state.
    /// The next `sample` reports `wrapped = false`. Rate and width are
    /// preserved.
    pub fn reset(self: *Self, clock: anytype) void {
        comptime requireClock(@TypeOf(clock));
        self.base = clock.now();
        self.last_wrap_count = 0;
    }

    /// Return the projected counter value at `clock.now()` without
    /// updating the wrap-edge state. Safe to interleave with `sample`.
    pub fn peek(self: *const Self, clock: anytype) u64 {
        comptime requireClock(@TypeOf(clock));
        const p = project(self, clock.now());
        return p.value;
    }

    /// Sample the counter at `clock.now()`, advancing the wrap-edge
    /// state. `wrapped` is true iff the unbounded tick count crossed a
    /// `1 << width_bits` boundary since the previous `sample`, `init`,
    /// or `reset`.
    pub fn sample(self: *Self, clock: anytype) Sample {
        comptime requireClock(@TypeOf(clock));
        const p = project(self, clock.now());
        const wrapped = p.wrap_count > self.last_wrap_count;
        self.last_wrap_count = p.wrap_count;
        return .{ .value = p.value, .wrapped = wrapped };
    }

    /// Assert the embedded config invariants. Runs unconditionally.
    pub fn assertValid(self: *const Self) void {
        const c: Config = .{
            .base = self.base,
            .rate_hz = self.rate_hz,
            .width_bits = self.width_bits,
        };
        c.assertValid();
    }
};

const Projection = struct {
    value: u64,
    wrap_count: u64,
};

/// Project `now` through `self`'s rate and width. Compiled outside the
/// type body to keep the hot arithmetic free of `self`-field indirection
/// and to isolate the u128 intermediate.
fn project(self: *const RateCounter, now: Instant) Projection {
    if (debug.checksEnabled(.build_mode)) {
        std.debug.assert(now.afterOrEq(self.base));
    }

    // Debug builds trap above on `now < base`; release builds clamp the
    // elapsed to zero so the u128 cast is total, keeping the primitive
    // fault-free outside the checked contract.
    const elapsed_i64: i64 = now.since(self.base).nanos();
    const elapsed_ns: u128 = if (elapsed_i64 < 0) 0 else @intCast(elapsed_i64);
    const unbounded: u128 = (elapsed_ns * @as(u128, self.rate_hz)) / nanos_per_second;

    if (self.width_bits == 64) {
        return .{
            .value = @truncate(unbounded),
            .wrap_count = 0,
        };
    }

    const width_shift: u7 = self.width_bits;
    const mask: u128 = (@as(u128, 1) << width_shift) - 1;
    const value_u128: u128 = unbounded & mask;
    const wrap_u128: u128 = unbounded >> width_shift;

    return .{
        .value = @intCast(value_u128),
        .wrap_count = @intCast(wrap_u128),
    };
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
            "RateCounter: clock type " ++ @typeName(C) ++
                " is missing pub fn now(*Self) Instant",
        );
    }

    const NowFn = @TypeOf(@field(T, "now"));
    const info = switch (@typeInfo(NowFn)) {
        .@"fn" => |f| f,
        else => @compileError(
            "RateCounter: " ++ @typeName(T) ++ ".now must be a function",
        ),
    };

    if (info.params.len != 1) {
        @compileError(
            "RateCounter: " ++ @typeName(T) ++
                ".now must take exactly one argument (*Self)",
        );
    }

    const P0 = info.params[0].type orelse @compileError(
        "RateCounter: " ++ @typeName(T) ++ ".now must take (*Self), not anytype",
    );
    if (P0 != *T) {
        @compileError(
            "RateCounter: " ++ @typeName(T) ++
                ".now must take *" ++ @typeName(T) ++
                ", got " ++ @typeName(P0),
        );
    }

    const Ret = info.return_type orelse @compileError(
        "RateCounter: " ++ @typeName(T) ++ ".now must return Instant",
    );
    if (Ret != Instant) {
        @compileError(
            "RateCounter: " ++ @typeName(T) ++
                ".now must return Instant, not an error union or anyerror; got " ++
                @typeName(Ret),
        );
    }
}
