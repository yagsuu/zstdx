const std = @import("std");
const time = @import("time");

const Deadline = time.Deadline;
const Backoff = time.Backoff;

pub const until = Impl.until;

pub const Result = Impl.Result;

const Impl = struct {
    const ResultInfo = struct {
        returns: type,
        errors: type,
        payload: type,
    };

    fn until(
        clock: anytype,
        deadline: Deadline,
        backoff: *Backoff,
        predicate: anytype,
    ) Impl.Result(@TypeOf(predicate)) {
        while (true) {
            if (try call(predicate)) |payload| {
                return payload;
            }

            switch (backoff.next(deadline, clock)) {
                .spin => std.atomic.spinLoopHint(),
                .yield => backoff.policy.yield.?.hook(),
                .sleep => |duration| clock.sleep(duration),
                .timeout => return error.Timeout,
            }
        }
    }

    fn Result(comptime Predicate: type) type {
        const shape = analyze(Predicate);
        return (Deadline.TimeoutError || shape.errors)!shape.payload;
    }

    fn analyze(comptime Predicate: type) ResultInfo {
        const Base = switch (@typeInfo(Predicate)) {
            .pointer => |pointer| pointer.child,
            else => Predicate,
        };

        const Function = switch (@typeInfo(Base)) {
            .@"fn" => Base,
            .@"struct" => method: {
                if (!@hasDecl(Base, "call")) {
                    @compileError("poll predicate must expose call");
                }

                break :method @TypeOf(Base.call);
            },
            else => @compileError("poll predicate must be a function or a struct with call"),
        };

        const function = switch (@typeInfo(Function)) {
            .@"fn" => |info| info,
            else => @compileError("poll predicate call must be a function"),
        };

        const parameters: usize = switch (@typeInfo(Base)) {
            .@"fn" => 0,
            else => 1,
        };

        if (function.params.len != parameters) {
            @compileError("poll predicate takes no arguments; call methods take only self");
        }

        const Return = function.return_type orelse
            @compileError("poll predicate requires a concrete return type");

        const errors = switch (@typeInfo(Return)) {
            .error_union => |info| info,
            else => @compileError("poll predicate must return E!?T"),
        };

        if (errors.error_set == anyerror) {
            @compileError("poll predicate must not return anyerror");
        }

        const optional = switch (@typeInfo(errors.payload)) {
            .optional => |info| info,
            else => @compileError("poll predicate must return E!?T"),
        };

        return .{
            .returns = Return,
            .errors = errors.error_set,
            .payload = optional.child,
        };
    }

    inline fn call(predicate: anytype) analyze(@TypeOf(predicate)).returns {
        switch (@typeInfo(@TypeOf(predicate))) {
            .@"fn" => return predicate(),
            .pointer => |pointer| switch (@typeInfo(pointer.child)) {
                .@"fn" => return predicate(),
                else => return predicate.call(),
            },
            else => return predicate.call(),
        }
    }
};

pub const unit = struct {
    const testing = std.testing;

    const Duration = time.Duration;
    const Instant = time.Instant;

    test "ready values and predicate errors precede an expired deadline" {
        var clock: Clock = .{ .current = .fromNanos(10) };
        const deadline = Deadline.from(clock.current);
        var backoff = Backoff.init(policy);
        var ready: Predicate = .{ .ready_after = 1, .value = 0 };
        var failure: Predicate = .{ .ready_after = 1, .fail = true };

        const value = try Impl.until(&clock, deadline, &backoff, &ready);
        const failed = Impl.until(&clock, deadline, &backoff, &failure);

        try testing.expectEqual(@as(u32, 0), value);
        try testing.expectError(error.DeviceFault, failed);
        try testing.expectEqual(@as(usize, 1), ready.calls);
        try testing.expectEqual(@as(usize, 1), failure.calls);
        try testing.expectEqual(@as(usize, 0), clock.reads);
        try testing.expectEqual(@as(u32, 0), backoff.attempts());

        var pending: Predicate = .{};
        const expired = Impl.until(&clock, deadline, &backoff, &pending);

        try testing.expectError(error.Timeout, expired);
        try testing.expectEqual(@as(usize, 1), pending.calls);
        try testing.expectEqual(@as(u32, 0), backoff.attempts());
        try testing.expectEqual(@as(usize, 0), clock.count);
    }

    test "spin and yield dispatch lead to sleeps clipped by the deadline" {
        yields = 0;
        var clock: Clock = .{};
        var backoff = Backoff.init(.{
            .spin = .{ .iterations = 2 },
            .yield = .{ .iterations = 1, .hook = &yieldHook },
            .wait = .{ .initial = .fromNanos(4), .max = .fromNanos(8), .growth_shift = 1 },
        });
        var predicate: Predicate = .{};
        const deadline = Deadline.from(.fromNanos(9));

        const result = Impl.until(&clock, deadline, &backoff, &predicate);

        try testing.expectError(error.Timeout, result);
        try testing.expectEqual(@as(usize, 6), predicate.calls);
        try testing.expectEqual(@as(u32, 5), backoff.attempts());
        try testing.expectEqual(@as(usize, 1), yields);
        try testing.expectEqual(@as(usize, 2), clock.count);
        try testing.expectEqual(Duration.fromNanos(4), clock.sleeps[0]);
        try testing.expectEqual(Duration.fromNanos(5), clock.sleeps[1]);
        try testing.expectEqual(Instant.fromNanos(9), clock.current);
    }

    test "predicate failure after waits returns without another backoff step" {
        var clock: Clock = .{};
        var backoff = Backoff.init(policy);
        var predicate: Predicate = .{ .ready_after = 3, .fail = true };

        const result = Impl.until(&clock, Deadline.never, &backoff, &predicate);

        try testing.expectError(error.DeviceFault, result);
        try testing.expectEqual(@as(usize, 3), predicate.calls);
        try testing.expectEqual(@as(u32, 2), backoff.attempts());
        try testing.expectEqual(@as(usize, 2), clock.count);
        try testing.expectEqual(Instant.fromNanos(2), clock.current);
    }

    const policy: Backoff.Policy = .{
        .spin = .{ .iterations = 0 },
        .yield = null,
        .wait = .{ .initial = .fromNanos(1), .max = .fromNanos(1), .growth_shift = 0 },
    };

    var yields: usize = 0;

    fn yieldHook() void {
        yields += 1;
    }

    const Clock = struct {
        current: Instant = .zero,
        reads: usize = 0,
        sleeps: [2]Duration = undefined,
        count: usize = 0,

        const Self = @This();

        pub fn now(self: *Self) Instant {
            self.reads += 1;
            return self.current;
        }

        pub fn sleep(self: *Self, duration: Duration) void {
            self.sleeps[self.count] = duration;
            self.count += 1;

            self.current = self.current.add(duration) catch unreachable;
        }
    };

    const Predicate = struct {
        calls: usize = 0,
        ready_after: usize = std.math.maxInt(usize),
        fail: bool = false,
        value: u32 = 0,

        const Self = @This();

        pub fn call(self: *Self) error{DeviceFault}!?u32 {
            self.calls += 1;

            if (self.calls < self.ready_after) {
                return null;
            }

            if (self.fail) {
                return error.DeviceFault;
            }

            return self.value;
        }
    };
};
