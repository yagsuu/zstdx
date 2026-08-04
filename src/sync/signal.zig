//! Manual-reset sticky notification primitive. See `docs/specs/sync/signal.md`.

const std = @import("std");

// State word encoding: bit 0 is the set flag (1 = set, 0 = unset); the
// remaining bits are a generation counter that advances by `generation_step`
// on every real set/clear edge. Redundant `set` while set and redundant
// `clear` while unset leave the word unchanged.
const set_bit: usize = 1;
const generation_step: usize = 2;

/// Manual-reset sticky notification family. `Signal.State` is the raw atomic
/// word, `Signal.Token` is an observed snapshot, and `Signal.Manual(Backend)`
/// pairs the state with a compile-time wait/wake backend.
pub const Signal = struct {
    /// Initial state selector for `State.init` and `Manual.init`.
    pub const InitialState = enum { unset, set };

    /// Observed snapshot of a `State` word. Compares by identity for
    /// `changedSince`; carries both the set flag and the generation counter.
    pub const Token = enum(usize) {
        _,

        /// True if the token's set flag is set at the moment it was observed.
        pub fn isSet(self: Token) bool {
            return (@intFromEnum(self) & set_bit) != 0;
        }
    };

    /// Atomic sticky signal state. One `usize` word encodes the set flag and
    /// the generation counter; all reads are `.acquire` and all publications
    /// are `.release`.
    pub const State = struct {
        word: std.atomic.Value(usize),

        /// Initializes an `.unset` or `.set` state; generation starts at zero.
        pub fn init(initial: InitialState) State {
            return .{ .word = std.atomic.Value(usize).init(switch (initial) {
                .unset => 0,
                .set => set_bit,
            }) };
        }

        /// Acquire-loads the word and reports whether the set flag is set.
        pub fn isSet(self: *const State) bool {
            return self.observe().isSet();
        }

        /// Acquire-loads the word into a `Token`; used to arm a lost-wakeup
        /// safe wait.
        pub fn observe(self: *const State) Token {
            return @enumFromInt(self.word.load(.acquire));
        }

        /// Acquire-loads the word and reports whether any set/clear transition
        /// has occurred since `token` was observed.
        pub fn changedSince(self: *const State, token: Token) bool {
            return self.word.load(.acquire) != @intFromEnum(token);
        }
    };

    /// Wait-capable manual-reset signal parameterized on `Backend`. `Backend`
    /// must expose `WaitError`, `fn wait(*Backend, *const State, Token) WaitError!void`,
    /// and `fn wakeAll(*Backend, *const State) void`. `Backend` is stored by value.
    pub fn Manual(comptime Backend: type) type {
        return struct {
            state: Signal.State,
            backend: Backend,

            const Self = @This();

            /// Backend-provided error set for `wait`.
            pub const WaitError = Backend.WaitError;

            /// Returns a signal with initialized state and backend. Must complete before
            /// any concurrent use; copying or moving the signal after initialization is
            /// outside the primitive's contract.
            pub fn init(initial: Signal.InitialState, backend: Backend) Self {
                return .{ .state = Signal.State.init(initial), .backend = backend };
            }

            /// Acquire-loads the state and reports the set flag.
            pub fn isSet(self: *const Self) bool {
                return self.state.isSet();
            }

            /// Transitions to set. Idempotent: only the winning unset-to-set
            /// CAS bumps the generation, release-publishes the transition,
            /// and calls `backend.wakeAll(&state)`.
            pub fn set(self: *Self) void {
                var current = self.state.word.load(.acquire);
                while (true) {
                    if ((current & set_bit) != 0) return;

                    const next = (current +% generation_step) | set_bit;
                    if (self.state.word.cmpxchgWeak(current, next, .release, .acquire)) |observed| {
                        current = observed;
                        continue;
                    }

                    self.backend.wakeAll(&self.state);
                    return;
                }
            }

            /// Transitions to unset. Idempotent: only the winning set-to-unset
            /// CAS bumps the generation and release-publishes the transition.
            /// Never invokes the backend.
            pub fn clear(self: *Self) void {
                var current = self.state.word.load(.acquire);
                while (true) {
                    if ((current & set_bit) == 0) return;

                    const next = (current +% generation_step) & ~set_bit;
                    if (self.state.word.cmpxchgWeak(current, next, .release, .acquire)) |observed| {
                        current = observed;
                        continue;
                    }

                    return;
                }
            }

            /// Waits until it observes the signal set.
            ///
            /// Each iteration observes a token and returns immediately if set. Otherwise,
            /// it calls `backend.wait(&state, token)`. Spurious backend successes
            /// re-observe the state before returning. Backend errors are propagated unchanged.
            pub fn wait(self: *Self) WaitError!void {
                while (true) {
                    const token = self.state.observe();
                    if (token.isSet()) return;
                    try self.backend.wait(&self.state, token);
                }
            }

            /// Borrows the underlying `State` for backend enrollment or
            /// external `changedSince` recheck.
            pub fn stateRef(self: *const Self) *const Signal.State {
                return &self.state;
            }
        };
    }
};
