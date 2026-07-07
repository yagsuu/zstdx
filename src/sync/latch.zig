//! One-shot countdown latch. Spec: docs/specs/sync/latch.md.

const std = @import("std");

const debug = @import("../core/debug.zig");

/// Atomic one-shot countdown-latch state. One `u32` word holds the
/// remaining arrival count; `remaining == 0` is the released state and is
/// sticky.
pub const State = struct {
    word: std.atomic.Value(u32),

    /// `capacity` must be strictly positive; zero traps under
    /// `core.debug.checksEnabled(.build_mode)`.
    pub fn init(capacity: u32) State {
        if (debug.checksEnabled(.build_mode)) {
            std.debug.assert(capacity > 0);
        }
        return .{ .word = std.atomic.Value(u32).init(capacity) };
    }

    /// Acquire-load the word into a `Token` snapshot used to arm a
    /// lost-wakeup-safe wait.
    pub fn observe(self: *const State) Token {
        return @enumFromInt(self.word.load(.acquire));
    }

    /// Acquire-load the word and report whether it differs from `token`.
    pub fn changedSince(self: *const State, token: Token) bool {
        const current = self.word.load(.acquire);
        return current != @intFromEnum(token);
    }

    /// Acquire-load the word and return the current remaining count.
    pub fn remaining(self: *const State) u32 {
        return self.word.load(.acquire);
    }

    /// Acquire-load the word and return whether the latch is released.
    pub fn isReleased(self: *const State) bool {
        return self.word.load(.acquire) == 0;
    }
};

/// Observed snapshot of a `State` word.
pub const Token = enum(u32) {
    _,

    /// Remaining arrivals recorded at observation time.
    pub fn remaining(self: Token) u32 {
        return @intFromEnum(self);
    }

    /// Whether the observed snapshot indicates a released latch.
    pub fn isReleased(self: Token) bool {
        return @intFromEnum(self) == 0;
    }
};

/// One-shot countdown latch parameterized on `Backend`.
///
/// `Backend` must expose `WaitError`, `fn wait(*Backend, *const State, Token) WaitError!void`,
/// and `fn wakeAll(*Backend, *const State) void`. `Backend` is stored by value.
///
/// Storage variants: `Static(N)` (comptime capacity) and `Bounded` (runtime capacity).
pub fn Latch(comptime Backend: type) type {
    comptime requireBackend(Backend);

    return struct {
        /// Backend-provided error set for `wait`.
        pub const WaitError = Backend.WaitError;

        /// Comptime-capacity variant. `Static(0)` and any capacity greater
        /// than `maxInt(u32)` are rejected at compile time.
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

                /// Backend-provided error set for `wait`.
                pub const WaitError = Backend.WaitError;

                /// Comptime arrival capacity.
                pub const arrival_capacity: usize = capacity_arrivals;

                const capacity_u32: u32 = @intCast(capacity_arrivals);

                /// Return a latch pre-armed with `remaining = capacity` and
                /// `backend` stored by value. Must complete before any
                /// concurrent use.
                pub fn init(backend: Backend) Self {
                    return .{ .state = State.init(capacity_u32), .backend = backend };
                }

                /// Decrement remaining. The last arriver release-publishes
                /// `remaining = 0` and calls `backend.wakeAll(&state)`
                /// exactly once; non-last arrivers return without entering
                /// the backend.
                pub fn arrive(self: *Self) void {
                    arriveShared(&self.state, &self.backend);
                }

                /// Block until the latch is released. Fast-path returns
                /// immediately once released; otherwise loops on
                /// `Backend.wait` until observed released.
                pub fn wait(self: *Self) Backend.WaitError!void {
                    return waitShared(&self.state, &self.backend);
                }

                /// Acquire-load `remaining`.
                pub fn pending(self: *const Self) u32 {
                    return self.state.remaining();
                }

                /// Arrival capacity (constant).
                pub fn capacity(self: *const Self) u32 {
                    _ = self;
                    return capacity_u32;
                }

                /// Acquire-load and report whether the latch is released.
                pub fn isReleased(self: *const Self) bool {
                    return self.state.isReleased();
                }

                /// Borrow the underlying `State` for backend enrollment or
                /// external `changedSince` recheck.
                pub fn stateRef(self: *const Self) *const State {
                    return &self.state;
                }
            };
        }

        /// Runtime-capacity variant. `capacity == 0` is a caller-contract
        /// violation and traps under `core.debug.checksEnabled(.build_mode)`.
        pub const Bounded = struct {
            arrival_capacity: u32,
            state: State,
            backend: Backend,

            /// Backend-provided error set for `wait`.
            pub const WaitError = Backend.WaitError;

            /// Return a latch pre-armed with `remaining = capacity_arrivals`
            /// and `backend` stored by value. Must complete before any
            /// concurrent use.
            pub fn init(capacity_arrivals: u32, backend: Backend) Bounded {
                if (debug.checksEnabled(.build_mode)) {
                    std.debug.assert(capacity_arrivals > 0);
                }
                return .{
                    .arrival_capacity = capacity_arrivals,
                    .state = State.init(capacity_arrivals),
                    .backend = backend,
                };
            }

            /// Decrement remaining; see `Static.arrive` for the shared
            /// contract.
            pub fn arrive(self: *Bounded) void {
                arriveShared(&self.state, &self.backend);
            }

            /// Block until the latch is released; see `Static.wait`.
            pub fn wait(self: *Bounded) Backend.WaitError!void {
                return waitShared(&self.state, &self.backend);
            }

            /// Acquire-load `remaining`.
            pub fn pending(self: *const Bounded) u32 {
                return self.state.remaining();
            }

            /// Arrival capacity stored at construction.
            pub fn capacity(self: *const Bounded) u32 {
                return self.arrival_capacity;
            }

            /// Acquire-load and report whether the latch is released.
            pub fn isReleased(self: *const Bounded) bool {
                return self.state.isReleased();
            }

            /// Borrow the underlying `State` for backend enrollment or
            /// external `changedSince` recheck.
            pub fn stateRef(self: *const Bounded) *const State {
                return &self.state;
            }
        };
    };
}

// Shared arrival body used by both `Static(N)` and `Bounded`. Runs the
// reservation CAS loop and calls `wakeAll` on the last-arrival path.
fn arriveShared(state: *State, backend: anytype) void {
    while (true) {
        const observed = state.observe();
        const rem = observed.remaining();
        if (rem == 0) {
            // Over-arrival: caller-contract violation. Trap under
            // checksEnabled; saturate at zero in release without wrap and
            // without a second wakeAll.
            if (debug.checksEnabled(.build_mode)) unreachable;
            return;
        }
        if (state.word.cmpxchgWeak(@intFromEnum(observed), rem - 1, .acq_rel, .acquire)) |_| continue;
        if (rem == 1) backend.wakeAll(state);
        return;
    }
}

// Shared wait body used by both `Static(N)` and `Bounded`. Fast-paths
// released state, otherwise loops on `Backend.wait` until released.
fn waitShared(state: *State, backend: anytype) @TypeOf(backend.*).WaitError!void {
    if (state.isReleased()) return;
    while (true) {
        const token = state.observe();
        if (token.isReleased()) return;
        try backend.wait(state, token);
    }
}

// Comptime interface check for `Backend`. Mirrors the shared wait/wake
// contract: explicit `WaitError` error set, `wait`, and `wakeAll` decls.
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
