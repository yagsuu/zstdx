//! One-shot init primitive. Spec: docs/specs/sync/once.md.

const std = @import("std");
const builtin = @import("builtin");

const debug = @import("../core/debug.zig");

// State word encoding: bits 0..1 hold the init state; bits 2..31 hold a
// generation counter that advances on every claim, publish, and rollback so
// that losers observing an old token see the transition on their
// post-registration recheck.
const state_mask: u32 = 0b11;
const generation_step: u32 = 0b100;
const untouched_bits: u32 = 0b00;
const running_bits: u32 = 0b01;
const done_bits: u32 = 0b10;

/// One-shot init state substrate. One atomic `u32` encodes both the sticky
/// init state and a generation counter; every reader uses acquire loads and
/// every transition uses a release store.
pub const State = struct {
    word: std.atomic.Value(u32),

    /// Return a fresh state: `untouched` bits, generation zero.
    pub fn init() State {
        return .{ .word = std.atomic.Value(u32).init(0) };
    }

    /// Acquire-load the word and report whether the state bits equal
    /// `done` (`0b10`).
    pub fn isDone(self: *const State) bool {
        return (self.word.load(.acquire) & state_mask) == done_bits;
    }

    /// Acquire-load the word into a `Token` snapshot used to arm a
    /// lost-wakeup-safe wait.
    pub fn observe(self: *const State) Token {
        return @enumFromInt(self.word.load(.acquire));
    }

    /// Acquire-load the word and report whether any claim, publish, or
    /// rollback transition has occurred since `token` was observed.
    pub fn changedSince(self: *const State, token: Token) bool {
        return self.word.load(.acquire) != @intFromEnum(token);
    }

    // Try to CAS untouched(gen=G) -> running(gen=G+1). Returns true on the
    // winning transition. Release on success synchronizes with any acquire
    // load that observes `running`.
    fn tryClaim(self: *State) bool {
        var current = self.word.load(.acquire);
        while (true) {
            if ((current & state_mask) != untouched_bits) return false;

            const gen_next = (current & ~state_mask) +% generation_step;
            const next = gen_next | running_bits;
            if (self.word.cmpxchgWeak(current, next, .release, .acquire)) |observed| {
                current = observed;
                continue;
            }

            return true;
        }
    }

    // Publish running(gen=G) -> done(gen=G+1). Only the winning claimer
    // calls this; the store is unconditional and release-ordered so
    // acquire-loading observers synchronize-with the work's writes.
    fn publish(self: *State) void {
        const current = self.word.load(.monotonic);
        std.debug.assert((current & state_mask) == running_bits);
        const gen_next = (current & ~state_mask) +% generation_step;
        self.word.store(gen_next | done_bits, .release);
    }

    // Roll back running(gen=G) -> untouched(gen=G+1). Only the winning
    // claimer of a failed `callChecked` calls this; the release store
    // makes the untouched state and its bumped generation visible to any
    // loser holding the earlier `running` token.
    fn rollback(self: *State) void {
        const current = self.word.load(.monotonic);
        std.debug.assert((current & state_mask) == running_bits);
        const gen_next = (current & ~state_mask) +% generation_step;
        self.word.store(gen_next | untouched_bits, .release);
    }
};

/// Observed snapshot of a `State` word. Compares by identity for
/// `changedSince`; carries both the state bits and the generation counter.
pub const Token = enum(u32) {
    _,

    /// True if the token's state bits equal `done` (`0b10`).
    pub fn isDone(self: Token) bool {
        return (@intFromEnum(self) & state_mask) == done_bits;
    }
};

// Recursion-detection substrate. `current_claim` is a threadlocal typed
// pointer to the state currently owned by this thread's `work` invocation;
// `null` when not inside a claim. The helpers no-op when
// `checksEnabled(.build_mode)` is off or when the target is
// `single_threaded` — hosted-freestanding maps `threadlocal` onto shared
// storage in that case, which would produce cross-thread false positives.
threadlocal var current_claim: ?*const State = null;

fn checkNotRecursive(state: *const State) void {
    if (comptime !debug.checksEnabled(.build_mode)) return;
    if (comptime builtin.single_threaded) return;
    std.debug.assert(current_claim != state);
}

fn enterClaim(state: *const State) void {
    if (comptime !debug.checksEnabled(.build_mode)) return;
    if (comptime builtin.single_threaded) return;
    current_claim = state;
}

fn leaveClaim(state: *const State) void {
    if (comptime !debug.checksEnabled(.build_mode)) return;
    if (comptime builtin.single_threaded) return;
    if (current_claim == state) current_claim = null;
}

/// Wait-capable one-shot init family parameterized on `Backend`. `Backend`
/// must expose `WaitError`, `fn wait(*Backend, *const State, Token) WaitError!void`,
/// and `fn wakeAll(*Backend, *const State) void`. `Backend` is stored by value.
pub fn Once(comptime Backend: type) type {
    comptime requireBackend(Backend);

    return struct {
        state: State,
        backend: Backend,

        const Self = @This();

        /// Backend-provided error set for `wait`.
        pub const WaitError = Backend.WaitError;

        /// Return a `Once` with a fresh state and the supplied backend
        /// stored by value. Must complete before any concurrent use;
        /// copying or moving the `Once` after any pointer to it is shared
        /// is outside the primitive's contract.
        pub fn init(backend: Backend) Self {
            return .{ .state = State.init(), .backend = backend };
        }

        /// Acquire-load the state and report whether `work` has published.
        pub fn isDone(self: *const Self) bool {
            return self.state.isDone();
        }

        /// Borrow the underlying `State` for backend enrollment or
        /// external `changedSince` recheck.
        pub fn stateRef(self: *const Self) *const State {
            return &self.state;
        }

        /// Run `work(ctx)` at most once against `self.state`. Winners
        /// publish `done` and call `backend.wakeAll(&state)`; losers wait
        /// via the backend and return only after observing `done`. On the
        /// fast path (already `done`), returns immediately without
        /// invoking `work`. Never allocates.
        pub fn call(
            self: *Self,
            comptime Ctx: type,
            comptime work: fn (ctx: Ctx) void,
            ctx: Ctx,
        ) WaitError!void {
            if (self.state.isDone()) return;

            checkNotRecursive(&self.state);

            if (self.state.tryClaim()) {
                enterClaim(&self.state);
                defer leaveClaim(&self.state);

                work(ctx);

                self.state.publish();
                self.backend.wakeAll(&self.state);
                return;
            }

            while (true) {
                const token = self.state.observe();
                if (token.isDone()) return;
                try self.backend.wait(&self.state, token);
            }
        }

        /// Run `work(ctx)` at most once until one invocation succeeds. On
        /// a work error, roll back to `untouched` (bumping the
        /// generation), wake all waiters, and return the error unchanged;
        /// subsequent callers may re-race the claim. On success, publish
        /// `done` and call `backend.wakeAll(&state)`. Never allocates.
        pub fn callChecked(
            self: *Self,
            comptime Ctx: type,
            comptime E: type,
            comptime work: fn (ctx: Ctx) E!void,
            ctx: Ctx,
        ) (E || WaitError)!void {
            if (self.state.isDone()) return;

            checkNotRecursive(&self.state);

            // Rollback returns state to `untouched`, so every loser released
            // by `wakeAll` re-races the claim instead of waiting on a stale token.
            while (true) {
                if (self.state.isDone()) return;

                if (self.state.tryClaim()) {
                    enterClaim(&self.state);
                    defer leaveClaim(&self.state);

                    work(ctx) catch |err| {
                        self.state.rollback();
                        self.backend.wakeAll(&self.state);
                        return err;
                    };

                    self.state.publish();
                    self.backend.wakeAll(&self.state);
                    return;
                }

                const token = self.state.observe();
                if (token.isDone()) return;
                // Rollback races: state is `untouched` (someone rolled back
                // between tryClaim and observe). Skip the backend wait and
                // retry the claim immediately.
                if ((@intFromEnum(token) & state_mask) == untouched_bits) continue;
                try self.backend.wait(&self.state, token);
            }
        }
    };
}

// This comptime backend check requires explicit `WaitError`, `wait`, and
// `wakeAll` declarations, rejects `anyerror`, and leaves full signature
// enforcement to the call sites in `Once`.
fn requireBackend(comptime Backend: type) void {
    if (!@hasDecl(Backend, "WaitError")) {
        @compileError("Once(Backend): Backend must declare pub const WaitError");
    }
    const WaitError = Backend.WaitError;
    const info = @typeInfo(WaitError);
    if (info != .error_set) {
        @compileError("Once(Backend): Backend.WaitError must be an error set");
    }
    if (info.error_set == null) {
        @compileError("Once(Backend): Backend.WaitError must be an explicit error set; anyerror is not approved");
    }
    if (!@hasDecl(Backend, "wait")) {
        @compileError("Once(Backend): Backend must declare pub fn wait(*Backend, *const State, Token) WaitError!void");
    }
    if (!@hasDecl(Backend, "wakeAll")) {
        @compileError("Once(Backend): Backend must declare pub fn wakeAll(*Backend, *const State) void");
    }
}
