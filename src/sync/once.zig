//! one-shot initialization

const std = @import("std");
const builtin = @import("builtin");

const debug = @import("core").debug;
const BackendImpl = @import("backend/impl.zig");

/// blocking backends must enroll and recheck before parking
/// initialize before sharing; do not copy or move a shared initializer
pub fn Once(comptime Backend: type) type {
    comptime BackendImpl.requireBackend(Backend, "Once(Backend)");

    return struct {
        state: State,
        backend: Backend,

        const Self = @This();

        pub const WaitError = Backend.WaitError;

        pub fn init(backend: Backend) Self {
            return .{ .state = State.init(), .backend = backend };
        }

        pub fn isDone(self: *const Self) bool {
            return self.state.isDone();
        }

        pub fn call(
            self: *Self,
            comptime Context: type,
            comptime work: fn (context: Context) void,
            context: Context,
        ) WaitError!void {
            if (self.state.isDone()) {
                return;
            }

            Recursion.check(&self.state);

            if (Impl.tryClaim(&self.state)) |claim| {
                Recursion.enter(&self.state);
                defer Recursion.leave(&self.state);

                work(context);

                Impl.publish(&self.state, claim);
                self.backend.wakeAll(&self.state);
                return;
            }

            while (true) {
                const token = self.state.observe();
                if (token.isDone()) {
                    return;
                }
                try self.backend.wait(&self.state, token);
            }
        }

        /// work failure rolls back, wakes waiters, and returns the error
        /// other callers may claim after rollback
        pub fn callChecked(
            self: *Self,
            comptime Context: type,
            comptime WorkError: type,
            comptime work: fn (context: Context) WorkError!void,
            context: Context,
        ) (WorkError || WaitError)!void {
            if (self.state.isDone()) {
                return;
            }

            Recursion.check(&self.state);

            while (true) {
                if (self.state.isDone()) {
                    return;
                }

                if (Impl.tryClaim(&self.state)) |claim| {
                    Recursion.enter(&self.state);
                    defer Recursion.leave(&self.state);

                    work(context) catch |err| {
                        Impl.rollback(&self.state, claim);
                        self.backend.wakeAll(&self.state);
                        return err;
                    };

                    Impl.publish(&self.state, claim);
                    self.backend.wakeAll(&self.state);
                    return;
                }

                const token = self.state.observe();
                if (token.isDone()) {
                    return;
                }

                // rollback can restore idle after the failed claim
                if (@as(Word, @bitCast(@intFromEnum(token))).phase == .idle) {
                    continue;
                }

                try self.backend.wait(&self.state, token);
            }
        }
    };
}

pub const State = struct {
    word: std.atomic.Value(Word),

    pub fn init() State {
        return .{ .word = std.atomic.Value(Word).init(.{
            .phase = .idle,
            .generation = 0,
        }) };
    }

    pub fn isDone(self: *const State) bool {
        return self.word.load(.acquire).phase == .done;
    }

    pub fn observe(self: *const State) Token {
        return @enumFromInt(@as(u32, @bitCast(self.word.load(.acquire))));
    }

    pub fn changedSince(self: *const State, token: Token) bool {
        return self.word.load(.acquire) != @as(Word, @bitCast(@intFromEnum(token)));
    }
};

pub const Token = enum(u32) {
    _,

    pub fn isDone(self: Token) bool {
        return @as(Word, @bitCast(@intFromEnum(self))).phase == .done;
    }
};

const Phase = enum(u2) {
    idle,
    running,
    done,
    _,
};

const Word = packed struct(u32) {
    phase: Phase,
    generation: u30,

    fn next(self: Word, phase: Phase) Word {
        return .{
            .phase = phase,
            .generation = self.generation +% 1,
        };
    }
};

const Claim = struct {
    running: Word,
};

const Impl = struct {
    fn tryClaim(state: *State) ?Claim {
        var current = state.word.load(.acquire);
        while (true) {
            if (current.phase != .idle) {
                return null;
            }

            const running = current.next(.running);
            if (state.word.cmpxchgWeak(current, running, .release, .acquire)) |observed| {
                current = observed;
                continue;
            }

            return .{ .running = running };
        }
    }

    fn publish(state: *State, claim: Claim) void {
        const done = claim.running.next(.done);
        if (state.word.cmpxchgStrong(claim.running, done, .release, .monotonic) != null) {
            @panic("Once: claim changed before publication");
        }
    }

    fn rollback(state: *State, claim: Claim) void {
        const idle = claim.running.next(.idle);
        if (state.word.cmpxchgStrong(claim.running, idle, .release, .monotonic) != null) {
            @panic("Once: claim changed before rollback");
        }
    }
};

const Recursion = struct {
    const enabled = debug.checksEnabled() and !builtin.single_threaded;

    threadlocal var active: ?*const State = null;

    fn check(state: *const State) void {
        if (comptime !enabled) {
            return;
        }
        std.debug.assert(active != state);
    }

    fn enter(state: *const State) void {
        if (comptime !enabled) {
            return;
        }
        active = state;
    }

    fn leave(state: *const State) void {
        if (comptime !enabled) {
            return;
        }
        if (active == state) {
            active = null;
        }
    }
};

pub const unit = struct {
    const testing = std.testing;

    const SpinOnce = Once(@import("backend/spin.zig").Backend);

    test "claim rollback and publication advance generations" {
        var state = State.init();
        state.word.store(.{ .phase = .idle, .generation = std.math.maxInt(u30) }, .monotonic);
        const initial = state.observe();

        const first = Impl.tryClaim(&state).?;
        const running = state.observe();

        try testing.expectEqual(@as(u30, 0), first.running.generation);
        try testing.expect(state.changedSince(initial));
        try testing.expect(!running.isDone());
        try testing.expect(Impl.tryClaim(&state) == null);

        Impl.rollback(&state, first);

        try testing.expect(state.changedSince(running));
        try testing.expect(!state.isDone());
        try testing.expectEqual(@as(u30, 1), state.word.load(.acquire).generation);

        const second = Impl.tryClaim(&state).?;
        Impl.publish(&state, second);
        const done = state.observe();

        try testing.expectEqual(@as(u30, 3), state.word.load(.acquire).generation);
        try testing.expect(done.isDone());
        try testing.expect(state.isDone());
        try testing.expect(!state.changedSince(done));
        try testing.expect(Impl.tryClaim(&state) == null);
    }

    test "call publishes once across plain and checked callers" {
        const Work = struct {
            fn run(value: *u32) void {
                value.* += 1;
            }

            fn checked(value: *u32) error{}!void {
                value.* += 1;
            }
        };

        var value: u32 = 0;
        var once = SpinOnce.init(.{});

        try once.call(*u32, Work.run, &value);
        try once.call(*u32, Work.run, &value);
        try once.callChecked(*u32, error{}, Work.checked, &value);

        try testing.expectEqual(@as(u32, 1), value);
        try testing.expect(once.isDone());
    }

    const Backend = struct {
        wake_calls: usize = 0,

        pub const WaitError = error{Canceled};

        pub fn wait(_: *Backend, _: *const State, _: Token) WaitError!void {
            return error.Canceled;
        }

        pub fn wakeAll(self: *Backend, _: *const State) void {
            self.wake_calls += 1;
        }
    };

    test "work failure rolls back and wakes before a successful retry" {
        const Work = struct {
            fn fail(attempts: *u32) error{Custom}!void {
                attempts.* += 1;
                return error.Custom;
            }

            fn succeed(attempts: *u32) error{Custom}!void {
                attempts.* += 1;
            }

            fn plain(attempts: *u32) void {
                attempts.* += 1;
            }
        };

        var attempts: u32 = 0;
        var once = Once(Backend).init(.{});

        try testing.expectError(
            error.Custom,
            once.callChecked(*u32, error{Custom}, Work.fail, &attempts),
        );

        try testing.expect(!once.isDone());
        try testing.expectEqual(@as(u32, 1), attempts);
        try testing.expectEqual(@as(usize, 1), once.backend.wake_calls);

        try once.callChecked(*u32, error{Custom}, Work.succeed, &attempts);
        try once.callChecked(*u32, error{Custom}, Work.succeed, &attempts);
        try once.call(*u32, Work.plain, &attempts);

        try testing.expect(once.isDone());
        try testing.expectEqual(@as(u32, 2), attempts);
        try testing.expectEqual(@as(usize, 2), once.backend.wake_calls);
    }

    test "backend cancellation leaves the active claim unchanged" {
        const Work = struct {
            fn plain(calls: *u32) void {
                calls.* += 1;
            }

            fn checked(calls: *u32) error{Custom}!void {
                calls.* += 1;
            }
        };

        var calls: u32 = 0;
        var once = Once(Backend).init(.{});

        const claim = Impl.tryClaim(&once.state).?;
        const running = once.state.observe();

        try testing.expectError(error.Canceled, once.call(*u32, Work.plain, &calls));
        try testing.expectError(
            error.Canceled,
            once.callChecked(*u32, error{Custom}, Work.checked, &calls),
        );

        try testing.expectEqual(@as(u32, 0), calls);
        try testing.expect(!once.state.changedSince(running));
        try testing.expectEqual(@as(usize, 0), once.backend.wake_calls);

        Impl.publish(&once.state, claim);

        try testing.expect(once.isDone());
    }
};
