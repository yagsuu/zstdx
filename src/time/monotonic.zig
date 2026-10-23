//! monotonic clocks and time values

const std = @import("std");

const debug = @import("core").debug;

/// nanoseconds since the backend epoch
pub const Instant = enum(u64) {
    _,

    pub const zero: Self = @enumFromInt(0);

    pub const Int = u64;
    pub const Error = error{Overflow};

    const Self = @This();

    pub fn fromNanos(ns: Int) Self {
        return @enumFromInt(ns);
    }

    pub fn nanos(self: Self) Int {
        return @intFromEnum(self);
    }

    pub fn add(self: Self, delta: Duration) Error!Self {
        const wide = @as(i128, self.nanos()) + @as(i128, delta.nanos());
        const narrowed = std.math.cast(Int, wide) orelse return error.Overflow;
        return fromNanos(narrowed);
    }

    pub fn since(self: Self, base: Self) Duration {
        const wide = @as(i128, self.nanos()) - @as(i128, base.nanos());
        const narrowed = std.math.cast(i64, wide) orelse unreachable;
        return Duration.fromNanos(narrowed);
    }

    pub fn isAtOrAfter(self: Self, other: Self) bool {
        return self.nanos() >= other.nanos();
    }
};

/// signed nanoseconds
pub const Duration = enum(i64) {
    _,

    pub const zero: Self = @enumFromInt(0);

    pub const Int = i64;
    pub const Error = error{Overflow};

    const Self = @This();

    pub fn fromNanos(ns: Int) Self {
        return @enumFromInt(ns);
    }

    pub fn nanos(self: Self) Int {
        return @intFromEnum(self);
    }

    pub fn fromMicros(us: Int) Error!Self {
        return fromNanos(std.math.mul(Int, us, 1_000) catch return error.Overflow);
    }

    pub fn fromMillis(ms: Int) Error!Self {
        return fromNanos(std.math.mul(Int, ms, 1_000_000) catch return error.Overflow);
    }

    pub fn fromSeconds(s: Int) Error!Self {
        return fromNanos(std.math.mul(Int, s, 1_000_000_000) catch return error.Overflow);
    }

    pub fn isPositive(self: Self) bool {
        return self.nanos() > 0;
    }

    pub fn isNegative(self: Self) bool {
        return self.nanos() < 0;
    }
};

pub const Clock = struct {
    pub fn Monotonic(comptime Backend: type) type {
        Impl.requireClock(Backend, "Clock.Monotonic backend");

        const checks = debug.checksEnabled();

        if (!@hasDecl(Backend, "sleep")) {
            return struct {
                backend: Backend,
                last: if (checks) Instant else void,

                const Self = @This();

                pub fn init(backend: Backend) Self {
                    return .{
                        .backend = backend,
                        .last = if (checks) Instant.zero else {},
                    };
                }

                pub fn now(self: *Self) Instant {
                    return Impl.now(Self, self);
                }
            };
        }

        Impl.requireSleep(Backend);

        return struct {
            backend: Backend,
            last: if (checks) Instant else void,

            const Self = @This();

            pub fn init(backend: Backend) Self {
                return .{
                    .backend = backend,
                    .last = if (checks) Instant.zero else {},
                };
            }

            pub fn now(self: *Self) Instant {
                return Impl.now(Self, self);
            }

            pub fn sleep(self: *Self, delta: Duration) void {
                if (checks) {
                    std.debug.assert(delta.nanos() >= 0);
                }
                self.backend.sleep(delta);
            }
        };
    }

    pub const Impl = struct {
        pub fn requireClock(comptime C: type, comptime kind: []const u8) void {
            const T = switch (@typeInfo(C)) {
                .pointer => |pointer| pointer.child,
                else => C,
            };

            if (!@hasDecl(T, "now")) {
                @compileError(kind ++ ": missing pub fn now(*Self) Instant");
            }

            const info = switch (@typeInfo(@TypeOf(T.now))) {
                .@"fn" => |info| info,
                else => @compileError(kind ++ ": now must be a function"),
            };

            if (info.params.len != 1) {
                @compileError(kind ++ ": now must take exactly one argument (*Self)");
            }

            const receiver = info.params[0].type orelse
                @compileError(kind ++ ": now must take (*Self), not anytype");

            if (receiver != *T) {
                @compileError(kind ++ ": now must take *" ++ @typeName(T));
            }

            const Return = info.return_type orelse
                @compileError(kind ++ ": now must return Instant");

            if (Return != Instant) {
                @compileError(kind ++ ": now must return Instant, not an error union or another type");
            }
        }

        fn requireSleep(comptime Backend: type) void {
            const message = "Clock.Monotonic backend: sleep must be fn(*Backend, Duration) void";
            const info = switch (@typeInfo(@TypeOf(Backend.sleep))) {
                .@"fn" => |info| info,
                else => @compileError(message),
            };

            if (info.params.len != 2) {
                @compileError(message);
            }

            if (info.params[0].type != *Backend or
                info.params[1].type != Duration or
                info.return_type != void)
            {
                @compileError(message);
            }
        }

        fn now(comptime C: type, self: *C) Instant {
            const instant = self.backend.now();

            if (comptime debug.checksEnabled()) {
                std.debug.assert(instant.isAtOrAfter(self.last));
                self.last = instant;
            }

            return instant;
        }
    };
};

pub const unit = struct {
    const testing = std.testing;

    test "unit: instant arithmetic checks both ends of the nanosecond range" {
        const base = Instant.fromNanos(100);
        const maximum = Instant.fromNanos(std.math.maxInt(u64));

        try testing.expectEqual(base, try base.add(Duration.zero));
        try testing.expectEqual(Instant.fromNanos(150), try base.add(Duration.fromNanos(50)));
        try testing.expectEqual(Instant.fromNanos(75), try base.add(Duration.fromNanos(-25)));
        try testing.expectError(error.Overflow, maximum.add(Duration.fromNanos(1)));
        try testing.expectError(error.Overflow, Instant.zero.add(Duration.fromNanos(-1)));
    }

    test "unit: instant differences and ordering distinguish either side and equality" {
        const earlier = Instant.fromNanos(200);
        const later = Instant.fromNanos(500);

        try testing.expectEqual(@as(i64, 300), later.since(earlier).nanos());
        try testing.expectEqual(@as(i64, -300), earlier.since(later).nanos());
        try testing.expectEqual(Duration.zero, later.since(later));
        try testing.expect(later.isAtOrAfter(earlier));
        try testing.expect(later.isAtOrAfter(later));
        try testing.expect(!earlier.isAtOrAfter(later));
    }

    test "unit: duration conversions preserve sign and reject multiplication overflow" {
        const micros = try Duration.fromMicros(3);
        const millis = try Duration.fromMillis(-5);
        const seconds = try Duration.fromSeconds(7);

        try testing.expectEqual(@as(i64, 3_000), micros.nanos());
        try testing.expectEqual(@as(i64, -3_000), (try Duration.fromMicros(-3)).nanos());
        try testing.expectEqual(@as(i64, -5_000_000), millis.nanos());
        try testing.expectEqual(@as(i64, 5_000_000), (try Duration.fromMillis(5)).nanos());
        try testing.expectEqual(@as(i64, 7_000_000_000), seconds.nanos());
        try testing.expectEqual(@as(i64, -7_000_000_000), (try Duration.fromSeconds(-7)).nanos());
        try testing.expectError(error.Overflow, Duration.fromMicros(std.math.maxInt(i64) / 1_000 + 1));
        try testing.expectError(error.Overflow, Duration.fromMillis(std.math.maxInt(i64) / 1_000_000 + 1));
        try testing.expectError(error.Overflow, Duration.fromSeconds(std.math.maxInt(i64) / 1_000_000_000 + 1));
    }

    test "unit: duration sign predicates distinguish zero from either sign" {
        const positive = Duration.fromNanos(1);
        const negative = Duration.fromNanos(-1);

        try testing.expect(positive.isPositive());
        try testing.expect(!positive.isNegative());
        try testing.expect(negative.isNegative());
        try testing.expect(!negative.isPositive());
        try testing.expect(!Duration.zero.isPositive());
        try testing.expect(!Duration.zero.isNegative());
    }

    test "unit: checked clock reads maintain independent state across both wrapper shapes" {
        if (comptime !debug.checksEnabled()) {
            return error.SkipZigTest;
        }

        const Reader = struct {
            tick: u64,

            pub fn now(self: *@This()) Instant {
                return Instant.fromNanos(self.tick);
            }
        };
        const Sleeper = struct {
            tick: u64,

            pub fn now(self: *@This()) Instant {
                return Instant.fromNanos(self.tick);
            }

            pub fn sleep(self: *@This(), delta: Duration) void {
                self.tick += @intCast(delta.nanos());
            }
        };
        var reader = Clock.Monotonic(Reader).init(.{ .tick = 10 });
        var sleeper = Clock.Monotonic(Sleeper).init(.{ .tick = 20 });

        _ = Clock.Impl.now(@TypeOf(reader), &reader);
        _ = reader.now();
        _ = sleeper.now();
        sleeper.sleep(Duration.fromNanos(5));
        _ = sleeper.now();

        try testing.expectEqual(Instant.fromNanos(10), reader.last);
        try testing.expectEqual(Instant.fromNanos(25), sleeper.last);
    }
};
