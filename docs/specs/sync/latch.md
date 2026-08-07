# Sync latch

Status: Approved.

`stdx.sync.Latch(Backend)` is a one-shot countdown latch. It gates any number
of waiters on a fixed number of arrivals; once the remaining count reaches
zero the latch is released, sticky, and every current and future waiter
returns without blocking.

## Owned scope

This spec owns:

- `sync.latch.State`, the atomic remaining-count word;
- `sync.latch.Token`, an observed state snapshot;
- `sync.Latch(Backend)`, the wait-capable one-shot countdown-latch family;
- `sync.Latch(Backend).Static(N)` and `sync.Latch(Backend).Bounded` storage
  variants;
- `arrive`, `wait`, `pending`, `capacity`, and `isReleased` semantics;
- backend requirements delegated to the shared wait/wake contract defined in
  `docs/specs/sync/spin.md`;
- lost-wakeup prevention via token comparison and backend recheck;
- allocation, waiting, concurrency, and ordering contracts;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- reusable cyclic barriers (see `docs/specs/sync/rendezvous.md`);
- one-shot init with a return-of-writes contract (see
  `docs/specs/sync/once.md`);
- `reset`, `rearm`, `resize`, `arriveAndWait`, `tryArrive`, `tryWait`,
  timed arrival, deadlines, cancellation, or interrupt policy;
- negative or additive counter updates (`add(delta)` in
  `sync.WaitGroup`-style APIs);
- per-arrival identity, per-party tokens, or arriver-to-waiter affinity;
- scheduler parking, priority-inheritance, futex, or kernel wait queues;
- heap allocation or dynamic waiter allocation;
- data visibility for buffers, rings, or other structures published across
  the latch (arrivers own their own release/acquire on those structures);

A backend may provide scheduler-specific waiter behavior. That behavior is
explicit in the `Latch(Backend)` type and is not owned by this spec.

## Public namespace

`Latch` lives under `stdx.sync`; its backend-independent state substrate
lives under the `stdx.sync.latch` submodule so the `Latch(Backend)` factory
can keep its call syntax while backends name stable state/token types:

```zig
stdx.sync.Latch
stdx.sync.latch.State
stdx.sync.latch.Token
```

Source ownership:

```text
src/sync.zig
src/sync/latch.zig
test/sync/latch_test.zig
```

`src/sync.zig` re-exports:

```zig
pub const latch = @import("sync/latch.zig");

pub const Latch = latch.Latch;
```

`src/sync.zig` is a thin facade. It contains no logic beyond re-exporting
and aliasing.

## API

```zig
pub const State = struct {
    word: std.atomic.Value(u32),

    pub fn init(capacity: u32) State;
    pub fn observe(self: *const State) Token;
    pub fn changedSince(self: *const State, token: Token) bool;
    pub fn remaining(self: *const State) u32;
    pub fn isReleased(self: *const State) bool;
};

pub const Token = enum(u32) {
    _,

    pub fn remaining(self: Token) u32;
    pub fn isReleased(self: Token) bool;
};

pub fn Latch(comptime Backend: type) type;
```

### `Latch(Backend)` returned type

```zig
pub const Namespace = struct {
    pub const WaitError = Backend.WaitError;

    pub fn Static(comptime capacity: usize) type;
    pub const Bounded = struct { ... };
};
```

### `Latch(Backend).Static(N)` returned type

```zig
pub const Self = struct {
    state: State,
    backend: Backend,

    pub const arrival_capacity: usize = capacity;
    pub const WaitError = Backend.WaitError;

    pub fn init(backend: Backend) Self;

    pub fn arrive(self: *Self) void;
    pub fn wait(self: *Self) WaitError!void;
    pub fn pending(self: *const Self) u32;
    pub fn capacity(self: *const Self) u32;
    pub fn isReleased(self: *const Self) bool;
};
```

### `Latch(Backend).Bounded` type

```zig
pub const Bounded = struct {
    arrival_capacity: u32,
    state: State,
    backend: Backend,

    pub const WaitError = Backend.WaitError;

    pub fn init(capacity: u32, backend: Backend) Bounded;

    pub fn arrive(self: *Bounded) void;
    pub fn wait(self: *Bounded) WaitError!void;
    pub fn pending(self: *const Bounded) u32;
    pub fn capacity(self: *const Bounded) u32;
    pub fn isReleased(self: *const Bounded) bool;
};
```

`State` and `Token` support `Backend` implementations. Normal callers use
`Static` or `Bounded` operations.

`Static(0)` is a compile-time error, matching the `BitSet.Static(0)` rule in
`docs/specs/bits/set/static.md` and the `Rendezvous.Static(0)` rule in
`docs/specs/sync/rendezvous.md`. `Static(capacity)` with
`capacity > std.math.maxInt(u32)` is a compile-time error.
`Bounded.init(0, backend)` is a caller-contract violation and traps under
`stdx.core.debug.checksEnabled(.build_mode)`.

There is no `reset`, `rearm`, `resize`, `arriveAndWait`, `tryArrive`,
`tryWait`, `arriveTimeout`, or `waitUntil` alias in this spec. `arrive` is
the only spelling for the "decrement remaining, wake waiters if last" step;
`wait` is the only spelling for the "block until released" step. Waiters
never decrement the counter; arrivers never enter the backend wait path.

## Backend interface

`Latch(Backend)` requires `Backend` to satisfy the shared wait/wake backend
contract defined in `docs/specs/sync/spin.md`, specialized to
`sync.latch.State` and `sync.latch.Token`:

```zig
pub const WaitError = error{...};

pub fn wait(
    self: *Backend,
    state: *const stdx.sync.latch.State,
    observed: stdx.sync.latch.Token,
) WaitError!void;

pub fn wakeAll(self: *Backend, state: *const stdx.sync.latch.State) void;
```

`WaitError` must be an explicit error set. `anyerror` is not approved. An
empty error set (`error{}`, as `sync.spin.Backend` uses) is legal; the
primitive-side `try` in `wait` monomorphizes away for spin-only callers.

`Backend` is stored by value in the primitive. If backend state is large,
mutable, or shared elsewhere, callers should make `Backend` a pointer or
small handle type.

`Backend.wait` may block, sleep, park, yield, spin, or return spuriously
according to the backend's own contract. `Latch.wait` loops on spurious
returns until the state is observed released or a backend error is
returned.

`Backend.wakeAll` is called by the last arriver after the release
transition is release-published. It must wake every waiter that could be
blocked in `Backend.wait` for this latch instance, or otherwise make those
waiters return according to the backend's contract.

The allocation, waiting, locking, interrupt, and scheduler behavior of
backend functions is backend-owned. The latch layer adds no heap allocation
and no hidden global scheduler policy.

Spin-only callers MUST instantiate `Latch(sync.spin.Backend)`. This API has no `.Spin` alias.

## State and token representation

`sync.latch.State` contains one atomic `u32` word holding the remaining
arrival count. `remaining == 0` is the released state and is sticky: once
observed, the word never transitions back to a non-zero value.

`sync.latch.Token` is a strong snapshot of that word.

`State.observe()` acquire-loads the current word and returns it as a token.

`State.changedSince(token)` acquire-loads the current word and compares it
with the token. It returns true when the current word differs from the
snapshot.

`State.remaining()` acquire-loads and returns the remaining count.
`State.isReleased()` acquire-loads and returns whether the remaining count
equals zero. `Token.remaining()` and `Token.isReleased()` read the same
fields out of the snapshot without an atomic load.

The state word carries no generation counter. The latch never transitions
out of the released state.

## Construction

`State.init(capacity)` returns a state with `remaining = capacity`.
`capacity` must be strictly positive; passing zero is a caller-contract
violation and traps under `stdx.core.debug.checksEnabled(.build_mode)`.

`Latch(Backend).Static(capacity).init(backend)` returns a `Self` with the
state pre-armed to `remaining = capacity` and the supplied backend stored
by value. `capacity` is a comptime constant; `Static(0)` is a compile-time
error.

`Latch(Backend).Bounded.init(capacity, backend)` returns a `Bounded` with
the state pre-armed to `remaining = capacity` and the runtime `capacity`
stored in the struct. `capacity == 0` is a caller-contract violation and
traps under `checksEnabled(.build_mode)`.

`init` must complete before any concurrent use.

After initialization, copying a latch is outside the primitive's contract.
Once any pointer to a latch is shared with another execution context,
moving it is outside the primitive's contract.

## Arrival semantics

`arrive()` decrements the remaining counter and, when the caller is the
last arriver, calls `Backend.wakeAll(&self.state)`. `arrive` never blocks.

Required algorithm shape:

```zig
pub fn arrive(self: *Self) void {
    while (true) {
        const observed = self.state.observe();
        const rem = observed.remaining();

        if (rem == 0) {
            // Over-arrival: caller-contract violation. Trap under
            // checksEnabled; saturate at zero in release without wrap and
            // without a second wakeAll.
            if (stdx.core.debug.checksEnabled(.build_mode)) unreachable;
            return;
        }

        if (self.state.tryTransition(observed, rem - 1, .acq_rel, .acquire)) {
            if (rem == 1) self.backend.wakeAll(&self.state);
            return;
        }
        // CAS lost race; retry.
    }
}
```

Required behavior:

- exactly one arriver observes `remaining == 1` on its successful CAS and
  is the "last arriver";
- the last arriver's release-published store installs `remaining = 0` and
  then calls `backend.wakeAll(&self.state)` exactly once;
- non-last arrivers return immediately after their successful CAS without
  entering the backend wait path;
- CAS retries are bounded by contention with peer arrivers, not by the
  arrival count;
- over-arrival (calling `arrive` after `remaining == 0`) is a caller-
  contract violation and traps under
  `stdx.core.debug.checksEnabled(.build_mode)`; in release builds the
  primitive saturates at zero, does not wrap, and does not invoke
  `wakeAll` a second time;
- `arrive` does not allocate.

Static-only additional constraint: the `capacity` argument passed to
`Static(N)` must satisfy `N > 0` and `N <= std.math.maxInt(u32)`. Bounded
enforces `capacity > 0` at runtime under
`stdx.core.debug.checksEnabled(.build_mode)`.

## Wait semantics

`wait()` blocks until the latch is released and then returns.

Required algorithm shape:

```zig
pub fn wait(self: *Self) WaitError!void {
    // Fast path.
    if (self.state.isReleased()) return;

    // Wait loop: block until released.
    while (true) {
        const token = self.state.observe();
        if (token.isReleased()) return;
        try self.backend.wait(&self.state, token);
    }
}
```

Required behavior:

- if `state.isReleased()` on entry, return immediately without invoking the
  backend;
- otherwise loop over `Backend.wait` until `token.isReleased()` on a
  post-observe check;
- `wait` never mutates the counter;
- every returning waiter synchronizes-with the last arriver's release
  publication under acquire semantics on `State.observe`;
- `WaitError` from the backend propagates unchanged; the primitive does
  not retry a failed backend `wait` on the caller's behalf;
- once the latch is released, every subsequent `wait` returns on the fast
  path without invoking `Backend.wait`;
- `wait` does not allocate.

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
for `Latch`.

## Concurrency contract

Any number of contexts may call `arrive` concurrently against the same
latch. Any number of contexts may call `wait` concurrently against the
same latch. Arrivers and waiters may share the same context; the primitive
does not distinguish caller identity.

`pending`, `capacity`, `isReleased`, and `State.observe` /
`State.changedSince` / `State.remaining` / `State.isReleased` are
non-mutating and may be called concurrently with any other operation.

`init` must complete before any concurrent use.

`arrive` is not safe from NMI or nested-interrupt context; a preempted
arriver between the release-CAS and the `wakeAll` call stalls the release
publication. `wait` is not safe from NMI on backends that block. On
`sync.spin.Backend`, `wait` is a spin loop callable from NMI but stalls
indefinitely until a non-NMI-context arriver completes the countdown.
Callers requiring NMI safety MUST use different primitives.

## Ordering contract

`Latch` provides:

- acquire semantics on every `State.observe` and on every CAS-failure
  reload;
- release semantics via `.acq_rel` on the successful CAS that installs the
  next `remaining` value, whether the transition is a plain decrement or
  the final release to zero;
- acquire semantics on the wait-loop `State.observe` so that a returning
  waiter synchronizes-with the last arriver's release publication.

The primitive does not order accesses outside its own state word. Data
visibility for buffers, rings, or other structures published across the
latch must be established by the participating arrivers using appropriate
atomics or barriers on those structures.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `State.init` | never | never | O(1) | value type | none | infallible |
| `State.observe` | never | never | O(1) | reader | acquire | infallible |
| `State.changedSince` | never | never | O(1) | reader | acquire | infallible |
| `State.remaining` | never | never | O(1) | reader | acquire | infallible |
| `State.isReleased` | never | never | O(1) | reader | acquire | infallible |
| `Static(N).init` | never | never | O(1) | single-owner | none | infallible |
| `Static(N).arrival_capacity` | never | never | comptime | comptime | none | infallible |
| `Bounded.init` | never | never | O(1) | single-owner | none | infallible |
| `arrive` last | never | backend `wakeAll` | O(1) + contention | many callers | acq_rel transition | infallible |
| `arrive` non-last | never | never | O(1) + contention | many callers | acq_rel transition | infallible |
| `wait` pre-release | never | backend `wait` | O(1) + wait | many callers | acquire on observe | propagates `WaitError` |
| `wait` post-release | never | never | O(1) | many callers | acquire on observe | infallible in practice |
| `pending` | never | never | O(1) | reader | acquire | infallible |
| `capacity` | never | never | O(1) | reader | none | infallible |
| `isReleased` | never | never | O(1) | reader | acquire | infallible |

The latch layer performs no heap allocation, I/O, MMIO, volatile access,
target probing, or hidden global scheduler access.

## Error behavior

`arrive`, `pending`, `capacity`, `isReleased`, `State.observe`,
`State.changedSince`, `State.remaining`, and `State.isReleased` are
infallible.

`wait` returns only `Backend.WaitError`. A backend error returned from the
wait loop leaves the state unchanged; the primitive does not roll back or
retry. Callers must treat a returned `WaitError` as "the wait did not
complete", not "the latch reverted". The next `wait` on the same latch
still observes whatever state actually exists.

Backend errors indicate that the backend-specific wait operation did not
complete as a normal wake. Timeout, cancellation, and unsupported-operation
semantics belong to the backend error set.

## Implementation constraints

Implementation must:

- store one atomic `u32` word in `sync.latch.State`;
- use a strong `Token` type rather than exposing raw `u32` tokens;
- keep `Latch(Backend)` free of runtime vtables;
- at `Latch(Backend)` factory instantiation, require `Backend` to declare `WaitError`, `wait`, and `wakeAll`, and require `WaitError` to be an explicit error set;
- release-publish the final `remaining = 0` store before calling
  `wakeAll(&state)`, and call `wakeAll` exactly once on the last-arrival
  path;
- loop in the wait path to tolerate spurious backend success returns;
- never allocate in the latch layer;
- avoid hidden globals and target-specific waits in the latch layer;
- compile-error `Static(0)` and any `Static(N)` with `N > u32max`;
- assert `capacity > 0` in `Bounded.init` under
  `stdx.core.debug.checksEnabled(.build_mode)`;
- trap over-arrival under `stdx.core.debug.checksEnabled(.build_mode)` and
  saturate at zero in release without wrapping and without a second
  `wakeAll`.

## std.Io lane

`sync.Latch(Backend)` serves both spec-queue lanes:

1. Composes inside a downstream `std.Io` backend that satisfies the shared
   wait/wake contract.
2. Serves freestanding consumers via `Latch(sync.spin.Backend)` where
   `std.Io` is unavailable.

## Examples

Backend shape:

```zig
const WaitQueueBackend = struct {
    queue: *WaitQueue,

    pub const WaitError = error{Canceled};

    pub fn wait(
        self: *WaitQueueBackend,
        state: *const stdx.sync.latch.State,
        observed: stdx.sync.latch.Token,
    ) WaitError!void {
        self.queue.enqueueCurrent();
        if (state.changedSince(observed)) {
            self.queue.cancelCurrent();
            return;
        }
        try self.queue.parkCurrent();
    }

    pub fn wakeAll(
        self: *WaitQueueBackend,
        state: *const stdx.sync.latch.State,
    ) void {
        self.queue.wakeAll(state);
    }
};
```

Spin-only latch in a freestanding context:

```zig
const L = stdx.sync.Latch(stdx.sync.spin.Backend).Static(4);
var l = L.init(.{});

// Four different CPUs:
l.arrive();

// Any number of consumers:
l.wait() catch unreachable; // spin backend WaitError == error{}
```

Bounded latch with a scheduler backend:

```zig
const L = stdx.sync.Latch(WaitQueueBackend).Bounded;
var l = L.init(worker_count, .{ .queue = &queue });

// Every worker:
l.arrive();

// Any number of consumers:
try l.wait();
```

## Testing

Compile-time tests MUST reject `Static(0)` and invalid backend declarations, and MUST instantiate both storage variants with `sync.spin.Backend`. These tests prove the capacity and backend-shape contracts.

Deterministic backend tests MUST use a controllable backend that records waits and wakes and can return a selected `WaitError`. Tests MUST verify construction boundaries, non-final and final arrival transitions, one final `wakeAll`, post-release fast-path waiting, over-arrival behavior, `Bounded` equivalence with `Static`, and unchanged error propagation. These tests prove the sticky-release state machine, error behavior, and wake rule.

Lost-wakeup model tests MUST enumerate arrival, waiter observation, waiter registration, and recheck interleavings. They MUST verify that a final arrival before registration is detected by `changedSince` and that a final arrival after registration wakes the waiter.

Memory-ordering tests MUST publish a payload before the last arrival and read it after a waiter acquire-observes release. The waiter MUST observe the payload. This test proves the final-arrival release/acquire edge.

Stress tests MUST run multiple arrivers and waiters against both storage variants with `sync.spin.Backend`, verify that each waiter returns once after the final arrival, and verify that no over-arrival or duplicate final wake occurs. Cross-target compilation MUST include a non-x86 target. Stress tests exercise progress; the model tests prove the lost-wakeup protocol.
