# Sync once

Status: Approved.

`stdx.sync.Once(Backend)` is a one-shot init primitive. It runs a caller-
provided initializer exactly once against a shared `sync.once.State` word, safe
from any number of concurrent callers, callable from interrupt-off and
pre-runtime contexts.

## Owned scope

This spec owns:

- `sync.once.State`, the atomic sticky init-state word;
- `sync.once.Token`, an opaque observed-word identity snapshot;
- `sync.Once(Backend)`, the wait-capable one-shot init family;
- `call` and `callChecked` semantics;
- ordering contract for publication of writes performed by the initializer;
- panicking-callback contract;
- caller-contract rule against recursive invocation, with debug detection on
  targets that provide per-thread `threadlocal` storage;
- backend requirements delegated to the shared wait/wake contract defined in
  `docs/specs/sync/spin.md`;
- lost-wakeup prevention via token comparison and backend recheck;
- allocation, waiting, concurrency, and ordering contracts;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- global default `Once` instances, module-init registries, or hidden
  singletons;
- lazy value cache with a return slot (`Once` returns `void`; a
  `LazyValue(T)` primitive is a separate spec if a consumer needs it);
- per-thread, per-fiber, or per-CPU keyed init variants;
- timeout, deadline, or cancellation of an in-flight initializer;
- reset-to-initial API on a completed `Once`;
- poisoning on panicking initializers;
- futex, kernel wait queue, scheduler, thread parking, preemption, or
  priority-inheritance implementations;
- heap allocation or dynamic waiter allocation;
- data visibility for anything outside the initializer's own writes.

A backend may provide scheduler-specific waiter behavior. That behavior is
explicit in the `Once(Backend)` type and is not owned by this spec.

## Public namespace

`Once` lives under `stdx.sync`; its backend-independent state substrate lives
under the `stdx.sync.once` submodule so the `Once(Backend)` factory can keep
its call syntax while backends name stable state/token types:

```zig
stdx.sync.Once
stdx.sync.once.State
stdx.sync.once.Token
```

Source ownership:

```text
src/sync.zig
src/sync/once.zig
test/sync/once_test.zig
```

`src/sync.zig` re-exports:

```zig
pub const once = @import("sync/once.zig");

pub const Once = once.Once;
```

`src/sync.zig` is a thin facade. It contains no logic beyond re-exporting
and aliasing.

## API

```zig
pub const State = struct {
    pub fn init() State;
    pub fn isDone(self: *const State) bool;
    pub fn observe(self: *const State) Token;
    pub fn changedSince(self: *const State, token: Token) bool;
};

pub const Token = enum(u32) {
    _,

    pub fn isDone(self: Token) bool;
};

pub fn Once(comptime Backend: type) type;
```

### `Once(Backend)` returned type

```zig
pub const Self = struct {
    state: State,
    backend: Backend,

    pub const WaitError = Backend.WaitError;

    pub fn init(backend: Backend) Self;

    pub fn isDone(self: *const Self) bool;

    pub fn call(
        self: *Self,
        comptime Ctx: type,
        comptime work: fn (ctx: Ctx) void,
        ctx: Ctx,
    ) WaitError!void;

    pub fn callChecked(
        self: *Self,
        comptime Ctx: type,
        comptime E: type,
        comptime work: fn (ctx: Ctx) E!void,
        ctx: Ctx,
    ) (E || WaitError)!void;
};
```

`State` and `Token` support `Backend` implementations. Normal callers use
only `Once.init`, `Once.isDone`, `Once.call`, and `Once.callChecked`.

There is no `reset`, `retry`, `poison`, `waitOnly`, `waitFor`, or `Manual`
alias in this spec. There is no operation that runs an initializer on `State`
alone: every call goes through a `Once(Backend)` instance so that the wait path
and the recursion-detection hook have a single home.

`Ctx` is a comptime type parameter of `call`/`callChecked`, not stored on
`Once`. The initializer signature is `fn (Ctx) void` (or `fn (Ctx) E!void`),
type-checked at instantiation and monomorphized per call site. Zero
allocation. Zero indirect call.

## Backend interface

`Once(Backend)` requires `Backend` to satisfy the shared wait/wake backend
contract defined in `docs/specs/sync/spin.md`, specialized to `sync.once.State`
and `sync.once.Token`:

```zig
pub const WaitError = error{...};

pub fn wait(
    self: *Backend,
    state: *const stdx.sync.once.State,
    observed: stdx.sync.once.Token,
) WaitError!void;

pub fn wakeAll(self: *Backend, state: *const stdx.sync.once.State) void;
```

`WaitError` must be an explicit error set. `anyerror` is not approved. An
empty error set (`error{}`, as `sync.spin.Backend` uses) is legal; the
`try` in `call`/`callChecked` monomorphizes away for spin-only callers.

`Backend` is stored by value in the `Once`. If backend state is large,
mutable, or shared elsewhere, callers should make `Backend` a pointer or
small handle type.

`Backend.wait` may block, sleep, park, yield, spin, or return spuriously
according to the backend's own contract. `Once.call` loops on spurious
returns until the state is observed done or a backend error is returned.

`Backend.wakeAll` is called with `&self.state` by the winning claimer on
publication and by the winning claimer of `callChecked` on rollback. It must
wake every waiter that could be blocked in `Backend.wait` for this `Once`, or
otherwise make those waiters return.

## State and token representation

`sync.once.State` contains one private atomic `Word` with a `u32` backing
integer. Its packed fields are:

```text
phase:      bits 0..1
generation: bits 2..31
```

`phase` has the values `untouched`, `running`, and `done`. The fourth `u2`
value is reserved. The private layout makes the bit allocation explicit
without masks or shifts in state-transition code.

`sync.once.Token` is an opaque identity snapshot of `Word`. Backends use
`Token` only with `State.changedSince`. `Token.isDone()` reports whether the
snapshot observed `done`.

`State.observe()` acquire-loads the current word and returns a token.
`State.changedSince(token)` acquire-loads the current word and compares it
with `token`. It returns true when a state transition occurred after the
token was observed, including a rollback from `callChecked`.

`State.isDone()` acquire-loads the current word and reports whether its phase
is `done`.

Every transition advances `generation`. Publish is a one-way transition; a
state with phase `done` never transitions again. Rollback (`running` →
`untouched`, only from `callChecked` on error) advances `generation` so that
losers holding an earlier `running` token observe the change.

A successful claim creates a private capability containing the exact
`running` word. `publish` and `rollback` consume that capability with a
strong release CAS. If either CAS fails, the implementation panics rather
than overwrite an unexpected state in any build mode.

Generation wrap can make `State.changedSince` report no change only after
exactly `2^30` state transitions between a token observation and its
comparison. Tests do not execute that many transitions.

## Construction

`Once(Backend).init(backend)` returns a `Self` with a fresh `State` (phase
`untouched`, generation zero) and the supplied backend stored by value.

After initialization, copying a `Once` is outside the primitive's contract.
Once any pointer to a `Once` is shared with another execution context,
moving it is outside the primitive's contract.

## Call semantics

`call(Ctx, work, ctx)` runs `work(ctx)` at most once against `self.state`.

Required algorithm shape:

```zig
pub fn call(self: *Self, comptime Ctx: type, comptime work: fn (Ctx) void, ctx: Ctx) WaitError!void {
    if (self.state.isDone()) return;

    checkNotRecursive(&self.state);

    if (self.state.tryClaim()) |claim| {
        enterClaim(&self.state);
        defer leaveClaim(&self.state);

        work(ctx);

        self.state.publish(claim);  // running -> done, release CAS
        self.backend.wakeAll(&self.state);
        return;
    }

    while (true) {
        const token = self.state.observe();
        if (token.isDone()) return;
        try self.backend.wait(&self.state, token);
    }
}
```

Required behavior:

- if `state` is already `done`, return immediately without invoking `work`;
- otherwise, at most one caller wins the CAS from `untouched` to `running`
  and invokes `work`;
- after `work` returns, publish `done` with a release CAS and call
  `backend.wakeAll(&state)`;
- every losing caller returns only after observing `done`;
- every returning caller synchronizes-with the writes `work` performed
  under acquire semantics on state observation;
- `WaitError` from the backend propagates unchanged; `work` is not invoked
  in that case;
- `call` does not allocate.

## Checked-call semantics

`callChecked(Ctx, E, work, ctx)` runs `work(ctx)` at most once until one
invocation succeeds.

Required algorithm shape:

```zig
pub fn callChecked(
    self: *Self,
    comptime Ctx: type,
    comptime E: type,
    comptime work: fn (Ctx) E!void,
    ctx: Ctx,
) (E || WaitError)!void {
    if (self.state.isDone()) return;

    checkNotRecursive(&self.state);

    if (self.state.tryClaim()) |claim| {
        enterClaim(&self.state);

        work(ctx) catch |err| {
            self.state.rollback(claim);  // running -> untouched, new generation, release CAS
            self.backend.wakeAll(&self.state);
            leaveClaim(&self.state);
            return err;
        };

        self.state.publish(claim);       // running -> done, release CAS
        self.backend.wakeAll(&self.state);
        leaveClaim(&self.state);
        return;
    }

    while (true) {
        const token = self.state.observe();
        if (token.isDone()) return;
        try self.backend.wait(&self.state, token);
    }
}
```

Required behavior:

- rollback restores the phase to `untouched` and bumps generation so that
  any loser holding a `running` token observes the change on its
  post-registration recheck;
- after rollback, `wakeAll(&state)` is called so waiters can return from
  `Backend.wait`, re-observe `untouched`, and try to claim themselves;
- rollback preserves the no-mutation-on-error convention: a caller observing
  `!isDone()` after a failed `callChecked` cannot tell whether any attempt
  ran, only that no successful publication has occurred;
- once one `callChecked` invocation publishes `done`, subsequent callers
  short-circuit on the fast path;
- error values from `work` return unchanged from the winning caller;
- `WaitError` from the backend returns unchanged from any waiting caller;
- `callChecked` does not allocate.

`callChecked` and `call` may operate on the same `State` in a single
program. The state machine does not distinguish which entry point produced
a transition. Mixing them is legal and defined.

## Lost-wakeup contract

`Backend.wait(state, observed)` must not park if the state changed after
`observed` was captured.

Correct backend shape:

1. register or enqueue the current waiter;
2. recheck `state.changedSince(observed)` after registration;
3. if changed, unregister/cancel the wait and return success;
4. otherwise park, block, yield, or spin according to backend policy;
5. return success after wake or spurious wake, or return a `WaitError`.

A backend that cannot perform the post-registration recheck is not valid
for `Once`.

## Concurrency contract

Any number of contexts may call `call` or `callChecked` concurrently against
the same `Once`. Exactly one wins the claim CAS on any given generation.

`Once.isDone`, `State.isDone`, `State.observe`, and `State.changedSince` do
not mutate state and may execute concurrently with any other operation.

`init` must be called before any concurrent use.

Publication ordering:

- the CAS that transitions `untouched → running` is a release operation on
  the running state;
- the strong CAS that transitions `running → done` is a release operation on
  the done state, sequenced-after every write performed inside `work`;
- every observer that reads `done` under acquire semantics synchronizes-with
  the `work` writes.

Rollback ordering (checked variant only):

- the strong CAS that transitions `running → untouched` is a release
  operation; it does not synchronize-with `work` writes because `work`
  returned an error and its partial writes are not observable through this
  primitive.

## Panicking-callback contract

If `work` panics or otherwise fails to return normally, subsequent behavior
of the `Once` is unspecified. This spec forbids the initializer from
panicking. Callers whose initializer can fail must use `callChecked` and
return an error from `work` instead of panicking.

Rationale: freestanding consumers do not have a portable
`panic → poison → recover` machinery. Rather than owning a panic-poison
protocol in this spec, `Once` requires the caller to model recoverable
initializer failure as an error return.

Consumers on hosts with unwinding may layer their own poison discipline on
top by wrapping `Once` inside a type that catches panics via
`std.builtin.Panic` policy. That layer is not owned by this spec.

## Recursion contract

Invoking `call` or `callChecked` on the same `Once` from inside `work` is a
caller contract violation and produces unspecified behavior.

Under `stdx.core.debug.checksEnabled(.build_mode)`, on targets where
`builtin.single_threaded` is `false`, the primitive detects direct recursion
using a module-level `threadlocal` current-claim pointer:

```zig
threadlocal var current_claim: ?*const anyopaque = null;

fn checkNotRecursive(state: *const State) void {
    if (stdx.core.debug.checksEnabled(.build_mode)) {
        std.debug.assert(current_claim != state);
    }
}

fn enterClaim(state: *const State) void {
    if (stdx.core.debug.checksEnabled(.build_mode)) {
        current_claim = state;
    }
}

fn leaveClaim(state: *const State) void {
    if (stdx.core.debug.checksEnabled(.build_mode)) {
        if (current_claim == state) current_claim = null;
    }
}
```

The check has these limits:

- it runs only when `checksEnabled(.build_mode)` is `true` and
  `builtin.single_threaded` is `false`;
- it detects direct recursion from inside `work` on the same thread;
- it does not detect mutual recursion through two different `Once` instances;
- it does not run on targets where `builtin.single_threaded` is `true`;
- release builds compile the check out entirely, matching the `SafetyMode`
  convention in `docs/specs/core/debug.md`.

Recursion that escapes detection deadlocks in the wait path when the
backend blocks, or spins in `sync.spin.Backend` until an external observer
notices.

## Ordering contract

`Once.call` and `Once.callChecked` provide:

- acquire semantics on every state observation, including the fast-path
  short-circuit;
- release semantics on the `untouched → running` claim CAS;
- release semantics on the `running → done` publish CAS;
- release semantics on the `running → untouched` rollback CAS.

The primitive does not order accesses outside `work`'s own writes. Data
visibility for buffers, rings, or other structures published as part of
initialization must be established by `work` itself using appropriate
atomics or barriers on those structures.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `State.init` | never | never | O(1) | value type | none | infallible |
| `State.isDone` | never | never | O(1) | reader | acquire | infallible |
| `State.observe` | never | never | O(1) | reader | acquire | infallible |
| `State.changedSince` | never | never | O(1) | reader | acquire | infallible |
| `Once.init` | never | never | O(1) | single-owner | none | infallible |
| `Once.isDone` | never | never | O(1) | reader | acquire | infallible |
| `Once.call` | never | may wait via backend | O(1) + work + wait | many callers | acquire on observation, release on transitions | propagates `WaitError` |
| `Once.callChecked` | never | may wait via backend | O(1) + work + wait | many callers | as above; rollback is release | propagates `E` or `WaitError` |

`Once` is safe from any execution context including NMI when paired with
`sync.spin.Backend`. Other backends inherit the backend's own safety
contract.

## std.Io lane

`sync.Once(Backend)` serves both spec-queue lanes:

1. Composes inside a downstream `std.Io` backend that satisfies the shared
   wait/wake contract.
2. Serves freestanding consumers via `sync.Once(sync.spin.Backend)` where
   `std.Io` is unavailable.

## Examples

Spin-only one-shot init in a freestanding context:

```zig
const stdx = @import("stdx");

var page_tables_once = stdx.sync.Once(stdx.sync.spin.Backend).init(.{});
var page_tables: PageTables = undefined;

fn ensurePageTables() void {
    page_tables_once.call(
        void,
        struct {
            fn work(_: void) void {
                page_tables = buildInitialPageTables();
            }
        }.work,
        {},
    ) catch unreachable; // spin backend WaitError == error{}
}
```

Retry-on-error init against a fallible device probe:

```zig
var hpet_once = stdx.sync.Once(stdx.sync.spin.Backend).init(.{});
var hpet: Hpet = undefined;

fn ensureHpet() error{HpetUnavailable}!void {
    try hpet_once.callChecked(
        void,
        error{HpetUnavailable},
        struct {
            fn work(_: void) error{HpetUnavailable}!void {
                hpet = try Hpet.probe();
            }
        }.work,
        {},
    );
}
```

Passing typed context without a global:

```zig
const InitCtx = struct { base: usize, len: usize };

var region_once = stdx.sync.Once(stdx.sync.spin.Backend).init(.{});

fn ensureRegion(base: usize, len: usize) void {
    region_once.call(
        InitCtx,
        struct {
            fn work(ctx: InitCtx) void {
                registerRegion(ctx.base, ctx.len);
            }
        }.work,
        .{ .base = base, .len = len },
    ) catch unreachable;
}
```

## Testing

Compile-time tests MUST instantiate `Once` with `sync.spin.Backend`, reject invalid backend declarations, and verify that the public API does not expose mutable state. These tests prove backend-shape and encapsulation constraints.

Deterministic backend tests MUST use a controllable backend that records waits and wakes and can return a selected `WaitError`. Tests MUST verify one successful initializer invocation, fast-path completion after publication, unchanged propagation of initializer and backend errors, rollback to a claimable state after `callChecked` fails, and wake after rollback. These tests prove the state transitions, error propagation, and retry contract.

Lost-wakeup model tests MUST enumerate claimant publication or rollback before and after waiter registration. They MUST verify that `changedSince` detects every transition before registration and that `wakeAll` makes registered waiters return. A direct-recursion test MUST verify debug-mode detection where functional `threadlocal` storage is available.

Memory-ordering tests MUST write an initializer payload before publication and read it after each returning caller acquire-observes `done`. Every returning caller MUST observe the payload. This test proves publication ordering.

Stress tests MUST run concurrent `call` and `callChecked` callers with `sync.spin.Backend` and verify one successful publication, exactly one successful initializer invocation, and completion of all non-error callers. Cross-target compilation MUST include a non-x86 target. Stress tests exercise concurrent progress; the model tests prove the waiter-transition protocol.
