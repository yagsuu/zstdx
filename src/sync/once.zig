//! One-shot init primitive. See `docs/specs/sync/once.md`.

const std = @import("std");
const builtin = @import("builtin");

const debug = @import("../core/debug.zig");

/// Wait-capable one-shot initializer.
/// Requirements: `Backend` provides `WaitError`, `wait`, and `wakeAll`.
pub fn Once(comptime Backend: type) type {
    comptime requireBackend(Backend);

    return struct {
        state: State,
        backend: Backend,

        const Self = @This();

        pub const WaitError = Backend.WaitError;

        /// Requirements: Initialize before sharing. Do not copy or move after sharing.
        pub fn init(backend: Backend) Self {
            return .{ .state = State.init(), .backend = backend };
        }

        /// Returns whether initialization published. Uses acquire.
        pub fn isDone(self: *const Self) bool {
            return self.state.isDone();
        }

        /// Runs `work(ctx)` at most once; losers wait until publication.
        /// Effects: Wakes waiters after publication. Never allocates.
        pub fn call(
            self: *Self,
            comptime Ctx: type,
            comptime work: fn (ctx: Ctx) void,
            ctx: Ctx,
        ) WaitError!void {
            if (self.state.isDone()) return;

            checkNotRecursive(&self.state);

            if (self.state.tryClaim()) |claim| {
                enterClaim(&self.state);
                defer leaveClaim(&self.state);

                work(ctx);

                self.state.publish(claim);
                self.backend.wakeAll(&self.state);
                return;
            }

            while (true) {
                const token = self.state.observe();
                if (token.isDone()) return;
                try self.backend.wait(&self.state, token);
            }
        }

        /// Runs `work(ctx)` until one invocation succeeds.
        /// Effects: On error, rolls back, wakes waiters, and propagates the error.
        /// Never allocates.
        pub fn callChecked(
            self: *Self,
            comptime Ctx: type,
            comptime E: type,
            comptime work: fn (ctx: Ctx) E!void,
            ctx: Ctx,
        ) (E || WaitError)!void {
            if (self.state.isDone()) return;

            checkNotRecursive(&self.state);

            // Retry after rollback instead of waiting on a stale token.
            while (true) {
                if (self.state.isDone()) return;

                if (self.state.tryClaim()) |claim| {
                    enterClaim(&self.state);
                    defer leaveClaim(&self.state);

                    work(ctx) catch |err| {
                        self.state.rollback(claim);
                        self.backend.wakeAll(&self.state);
                        return err;
                    };

                    self.state.publish(claim);
                    self.backend.wakeAll(&self.state);
                    return;
                }

                const token = self.state.observe();
                if (token.isDone()) return;

                // Rollback can restore `untouched` after the failed claim.
                if (wordFromToken(token).phase == .untouched) continue;
                try self.backend.wait(&self.state, token);
            }
        }
    };
}

/// Atomic once state. Reads use acquire; transitions use release.
pub const State = struct {
    word: std.atomic.Value(Word),

    /// Returns untouched state at generation zero.
    pub fn init() State {
        return .{ .word = std.atomic.Value(Word).init(.{
            .phase = .untouched,
            .generation = 0,
        }) };
    }

    /// Returns whether initialization published. Uses acquire.
    pub fn isDone(self: *const State) bool {
        return self.word.load(.acquire).phase == .done;
    }

    /// Returns an acquire snapshot for backend rechecks.
    pub fn observe(self: *const State) Token {
        return tokenFromWord(self.word.load(.acquire));
    }

    /// Returns whether state changed after `token`. Uses acquire.
    pub fn changedSince(self: *const State, token: Token) bool {
        return self.word.load(.acquire) != wordFromToken(token);
    }

    fn advance(current: Word, phase: Phase) Word {
        return .{
            .phase = phase,
            .generation = current.generation +% 1,
        };
    }

    // The release claim synchronizes with later acquire observers.
    fn tryClaim(self: *State) ?Claim {
        var current = self.word.load(.acquire);
        while (true) {
            if (current.phase != .untouched) return null;

            const running = advance(current, .running);
            if (self.word.cmpxchgWeak(current, running, .release, .acquire)) |observed| {
                current = observed;
                continue;
            }

            return .{ .running = running };
        }
    }

    // Trap rather than overwrite a state that no longer matches the claim.
    fn publish(self: *State, claim: Claim) void {
        const done = advance(claim.running, .done);
        if (self.word.cmpxchgStrong(claim.running, done, .release, .monotonic) != null) {
            @panic("Once: claim changed before publication");
        }
    }

    // Advance generation so stale wait tokens observe rollback.
    fn rollback(self: *State, claim: Claim) void {
        const untouched = advance(claim.running, .untouched);
        if (self.word.cmpxchgStrong(claim.running, untouched, .release, .monotonic) != null) {
            @panic("Once: claim changed before rollback");
        }
    }
};

/// Opaque state snapshot for backend rechecks.
pub const Token = enum(u32) {
    _,

    /// True if this snapshot observed the published state.
    pub fn isDone(self: Token) bool {
        return wordFromToken(self).phase == .done;
    }
};

// State word encoding: `phase` occupies bits 0..1; `generation` occupies
// bits 2..31. Every transition advances `generation` so that losers holding
// an earlier token observe claim, publication, or rollback.
const Phase = enum(u2) {
    untouched,
    running,
    done,
    _,
};

const Word = packed struct(u32) {
    phase: Phase,
    generation: u30,
};

// A claim owns this exact `running` word until publication or rollback.
const Claim = struct {
    running: Word,
};

fn wordFromToken(token: Token) Word {
    const bits = @intFromEnum(token);
    return @bitCast(bits);
}

fn tokenFromWord(word: Word) Token {
    const bits: u32 = @bitCast(word);
    return @enumFromInt(bits);
}

// Disable recursive-use assertions where `threadlocal` storage is shared.
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
