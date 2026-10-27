//! reusable cyclic barriers

const std = @import("std");

const debug = @import("core").debug;

const BackendImpl = @import("backend/impl.zig");

const Word = packed struct(u64) {
    pending: u32,
    generation: u32,
};

pub const State = struct {
    word: std.atomic.Value(Word),

    const Self = @This();

    pub fn init(count: u32) Self {
        if (debug.checksEnabled()) {
            std.debug.assert(count > 0);
        }
        return .{ .word = .init(.{ .pending = count, .generation = 0 }) };
    }

    pub fn observe(self: *const Self) Token {
        return @enumFromInt(@as(u64, @bitCast(self.word.load(.acquire))));
    }

    pub fn changedSince(self: *const Self, token: Token) bool {
        return self.word.load(.acquire).generation != token.generation();
    }

    pub fn pending(self: *const Self) u32 {
        return self.word.load(.acquire).pending;
    }

    pub fn generation(self: *const Self) u32 {
        return self.word.load(.acquire).generation;
    }
};

pub const Token = enum(u64) {
    _,

    const Self = @This();

    pub fn pending(self: Self) u32 {
        const word: Word = @bitCast(@intFromEnum(self));
        return word.pending;
    }

    pub fn generation(self: Self) u32 {
        const word: Word = @bitCast(@intFromEnum(self));
        return word.generation;
    }
};

/// blocking backends must enroll and recheck before parking
/// initialize before concurrent use; live state queries use acquire ordering
pub fn Rendezvous(comptime Backend: type) type {
    comptime BackendImpl.requireBackend(Backend, "Rendezvous(Backend)");

    return struct {
        pub const WaitError = Backend.WaitError;

        pub fn Static(comptime count: usize) type {
            comptime {
                if (count == 0) {
                    @compileError("Rendezvous.Static requires count >= 1");
                }
                if (count > std.math.maxInt(u32)) {
                    @compileError("Rendezvous.Static requires count <= maxInt(u32)");
                }
            }

            return struct {
                state: State,
                backend: Backend,

                pub const bound: usize = count;

                const Self = @This();

                pub const WaitError = Backend.WaitError;

                pub fn init(backend: Backend) Self {
                    return .{ .state = State.init(@intCast(bound)), .backend = backend };
                }

                pub fn arrive(self: *Self) Backend.WaitError!void {
                    return Impl.arrive(&self.state, &self.backend, @intCast(bound));
                }

                pub fn pending(self: *const Self) u32 {
                    return self.state.pending();
                }

                pub fn capacity(self: *const Self) u32 {
                    _ = self;
                    return @intCast(bound);
                }

                pub fn generation(self: *const Self) u32 {
                    return self.state.generation();
                }

                pub fn stateRef(self: *const Self) *const State {
                    return &self.state;
                }
            };
        }

        pub const Bounded = struct {
            bound: u32,
            state: State,
            backend: Backend,

            const Self = @This();

            pub const WaitError = Backend.WaitError;

            pub fn init(count: u32, backend: Backend) Self {
                return .{
                    .bound = count,
                    .state = State.init(count),
                    .backend = backend,
                };
            }

            pub fn arrive(self: *Self) Backend.WaitError!void {
                return Impl.arrive(&self.state, &self.backend, self.bound);
            }

            pub fn pending(self: *const Self) u32 {
                return self.state.pending();
            }

            pub fn capacity(self: *const Self) u32 {
                return self.bound;
            }

            pub fn generation(self: *const Self) u32 {
                return self.state.generation();
            }

            pub fn stateRef(self: *const Self) *const State {
                return &self.state;
            }
        };

        const Impl = struct {
            fn arrive(state: *State, backend: *Backend, capacity: u32) Backend.WaitError!void {
                std.debug.assert(capacity > 0);

                var generation: u32 = undefined;
                while (true) {
                    const observed = state.word.load(.acquire);
                    const pending = observed.pending;

                    std.debug.assert(pending > 0);

                    generation = observed.generation;

                    // the final arrival resets pending and advances generation atomically
                    const next: Word = switch (pending) {
                        1 => .{ .pending = capacity, .generation = generation +% 1 },
                        else => .{ .pending = pending - 1, .generation = generation },
                    };

                    if (state.word.cmpxchgWeak(observed, next, .acq_rel, .acquire)) |_| {
                        continue;
                    }

                    if (pending == 1) {
                        backend.wakeAll(state);
                        return;
                    }

                    break;
                }

                while (true) {
                    const token = state.observe();
                    if (token.generation() != generation) {
                        return;
                    }

                    try backend.wait(state, token);
                }
            }
        };
    };
}

pub const unit = struct {
    const testing = std.testing;

    const Family = Rendezvous(Backend);

    const Backend = struct {
        waits: usize = 0,
        wakes: usize = 0,
        spurious: usize = 0,
        finish: bool = false,
        wake_pending: u32 = 0,
        wake_generation: u32 = 0,

        pub const WaitError = error{Canceled};

        pub fn wait(self: *@This(), state: *const State, token: Token) WaitError!void {
            self.waits += 1;

            if (state.changedSince(token)) {
                return;
            }

            if (self.spurious != 0) {
                self.spurious -= 1;
                return;
            }

            if (self.finish) {
                self.finish = false;
                try Family.Impl.arrive(@constCast(state), self, 2);
                return;
            }

            return error.Canceled;
        }

        pub fn wakeAll(self: *@This(), state: *const State) void {
            self.wakes += 1;
            const token = state.observe();
            self.wake_pending = token.pending();
            self.wake_generation = token.generation();
        }
    };

    test "canceled arrivals commit and final arrivals reset before wake across cycles" {
        var state = State.init(2);
        var backend: Backend = .{};

        for (1..4) |generation| {
            const token = state.observe();

            try testing.expectError(error.Canceled, Family.Impl.arrive(&state, &backend, 2));
            try testing.expectEqual(@as(u32, 1), state.pending());
            try testing.expect(!state.changedSince(token));
            try testing.expectEqual(generation - 1, backend.wakes);

            try Family.Impl.arrive(&state, &backend, 2);

            try testing.expect(state.changedSince(token));
            try testing.expectEqual(@as(u32, 2), state.pending());
            try testing.expectEqual(@as(u32, @intCast(generation)), state.generation());
            try testing.expectEqual(generation, backend.wakes);
            try testing.expectEqual(@as(u32, 2), backend.wake_pending);
            try testing.expectEqual(state.generation(), backend.wake_generation);
        }
    }

    test "successful spurious waits recheck until generation changes" {
        var state = State.init(2);
        var backend: Backend = .{ .spurious = 2, .finish = true };

        try Family.Impl.arrive(&state, &backend, 2);

        try testing.expectEqual(@as(usize, 3), backend.waits);
        try testing.expectEqual(@as(usize, 1), backend.wakes);
        try testing.expectEqual(@as(u32, 2), state.pending());
        try testing.expectEqual(@as(u32, 1), state.generation());
    }

    test "generation-only changes and wrapping final arrival invalidate tokens" {
        var state = State.init(2);
        var backend: Backend = .{};

        const initial = state.observe();
        state.word.store(.{ .pending = 2, .generation = std.math.maxInt(u32) }, .release);
        const before_wrap = state.observe();

        try testing.expect(state.changedSince(initial));
        try testing.expectEqual(initial.pending(), before_wrap.pending());
        try testing.expectError(error.Canceled, Family.Impl.arrive(&state, &backend, 2));
        try testing.expect(!state.changedSince(before_wrap));

        try Family.Impl.arrive(&state, &backend, 2);

        try testing.expect(state.changedSince(before_wrap));
        try testing.expectEqual(@as(u32, 0), state.generation());
        try testing.expectEqual(@as(u32, 2), state.pending());
        try testing.expectEqual(@as(usize, 1), backend.wakes);
    }

    test "static minimum bound completes each arrival" {
        const Barrier = Family.Static(1);
        var barrier = Barrier.init(.{});

        try barrier.arrive();
        try barrier.arrive();

        try testing.expectEqual(@as(usize, 1), Barrier.bound);
        try testing.expectEqual(@as(u32, 1), barrier.capacity());
        try testing.expectEqual(@as(u32, 1), barrier.pending());
        try testing.expectEqual(@as(u32, 2), barrier.generation());
        try testing.expectEqual(@as(usize, 0), barrier.backend.waits);
        try testing.expectEqual(@as(usize, 2), barrier.backend.wakes);
    }

    test "bounded capacity stays fixed after an arrival" {
        var barrier = Family.Bounded.init(3, .{});

        try testing.expectError(error.Canceled, barrier.arrive());

        try testing.expectEqual(@as(u32, 3), barrier.capacity());
        try testing.expectEqual(@as(u32, 2), barrier.pending());
        try testing.expectEqual(@as(u32, 0), barrier.stateRef().generation());
    }
};
