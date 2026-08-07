//! One-shot countdown latch. See `docs/specs/sync/latch.md`.

const std = @import("std");

const debug = @import("../core/debug.zig");

/// Wait-capable countdown latch.
/// Requirements: `Backend` provides `WaitError`, `wait`, and `wakeAll`.
pub fn Latch(comptime Backend: type) type {
    comptime requireBackend(Backend);

    return struct {
        pub const WaitError = Backend.WaitError;

        /// Comptime-capacity variant. Rejects zero and values above `maxInt(u32)`.
        pub fn Static(comptime capacity_arrivals: usize) type {
            comptime {
                if (capacity_arrivals == 0) {
                    @compileError("Latch.Static requires capacity_arrivals >= 1");
                }
                if (capacity_arrivals > std.math.maxInt(u32)) {
                    @compileError("Latch.Static requires capacity_arrivals <= maxInt(u32)");
                }
            }

            return struct {
                state: State,
                backend: Backend,

                const Self = @This();

                pub const WaitError = Backend.WaitError;

                pub const arrival_capacity: usize = capacity_arrivals;

                const capacity_u32: u32 = @intCast(capacity_arrivals);

                /// Requirements: Initialize before sharing. Do not copy or move after sharing.
                pub fn init(backend: Backend) Self {
                    return .{ .state = State.init(capacity_u32), .backend = backend };
                }

                /// Decrements remaining. The last arrival wakes waiters.
                pub fn arrive(self: *Self) void {
                    arriveShared(&self.state, &self.backend);
                }

                /// Waits until released. Never allocates.
                pub fn wait(self: *Self) Backend.WaitError!void {
                    return waitShared(&self.state, &self.backend);
                }

                /// Returns remaining arrivals. Uses acquire.
                pub fn pending(self: *const Self) u32 {
                    return self.state.remaining();
                }

                pub fn capacity(self: *const Self) u32 {
                    _ = self;
                    return capacity_u32;
                }

                /// Returns whether released. Uses acquire.
                pub fn isReleased(self: *const Self) bool {
                    return self.state.isReleased();
                }
            };
        }

        /// Runtime-capacity variant.
        pub const Bounded = struct {
            total_capacity: u32,
            state: State,
            backend: Backend,

            pub const WaitError = Backend.WaitError;

            /// Requirements: `capacity_arrivals > 0`. Initialize before sharing.
            pub fn init(capacity_arrivals: u32, backend: Backend) Bounded {
                if (debug.checksEnabled(.build_mode)) {
                    std.debug.assert(capacity_arrivals > 0);
                }

                return .{
                    .total_capacity = capacity_arrivals,
                    .state = State.init(capacity_arrivals),
                    .backend = backend,
                };
            }

            /// Decrements remaining. The last arrival wakes waiters.
            pub fn arrive(self: *Bounded) void {
                arriveShared(&self.state, &self.backend);
            }

            /// Waits until released. Never allocates.
            pub fn wait(self: *Bounded) Backend.WaitError!void {
                return waitShared(&self.state, &self.backend);
            }

            /// Returns remaining arrivals. Uses acquire.
            pub fn pending(self: *const Bounded) u32 {
                return self.state.remaining();
            }

            pub fn capacity(self: *const Bounded) u32 {
                return self.total_capacity;
            }

            /// Returns whether released. Uses acquire.
            pub fn isReleased(self: *const Bounded) bool {
                return self.state.isReleased();
            }
        };
    };
}

/// Atomic countdown state. Zero is sticky released.
pub const State = struct {
    word: std.atomic.Value(u32),

    /// Requirements: `capacity > 0`.
    pub fn init(capacity: u32) State {
        if (debug.checksEnabled(.build_mode)) {
            std.debug.assert(capacity > 0);
        }
        return .{ .word = std.atomic.Value(u32).init(capacity) };
    }

    /// Returns an acquire snapshot for backend rechecks.
    pub fn observe(self: *const State) Token {
        return @enumFromInt(self.word.load(.acquire));
    }

    /// Returns whether state changed after `token`. Uses acquire.
    pub fn changedSince(self: *const State, token: Token) bool {
        const current = self.word.load(.acquire);
        return current != @intFromEnum(token);
    }

    /// Returns remaining arrivals. Uses acquire.
    pub fn remaining(self: *const State) u32 {
        return self.word.load(.acquire);
    }

    /// Returns whether released. Uses acquire.
    pub fn isReleased(self: *const State) bool {
        return self.word.load(.acquire) == 0;
    }
};

/// Observed state snapshot.
pub const Token = enum(u32) {
    _,

    pub fn remaining(self: Token) u32 {
        return @intFromEnum(self);
    }

    pub fn isReleased(self: Token) bool {
        return @intFromEnum(self) == 0;
    }
};

fn arriveShared(state: *State, backend: anytype) void {
    while (true) {
        const observed = state.observe();
        const rem = observed.remaining();

        if (rem == 0) {
            // Saturate over-arrival at zero; debug builds trap.
            if (debug.checksEnabled(.build_mode)) unreachable;
            return;
        }

        if (state.word.cmpxchgWeak(@intFromEnum(observed), rem - 1, .acq_rel, .acquire)) |_| continue;
        if (rem == 1) backend.wakeAll(state);

        return;
    }
}

fn waitShared(state: *State, backend: anytype) @TypeOf(backend.*).WaitError!void {
    if (state.isReleased()) return;
    while (true) {
        const token = state.observe();
        if (token.isReleased()) return;
        try backend.wait(state, token);
    }
}

fn requireBackend(comptime Backend: type) void {
    if (!@hasDecl(Backend, "WaitError")) {
        @compileError("Latch(Backend): Backend must declare pub const WaitError");
    }

    const info = @typeInfo(Backend.WaitError);
    if (info != .error_set) {
        @compileError("Latch(Backend): Backend.WaitError must be an error set");
    }

    if (info.error_set == null) {
        @compileError(
            "Latch(Backend): Backend.WaitError must be an explicit error set; " ++
                "anyerror is not approved",
        );
    }

    if (!@hasDecl(Backend, "wait")) {
        @compileError(
            "Latch(Backend): Backend must declare " ++
                "pub fn wait(*Backend, *const State, Token) WaitError!void",
        );
    }

    if (!@hasDecl(Backend, "wakeAll")) {
        @compileError(
            "Latch(Backend): Backend must declare " ++
                "pub fn wakeAll(*Backend, *const State) void",
        );
    }
}
