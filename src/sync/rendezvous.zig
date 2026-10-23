//! reusable cyclic barriers

const std = @import("std");

const debug = @import("core").debug;
const BackendImpl = @import("backend/impl.zig");

// the final arrival resets count and advances generation atomically; zero is never published
const remaining_bits: u6 = 32;
const remaining_mask: u64 = (@as(u64, 1) << remaining_bits) - 1;

pub const State = struct {
    word: std.atomic.Value(u64),

    pub fn init(capacity_parties: u32) State {
        if (debug.checksEnabled()) {
            std.debug.assert(capacity_parties > 0);
        }
        return .{ .word = std.atomic.Value(u64).init(packWord(capacity_parties, 0)) };
    }

    pub fn observe(self: *const State) Token {
        return @enumFromInt(self.word.load(.acquire));
    }

    /// detects generation changes, not changes in the remaining count
    pub fn changedSince(self: *const State, token: Token) bool {
        const current: Token = @enumFromInt(self.word.load(.acquire));
        return current.generation() != token.generation();
    }

    pub fn remaining(self: *const State) u32 {
        return unpackRemaining(self.word.load(.acquire));
    }

    pub fn generation(self: *const State) u32 {
        return unpackGeneration(self.word.load(.acquire));
    }
};

pub const Token = enum(u64) {
    _,

    pub fn remaining(self: Token) u32 {
        return unpackRemaining(@intFromEnum(self));
    }

    pub fn generation(self: Token) u32 {
        return unpackGeneration(@intFromEnum(self));
    }
};

/// blocking backends must enroll and recheck before parking
/// initialize before concurrent use; live state queries use acquire ordering
pub fn Rendezvous(comptime Backend: type) type {
    comptime BackendImpl.requireBackend(Backend, "Rendezvous(Backend)");

    return struct {
        pub const WaitError = Backend.WaitError;

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

                pub const WaitError = Backend.WaitError;

                pub const party_capacity: usize = capacity_parties;

                const capacity_u32: u32 = @intCast(capacity_parties);

                pub fn init(backend: Backend) Self {
                    return .{ .state = State.init(capacity_u32), .backend = backend };
                }

                /// a wait error does not undo this arrival
                pub fn arrive(self: *Self) Backend.WaitError!void {
                    return arriveShared(&self.state, &self.backend, capacity_u32);
                }

                pub fn pending(self: *const Self) u32 {
                    return self.state.remaining();
                }

                pub fn capacity(self: *const Self) u32 {
                    _ = self;
                    return capacity_u32;
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
            capacity_parties: u32,
            state: State,
            backend: Backend,

            pub const WaitError = Backend.WaitError;

            pub fn init(capacity_parties: u32, backend: Backend) Bounded {
                if (debug.checksEnabled()) {
                    std.debug.assert(capacity_parties > 0);
                }
                return .{
                    .capacity_parties = capacity_parties,
                    .state = State.init(capacity_parties),
                    .backend = backend,
                };
            }

            /// a wait error does not undo this arrival
            pub fn arrive(self: *Bounded) Backend.WaitError!void {
                return arriveShared(&self.state, &self.backend, self.capacity_parties);
            }

            pub fn pending(self: *const Bounded) u32 {
                return self.state.remaining();
            }

            pub fn capacity(self: *const Bounded) u32 {
                return self.capacity_parties;
            }

            pub fn generation(self: *const Bounded) u32 {
                return self.state.generation();
            }

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
