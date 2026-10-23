//! manual-reset signals

const std = @import("std");

pub const Signal = struct {
    pub const Status = enum(u1) { unset, set };

    pub const Token = enum(usize) {
        _,

        pub fn isSet(self: Token) bool {
            const word: Word = @bitCast(@intFromEnum(self));
            return word.status == .set;
        }
    };

    pub const State = struct {
        word: std.atomic.Value(Word),

        pub fn init(initial: Status) State {
            return .{ .word = std.atomic.Value(Word).init(.{
                .status = initial,
                .generation = 0,
            }) };
        }

        pub fn isSet(self: *const State) bool {
            return self.observe().isSet();
        }

        pub fn observe(self: *const State) Token {
            return @enumFromInt(@as(usize, @bitCast(self.word.load(.acquire))));
        }

        pub fn changedSince(self: *const State, token: Token) bool {
            return @as(usize, @bitCast(self.word.load(.acquire))) != @intFromEnum(token);
        }
    };

    /// blocking backends must enroll, recheck changedSince, then park
    pub fn Manual(comptime Backend: type) type {
        return struct {
            state: Signal.State,
            backend: Backend,

            const Self = @This();

            pub const WaitError = Backend.WaitError;

            pub fn init(initial: Signal.Status, backend: Backend) Self {
                return .{ .state = Signal.State.init(initial), .backend = backend };
            }

            pub fn isSet(self: *const Self) bool {
                return self.state.isSet();
            }

            /// release-publishes a set transition; redundant sets do not wake waiters
            pub fn set(self: *Self) void {
                Impl.set(&self.state, &self.backend);
            }

            /// release-publishes an unset transition without waking waiters
            pub fn clear(self: *Self) void {
                Impl.clear(&self.state);
            }

            pub fn wait(self: *Self) WaitError!void {
                return Impl.wait(&self.state, &self.backend);
            }

            pub fn stateRef(self: *const Self) *const Signal.State {
                return &self.state;
            }

            const Impl = struct {
                fn set(state: *Signal.State, backend: *Backend) void {
                    var current = state.word.load(.acquire);
                    while (true) {
                        if (current.status == .set) {
                            return;
                        }

                        if (state.word.cmpxchgWeak(current, current.next(.set), .release, .acquire)) |observed| {
                            current = observed;
                            continue;
                        }

                        backend.wakeAll(state);
                        return;
                    }
                }

                fn clear(state: *Signal.State) void {
                    var current = state.word.load(.acquire);
                    while (true) {
                        if (current.status == .unset) {
                            return;
                        }

                        if (state.word.cmpxchgWeak(current, current.next(.unset), .release, .acquire)) |observed| {
                            current = observed;
                            continue;
                        }
                        return;
                    }
                }

                fn wait(state: *Signal.State, backend: *Backend) WaitError!void {
                    while (true) {
                        const token = state.observe();
                        if (token.isSet()) {
                            return;
                        }
                        try backend.wait(state, token);
                    }
                }
            };
        };
    }

    const Word = packed struct(usize) {
        status: Status,
        generation: std.meta.Int(.unsigned, @bitSizeOf(usize) - 1),

        fn next(self: Word, status: Status) Word {
            return .{
                .status = status,
                .generation = self.generation +% 1,
            };
        }
    };
};

pub const unit = struct {
    const testing = std.testing;

    const Manual = Signal.Manual(Backend);

    const Backend = struct {
        waits: usize = 0,
        wakes: usize = 0,
        spurious: usize = 0,

        pub const WaitError = error{Canceled};

        pub fn wait(self: *@This(), state: *const Signal.State, token: Signal.Token) WaitError!void {
            self.waits += 1;
            if (state.changedSince(token)) {
                return;
            }
            if (self.spurious != 0) {
                self.spurious -= 1;
                return;
            }
            return error.Canceled;
        }

        pub fn wakeAll(self: *@This(), _: *const Signal.State) void {
            self.wakes += 1;
        }
    };

    test "signal transitions distinguish a complete cycle without redundant wakes" {
        var state = Signal.State.init(.unset);
        var backend: Backend = .{};
        const initial = state.observe();

        Manual.Impl.set(&state, &backend);
        const set = state.observe();
        Manual.Impl.set(&state, &backend);

        try testing.expect(set.isSet());
        try testing.expectEqual(set, state.observe());
        try testing.expect(state.changedSince(initial));
        try testing.expectEqual(@as(usize, 1), backend.wakes);

        Manual.Impl.clear(&state);
        const cleared = state.observe();
        Manual.Impl.clear(&state);

        try testing.expect(!cleared.isSet());
        try testing.expectEqual(cleared, state.observe());
        try testing.expect(state.changedSince(set));
        try testing.expect(state.changedSince(initial));
        try testing.expectEqual(@as(usize, 1), backend.wakes);

        Manual.Impl.set(&state, &backend);

        try testing.expectEqual(@as(usize, 2), backend.wakes);
        try testing.expect(state.isSet());
    }

    test "signal wait bypasses backend when ready and rechecks spurious returns" {
        var state = Signal.State.init(.set);
        var backend: Backend = .{ .spurious = 2 };

        try Manual.Impl.wait(&state, &backend);
        try testing.expectEqual(@as(usize, 0), backend.waits);

        Manual.Impl.clear(&state);
        try testing.expectError(error.Canceled, Manual.Impl.wait(&state, &backend));

        try testing.expect(!state.isSet());
        try testing.expectEqual(@as(usize, 3), backend.waits);
        try testing.expectEqual(@as(usize, 0), backend.wakes);
    }

    test "signal token recheck detects a transition before backend registration" {
        var signal = Manual.init(.unset, .{});
        const token = signal.stateRef().observe();

        signal.set();
        try signal.backend.wait(signal.stateRef(), token);
        try signal.wait();

        try testing.expect(signal.isSet());
        try testing.expectEqual(@as(usize, 1), signal.backend.waits);
        try testing.expectEqual(@as(usize, 1), signal.backend.wakes);
    }

    test "signal generation wraps without losing transition status" {
        var state: Signal.State = .{ .word = .init(.{
            .status = .set,
            .generation = std.math.maxInt(std.meta.Int(.unsigned, @bitSizeOf(usize) - 1)),
        }) };

        var backend: Backend = .{};
        const before = state.observe();

        Manual.Impl.clear(&state);
        const cleared = state.observe();
        Manual.Impl.set(&state, &backend);

        try testing.expect(!cleared.isSet());
        try testing.expect(state.changedSince(before));
        try testing.expect(state.isSet());
        try testing.expectEqual(@as(usize, 1), backend.wakes);
    }
};
