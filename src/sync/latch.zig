//! one-shot countdown latches

const std = @import("std");

const debug = @import("core").debug;

const BackendImpl = @import("backend/impl.zig");

/// blocking backends must enroll and recheck before parking
/// state reads acquire; only the final arrival wakes waiters
pub fn Latch(comptime Backend: type) type {
    comptime BackendImpl.requireBackend(Backend, "Latch(Backend)");

    return struct {
        pub const WaitError = Backend.WaitError;

        pub fn Static(comptime count: usize) type {
            comptime {
                if (count == 0) {
                    @compileError("Latch.Static requires count >= 1");
                }
                if (count > std.math.maxInt(u32)) {
                    @compileError("Latch.Static requires count <= maxInt(u32)");
                }
            }

            return struct {
                state: State,
                backend: Backend,

                const Self = @This();

                pub const WaitError = Backend.WaitError;

                pub const bound: usize = count;

                pub fn init(backend: Backend) Self {
                    return .{ .state = State.init(@intCast(bound)), .backend = backend };
                }

                pub fn arrive(self: *Self) void {
                    Impl.arrive(&self.state, &self.backend);
                }

                pub fn wait(self: *Self) Backend.WaitError!void {
                    return Impl.wait(&self.state, &self.backend);
                }

                pub fn pending(self: *const Self) u32 {
                    return self.state.pending();
                }

                pub fn capacity(self: *const Self) u32 {
                    _ = self;
                    return @intCast(bound);
                }

                pub fn isReleased(self: *const Self) bool {
                    return self.state.isReleased();
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

            pub fn arrive(self: *Self) void {
                Impl.arrive(&self.state, &self.backend);
            }

            pub fn wait(self: *Self) Backend.WaitError!void {
                return Impl.wait(&self.state, &self.backend);
            }

            pub fn pending(self: *const Self) u32 {
                return self.state.pending();
            }

            pub fn capacity(self: *const Self) u32 {
                return self.bound;
            }

            pub fn isReleased(self: *const Self) bool {
                return self.state.isReleased();
            }
        };

        const Impl = struct {
            fn arrive(state: *State, backend: *Backend) void {
                while (true) {
                    const token = state.observe();
                    const pending = token.pending();

                    if (pending == 0) {
                        if (debug.checksEnabled()) {
                            unreachable;
                        }
                        return;
                    }

                    if (state.word.cmpxchgWeak(@intFromEnum(token), pending - 1, .acq_rel, .acquire)) |_| {
                        continue;
                    }
                    if (pending == 1) {
                        backend.wakeAll(state);
                    }
                    return;
                }
            }

            fn wait(state: *State, backend: *Backend) WaitError!void {
                while (true) {
                    const token = state.observe();
                    if (token.isReleased()) {
                        return;
                    }
                    try backend.wait(state, token);
                }
            }
        };
    };
}

pub const State = struct {
    word: std.atomic.Value(u32),

    const Self = @This();

    pub fn init(count: u32) Self {
        if (debug.checksEnabled()) {
            std.debug.assert(count > 0);
        }
        return .{ .word = std.atomic.Value(u32).init(count) };
    }

    pub fn observe(self: *const Self) Token {
        return @enumFromInt(self.word.load(.acquire));
    }

    pub fn changedSince(self: *const Self, token: Token) bool {
        const current = self.word.load(.acquire);
        return current != @intFromEnum(token);
    }

    pub fn pending(self: *const Self) u32 {
        return self.word.load(.acquire);
    }

    pub fn isReleased(self: *const Self) bool {
        return self.word.load(.acquire) == 0;
    }
};

pub const Token = enum(u32) {
    _,

    const Self = @This();

    pub fn pending(self: Self) u32 {
        return @intFromEnum(self);
    }

    pub fn isReleased(self: Self) bool {
        return @intFromEnum(self) == 0;
    }
};

pub const unit = struct {
    const testing = std.testing;
    const Family = Latch(Backend);

    const Backend = struct {
        waits: usize = 0,
        wakes: usize = 0,
        spurious: usize = 0,
        release: ?*State = null,

        pub const WaitError = error{Canceled};

        pub fn wait(self: *@This(), state: *const State, token: Token) WaitError!void {
            self.waits += 1;
            if (self.release) |target| {
                self.release = null;
                Family.Impl.arrive(target, self);
            }
            if (state.changedSince(token)) {
                return;
            }
            if (self.spurious != 0) {
                self.spurious -= 1;
                return;
            }
            return error.Canceled;
        }

        pub fn wakeAll(self: *@This(), _: *const State) void {
            self.wakes += 1;
        }
    };

    test "countdown changes tokens and wakes only on final arrival" {
        var state = State.init(2);
        var backend: Backend = .{};
        const initial = state.observe();

        Family.Impl.arrive(&state, &backend);
        const middle = state.observe();

        try testing.expectEqual(@as(u32, 1), middle.pending());
        try testing.expect(!middle.isReleased());
        try testing.expect(state.changedSince(initial));
        try testing.expectEqual(@as(usize, 0), backend.wakes);

        Family.Impl.arrive(&state, &backend);
        const released = state.observe();

        try testing.expect(released.isReleased());
        try testing.expectEqual(@as(u32, 0), state.pending());
        try testing.expect(state.changedSince(middle));
        try testing.expect(!state.changedSince(released));
        try testing.expectEqual(@as(usize, 1), backend.wakes);
    }

    test "wait rechecks spurious returns and leaves pending unchanged on error" {
        var state = State.init(1);
        var backend: Backend = .{ .spurious = 2 };
        const initial = state.observe();

        try testing.expectError(error.Canceled, Family.Impl.wait(&state, &backend));

        try testing.expectEqual(@as(usize, 3), backend.waits);
        try testing.expect(!state.changedSince(initial));
        try testing.expectEqual(@as(usize, 0), backend.wakes);

        Family.Impl.arrive(&state, &backend);
        try Family.Impl.wait(&state, &backend);
        try Family.Impl.wait(&state, &backend);

        try testing.expectEqual(@as(usize, 3), backend.waits);
        try testing.expect(state.isReleased());
    }

    test "backend recheck observes a final arrival before parking" {
        var state = State.init(1);
        var backend: Backend = .{ .release = &state };

        try Family.Impl.wait(&state, &backend);

        try testing.expect(state.isReleased());
        try testing.expectEqual(@as(usize, 1), backend.waits);
        try testing.expectEqual(@as(usize, 1), backend.wakes);
    }

    test "static minimum bound releases on one arrival" {
        var latch = Family.Static(1).init(.{});

        latch.arrive();
        try latch.wait();

        try testing.expect(latch.isReleased());
        try testing.expectEqual(@as(u32, 0), latch.pending());
        try testing.expectEqual(@as(u32, 1), latch.capacity());
        try testing.expectEqual(@as(usize, 1), latch.backend.wakes);
        try testing.expectEqual(@as(usize, 0), latch.backend.waits);
    }

    test "bounded capacity remains fixed as pending decreases" {
        var latch = Family.Bounded.init(3, .{});

        latch.arrive();

        try testing.expectEqual(@as(u32, 3), latch.capacity());
        try testing.expectEqual(@as(u32, 2), latch.pending());
        try testing.expect(!latch.isReleased());
    }
};
