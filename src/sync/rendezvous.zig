//! Reusable N-way cyclic barrier. Spec: docs/specs/sync/rendezvous.md.

const std = @import("std");

const debug = @import("../core/debug.zig");

// State word layout: `remaining` in the low 32 bits, `generation` in the
// high 32 bits. The last arriver installs `remaining = capacity` and
// `generation = observed_generation +% 1` in a single CAS; no observer
// ever sees `remaining == 0`.
const remaining_bits: u6 = 32;
const remaining_mask: u64 = (@as(u64, 1) << remaining_bits) - 1;

/// Atomic rendezvous state. One `u64` word encodes the current
/// `remaining` count in the low 32 bits and the `generation` counter in
/// the high 32 bits.
pub const State = struct {
    word: std.atomic.Value(u64),

    /// `capacity_parties` must be strictly positive; zero traps under
    /// `core.debug.checksEnabled(.build_mode)`. Generation starts at `0`.
    pub fn init(capacity_parties: u32) State {
        if (debug.checksEnabled(.build_mode)) {
            std.debug.assert(capacity_parties > 0);
        }
        return .{ .word = std.atomic.Value(u64).init(packWord(capacity_parties, 0)) };
    }

    /// Acquire-load the word into a `Token` snapshot used to arm a
    /// lost-wakeup-safe wait.
    pub fn observe(self: *const State) Token {
        return @enumFromInt(self.word.load(.acquire));
    }

    /// Acquire-load the word and report whether the generation has
    /// advanced since `token` was observed.
    pub fn changedSince(self: *const State, token: Token) bool {
        const current: Token = @enumFromInt(self.word.load(.acquire));
        return current.generation() != token.generation();
    }

    /// Acquire-load the word and return the current `remaining` count.
    pub fn remaining(self: *const State) u32 {
        return unpackRemaining(self.word.load(.acquire));
    }

    /// Acquire-load the word and return the current generation counter.
    pub fn generation(self: *const State) u32 {
        return unpackGeneration(self.word.load(.acquire));
    }
};

/// Observed snapshot of a `State` word. Carries both the remaining count
/// and the generation counter.
pub const Token = enum(u64) {
    _,

    /// Remaining parties recorded at observation time.
    pub fn remaining(self: Token) u32 {
        return unpackRemaining(@intFromEnum(self));
    }

    /// Generation recorded at observation time.
    pub fn generation(self: Token) u32 {
        return unpackGeneration(@intFromEnum(self));
    }
};

/// Reusable N-way cyclic barrier parameterized on `Backend`.
///
/// `Backend` must expose `WaitError`, `fn wait(*Backend, *const State, Token) WaitError!void`,
/// and `fn wakeAll(*Backend, *const State) void`. `Backend` is stored by value.
///
/// Storage variants: `Static(N)` (comptime capacity) and `Bounded` (runtime capacity).
pub fn Rendezvous(comptime Backend: type) type {
    comptime requireBackend(Backend);

    return struct {
        /// Backend-provided error set for `wait`.
        pub const WaitError = Backend.WaitError;

        /// Comptime-capacity variant. `Static(0)` and any capacity greater
        /// than `maxInt(u32)` are rejected at compile time.
        pub fn Static(comptime capacity_parties: usize) type {
            comptime {
                if (capacity_parties == 0) {
                    @compileError("Rendezvous.Static requires capacity_parties >= 1");
                }
                if (capacity_parties > std.math.maxInt(u32)) {
                    @compileError("Rendezvous.Static requires capacity_parties <= maxInt(u32)");
                }
            }

            return struct {
                state: State,
                backend: Backend,

                const Self = @This();

                /// Backend-provided error set for `wait`.
                pub const WaitError = Backend.WaitError;

                /// Comptime party capacity (slot count).
                pub const party_capacity: usize = capacity_parties;

                const capacity_u32: u32 = @intCast(capacity_parties);

                /// Return a rendezvous pre-armed for the first generation
                /// with `backend` stored by value. Must complete before
                /// any concurrent use.
                pub fn init(backend: Backend) Self {
                    return .{ .state = State.init(capacity_u32), .backend = backend };
                }

                /// Decrement remaining for the current generation. The
                /// last arriver advances the generation, resets remaining
                /// to `party_capacity`, and calls `backend.wakeAll(&state)`;
                /// every other caller waits until the generation
                /// advances. Backend `WaitError` propagates unchanged;
                /// the caller's arrival CAS has already committed.
                pub fn arrive(self: *Self) Backend.WaitError!void {
                    return arriveShared(&self.state, &self.backend, capacity_u32);
                }

                /// Acquire-load `remaining` for the current generation.
                pub fn pending(self: *const Self) u32 {
                    return self.state.remaining();
                }

                /// Party capacity (constant).
                pub fn capacity(self: *const Self) u32 {
                    _ = self;
                    return capacity_u32;
                }

                /// Acquire-load the current generation counter.
                pub fn generation(self: *const Self) u32 {
                    return self.state.generation();
                }

                /// Borrow the underlying `State` for backend enrollment
                /// or external `changedSince` recheck.
                pub fn stateRef(self: *const Self) *const State {
                    return &self.state;
                }
            };
        }

        /// Runtime-capacity variant. `capacity_parties` is set at
        /// construction; `0` is a caller-contract violation and traps
        /// under `core.debug.checksEnabled(.build_mode)`.
        pub const Bounded = struct {
            capacity_parties: u32,
            state: State,
            backend: Backend,

            /// Backend-provided error set for `wait`.
            pub const WaitError = Backend.WaitError;

            /// Return a rendezvous pre-armed for the first generation
            /// with `backend` stored by value.
            pub fn init(capacity_parties: u32, backend: Backend) Bounded {
                if (debug.checksEnabled(.build_mode)) {
                    std.debug.assert(capacity_parties > 0);
                }
                return .{
                    .capacity_parties = capacity_parties,
                    .state = State.init(capacity_parties),
                    .backend = backend,
                };
            }

            /// Decrement remaining for the current generation; see
            /// `Static.arrive` for the shared contract.
            pub fn arrive(self: *Bounded) Backend.WaitError!void {
                return arriveShared(&self.state, &self.backend, self.capacity_parties);
            }

            /// Acquire-load `remaining` for the current generation.
            pub fn pending(self: *const Bounded) u32 {
                return self.state.remaining();
            }

            /// Party capacity stored at construction.
            pub fn capacity(self: *const Bounded) u32 {
                return self.capacity_parties;
            }

            /// Acquire-load the current generation counter.
            pub fn generation(self: *const Bounded) u32 {
                return self.state.generation();
            }

            /// Borrow the underlying `State` for backend enrollment or
            /// external `changedSince` recheck.
            pub fn stateRef(self: *const Bounded) *const State {
                return &self.state;
            }
        };
    };
}

inline fn packWord(remaining: u32, generation: u32) u64 {
    return @as(u64, remaining) | (@as(u64, generation) << remaining_bits);
}

inline fn unpackRemaining(word: u64) u32 {
    return @intCast(word & remaining_mask);
}

inline fn unpackGeneration(word: u64) u32 {
    return @intCast(word >> remaining_bits);
}

// Shared arrival body used by both `Static(N)` and `Bounded`. Runs the
// reservation CAS loop, then, for non-last arrivers, the wait loop.
fn arriveShared(state: *State, backend: anytype, capacity: u32) @TypeOf(backend.*).WaitError!void {
    std.debug.assert(capacity > 0);

    var my_generation: u32 = undefined;

    while (true) {
        const observed = state.observe();
        const rem = observed.remaining();
        const gen = observed.generation();
        my_generation = gen;

        std.debug.assert(rem > 0);

        const next_word: u64 = if (rem == 1)
            packWord(capacity, gen +% 1)
        else
            packWord(rem - 1, gen);

        if (state.word.cmpxchgWeak(@intFromEnum(observed), next_word, .acq_rel, .acquire)) |_| {
            continue;
        }

        if (rem == 1) {
            backend.wakeAll(state);
            return;
        }
        break;
    }

    while (true) {
        const token = state.observe();
        if (token.generation() != my_generation) return;
        try backend.wait(state, token);
    }
}

// Comptime interface check for `Backend`. Mirrors `Once`'s requirement:
// explicit `WaitError` error set, `wait`, and `wakeAll` decls.
fn requireBackend(comptime Backend: type) void {
    if (!@hasDecl(Backend, "WaitError")) {
        @compileError("Rendezvous(Backend): Backend must declare pub const WaitError");
    }
    const info = @typeInfo(Backend.WaitError);
    if (info != .error_set) {
        @compileError("Rendezvous(Backend): Backend.WaitError must be an error set");
    }
    if (info.error_set == null) {
        @compileError(
            "Rendezvous(Backend): Backend.WaitError must be an explicit error set; " ++
                "anyerror is not approved",
        );
    }
    if (!@hasDecl(Backend, "wait")) {
        @compileError(
            "Rendezvous(Backend): Backend must declare " ++
                "pub fn wait(*Backend, *const State, Token) WaitError!void",
        );
    }
    if (!@hasDecl(Backend, "wakeAll")) {
        @compileError(
            "Rendezvous(Backend): Backend must declare " ++
                "pub fn wakeAll(*Backend, *const State) void",
        );
    }
}
