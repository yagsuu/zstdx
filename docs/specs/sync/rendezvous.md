# Sync rendezvous

Status: Approved.

`stdx.sync.Rendezvous(Backend)` is a reusable N-way cyclic barrier. It gathers
a fixed number of parties per generation; when the last party arrives, the
generation advances, all waiters are released, and the primitive is armed
again for the next round.

## Owned scope

This spec owns:

- `sync.rendezvous.State`, the atomic remaining-count + generation word;
- `sync.rendezvous.Token`, an observed state/generation snapshot;
- `sync.Rendezvous(Backend)`, the wait-capable cyclic-barrier family;
- `sync.Rendezvous(Backend).Static(N)` and `sync.Rendezvous(Backend).Bounded`
  storage variants;
- `arrive`, `pending`, `capacity`, `generation`, and `stateRef` semantics;
- backend requirements delegated to the shared wait/wake contract defined in
  `docs/specs/sync/spin.md`;
- lost-wakeup prevention via token comparison and backend recheck;
- allocation, waiting, concurrency, and ordering contracts;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- one-shot countdown latches (see `docs/specs/sync/latch.md`);
- reset, resize, or reconfiguration of the party count after `init`;
- `tryArrive`, `arriveAndDrop`, timed arrival, deadlines, cancellation, or
  interrupt policy;
- SMP bring-up, INIT/SIPI, per-AP stack allocation, scheduler parking, or
  priority-inheritance implementations;
- waiter lists, futex, kernel wait queue, or thread parking;
- heap allocation or dynamic waiter allocation;
- data visibility for buffers, rings, or other structures published across
  the rendezvous point (parties own their own release/acquire on those
  structures);
- root promotion of `sync.Rendezvous`.

A backend may provide scheduler-specific waiter behavior. That behavior is
explicit in the `Rendezvous(Backend)` type and is not owned by this spec.

## Public namespace

`Rendezvous` lives under `stdx.sync`; its backend-independent state substrate
lives under the `stdx.sync.rendezvous` submodule so the `Rendezvous(Backend)`
factory can keep its call syntax while backends name stable state/token
types:

```zig
stdx.sync.Rendezvous
stdx.sync.rendezvous.State
stdx.sync.rendezvous.Token
```

It is not root-promoted:

```zig
stdx.Rendezvous // not exported
```

Source ownership:

```text
src/sync.zig
src/sync/rendezvous.zig
test/sync/rendezvous_test.zig
```

`src/sync.zig` re-exports:

```zig
pub const rendezvous = @import("sync/rendezvous.zig");

pub const Rendezvous = rendezvous.Rendezvous;
```

`src/sync.zig` is a thin facade. It contains no logic beyond re-exporting
and aliasing.

## Approved API

```zig
pub const State = struct {
    word: std.atomic.Value(u64),

    pub fn init(capacity_parties: u32) State;
    pub fn observe(self: *const State) Token;
    pub fn changedSince(self: *const State, token: Token) bool;
    pub fn remaining(self: *const State) u32;
    pub fn generation(self: *const State) u32;
};

pub const Token = enum(u64) {
    _,

    pub fn remaining(self: Token) u32;
    pub fn generation(self: Token) u32;
};

pub fn Rendezvous(comptime Backend: type) type;
```

### `Rendezvous(Backend)` returned type

```zig
pub const Namespace = struct {
    pub const WaitError = Backend.WaitError;

    pub fn Static(comptime capacity_parties: usize) type;
    pub const Bounded = struct { ... };
};
```

### `Rendezvous(Backend).Static(N)` returned type

```zig
pub const Self = struct {
    state: State,
    backend: Backend,

    pub const party_capacity: usize = capacity_parties;
    pub const WaitError = Backend.WaitError;

    pub fn init(backend: Backend) Self;

    pub fn arrive(self: *Self) WaitError!void;
    pub fn pending(self: *const Self) u32;
    pub fn capacity(self: *const Self) u32;
    pub fn generation(self: *const Self) u32;
    pub fn stateRef(self: *const Self) *const State;
};
```

### `Rendezvous(Backend).Bounded` type

```zig
pub const Bounded = struct {
    capacity_parties: u32,
    state: State,
    backend: Backend,

    pub const WaitError = Backend.WaitError;

    pub fn init(capacity_parties: u32, backend: Backend) Bounded;

    pub fn arrive(self: *Bounded) WaitError!void;
    pub fn pending(self: *const Bounded) u32;
    pub fn capacity(self: *const Bounded) u32;
    pub fn generation(self: *const Bounded) u32;
    pub fn stateRef(self: *const Bounded) *const State;
};
```

`Static(0)` is a compile-time error, matching the `BitSet.Static(0)` rule in
`docs/specs/bits/bitset/static.md`. `Static(capacity_parties)` with
`capacity_parties > std.math.maxInt(u32)` is a compile-time error.
`Bounded.init(0, backend)` is a caller-contract violation and traps under
`stdx.core.debug.checksEnabled(.build_mode)`.

There is no `reset`, `resize`, `dropParty`, `tryArrive`, `arriveTimeout`,
`arriveUntil`, or `arriveAndWait` alias in this spec. `arrive` is the only
spelling for the combined "decrement remaining, wait if not last" operation;
the last arriver returns without entering the wait path.

## Backend interface

`Rendezvous(Backend)` requires `Backend` to satisfy the shared wait/wake
backend contract defined in `docs/specs/sync/spin.md`, specialized to
`sync.rendezvous.State` and `sync.rendezvous.Token`:

```zig
pub const WaitError = error{...};

pub fn wait(
    self: *Backend,
    state: *const stdx.sync.rendezvous.State,
    observed: stdx.sync.rendezvous.Token,
) WaitError!void;

pub fn wakeAll(self: *Backend, state: *const stdx.sync.rendezvous.State) void;
```

`WaitError` must be an explicit error set. `anyerror` is not approved. An
empty error set (`error{}`, as `sync.spin.Backend` uses) is legal; the
primitive-side `try` in `arrive` monomorphizes away for spin-only callers.

`Backend` is stored by value in the primitive. If backend state is large,
mutable, or shared elsewhere, callers should make `Backend` a pointer or
small handle type.

`Backend.wait` may block, sleep, park, yield, spin, or return spuriously
according to the backend's own contract. `arrive` loops on spurious returns
until the generation advances or a backend error is returned.

`Backend.wakeAll` is called by the last arriver of a generation after the
generation advance is release-published. It must wake every waiter that
could be blocked in `Backend.wait` for this rendezvous instance, or otherwise
make those waiters return according to the backend's contract.

The allocation, waiting, locking, interrupt, and scheduler behavior of
backend functions is backend-owned. The rendezvous layer adds no heap
allocation and no hidden global scheduler policy.

Spin-only callers instantiate `Rendezvous(sync.spin.Backend)`; there is no
`.Spin` alias, per rule 3 of the wait-capable naming convention in
`docs/planning/spec-queue.md`.

## State and token representation

`sync.rendezvous.State` contains one atomic `u64` word.

Conceptually:

```text
bits  0..31  remaining: u32   parties still expected in the current generation
bits 32..63  generation: u32  generation counter, wraps on overflow
```

`sync.rendezvous.Token` is a strong snapshot of that word.

`State.observe()` acquire-loads the current word and returns it as a token.

`State.changedSince(token)` acquire-loads the current word and compares the
generation field with `token.generation()`. It returns true when the current
generation differs from the token's generation.

`State.remaining()` acquire-loads the current word and returns the remaining
field. `State.generation()` acquire-loads and returns the generation field.

Generation wrap at `2^32` is outside the primitive's practical test envelope
and is a mathematical worst case only. Implementations use the full 32-bit
generation space to make wrap unreachable in ordinary operation.

## Construction

`State.init(capacity_parties)` returns a state with `remaining =
capacity_parties` and `generation = 0`. `capacity_parties` must be strictly
positive; passing zero is a caller-contract violation and traps under
`stdx.core.debug.checksEnabled(.build_mode)`.

`Rendezvous(Backend).Static(capacity_parties).init(backend)` returns a `Self`
with the state pre-armed for the first generation and the supplied backend
stored by value. `capacity_parties` is a comptime constant; `Static(0)` is a
compile-time error.

`Rendezvous(Backend).Bounded.init(capacity_parties, backend)` returns a
`Bounded` with the state pre-armed and the runtime `capacity_parties` stored
in the struct. `capacity_parties == 0` is a caller-contract violation.

`init` must complete before any concurrent use.

After initialization, copying a rendezvous is outside the primitive's
contract. Once any pointer to a rendezvous is shared with another execution
context, moving it is outside the primitive's contract.

## Arrival semantics

`arrive()` decrements the remaining counter for the current generation and,
when the caller is the last party of the generation, advances the generation
and wakes waiters. Every other caller waits until the generation advances.

Required algorithm shape:

```zig
pub fn arrive(self: *Self) WaitError!void {
    var my_generation: u32 = undefined;

    // Reservation loop: atomically decrement remaining, or roll the generation
    // when we are the last party.
    while (true) {
        const observed = self.state.observe();
        const rem = observed.remaining();
        const gen = observed.generation();
        my_generation = gen;

        const next_word: u64 = if (rem == 1)
            pack(self.capacityU32(), gen +% 1)
        else
            pack(rem - 1, gen);

        if (self.state.tryTransition(observed, next_word, .acq_rel, .acquire)) {
            if (rem == 1) {
                self.backend.wakeAll(&self.state);
                return;
            }
            break; // loser: proceed to wait loop
        }
        // CAS lost race; retry.
    }

    // Wait loop: block until the generation advances.
    while (true) {
        const token = self.state.observe();
        if (token.generation() != my_generation) return;
        try self.backend.wait(&self.state, token);
    }
}
```

Required behavior:

- exactly one arriver per generation observes `remaining == 1` on its
  successful CAS and is the "last arriver";
- the last arriver installs `remaining = capacity_parties` and `generation =
  observed.generation() +% 1` in one CAS, then calls
  `backend.wakeAll(&self.state)`;
- every non-last arriver waits until the observed generation differs from
  the generation it committed against;
- `arrive` never observes `remaining == 0`: the last arriver's CAS reinstalls
  the full capacity before publishing, and the primitive's construction sets
  `remaining = capacity_parties`;
- CAS retries are bounded by contention with peer arrivers, not by the party
  count;
- `WaitError` from the backend propagates unchanged; the caller has already
  committed its arrival CAS and the primitive does not roll it back;
- `arrive` does not allocate.

Static-only additional constraint: the `capacity_parties` argument passed to
`Static(N)` must satisfy `N > 0` and `N <= std.math.maxInt(u32)`. Bounded
enforces `capacity_parties > 0` at runtime under
`stdx.core.debug.checksEnabled(.build_mode)`.

## Lost-wakeup contract

`Backend.wait(state, observed)` must not park if the state changed after
`observed` was captured.

Correct backend shape:

1. register or enqueue the current waiter;
2. recheck `state.changedSince(observed)` after registration;
3. if changed, unregister/cancel the wait and return success;
4. otherwise park, block, yield, or spin according to backend policy;
5. return success after wake or spurious wake, or return a `WaitError`.

A backend that cannot perform the post-registration recheck is not valid for
`Rendezvous`.

## Concurrency contract

Any number of contexts may call `arrive` concurrently against the same
rendezvous. Exactly one arriver per generation wins the "last arriver" CAS.

`pending`, `capacity`, `generation`, `stateRef`, and `State.observe` /
`State.changedSince` / `State.remaining` / `State.generation` are
non-mutating and may be called concurrently with any other operation.

`init` must complete before any concurrent use.

The rendezvous does not distinguish parties by identity. Any thread of
execution may play the role of any party in any generation; there is no
per-thread affinity, no expected caller identity, and no per-party token.

`arrive` is not safe from NMI or nested-interrupt context. A preempted
arriver that has committed its CAS but not yet exited the wait loop can
stall the next generation's release. Callers with NMI requirements use
different primitives (e.g. a `sync.spin`-backed `AtomicCell` on a
generation counter, or `concurrent.mpsc.AtomicRing` when applicable).

## Ordering contract

`Rendezvous.arrive` provides:

- acquire semantics on every `State.observe` and on every CAS-failure reload;
- release semantics via `.acq_rel` on the successful CAS that installs the
  next state word, whether the transition is a plain decrement or a
  generation advance;
- acquire semantics on the wait-loop `State.observe` so that a returning
  waiter synchronizes-with the last arriver's generation advance.

The primitive does not order accesses outside its own state word. Data
visibility for buffers, rings, or other structures published across the
rendezvous point must be established by the participating parties using
appropriate atomics or barriers on those structures.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `State.init` | never | never | O(1) | value type | none | infallible |
| `State.observe` | never | never | O(1) | reader | acquire | infallible |
| `State.changedSince` | never | never | O(1) | reader | acquire | infallible |
| `State.remaining` | never | never | O(1) | reader | acquire | infallible |
| `State.generation` | never | never | O(1) | reader | acquire | infallible |
| `Static(N).init` | never | never | O(1) | single-owner | none | infallible |
| `Static(N).party_capacity` | never | never | comptime | comptime | none | infallible |
| `Bounded.init` | never | never | O(1) | single-owner | none | infallible |
| `arrive` last | never | backend `wakeAll` | O(1) + contention | many callers | acq_rel transition | infallible in primitive |
| `arrive` non-last | never | backend `wait` | O(1) + wait | many callers | acquire on observe | propagates `WaitError` |
| `pending` | never | never | O(1) | reader | acquire | infallible |
| `capacity` | never | never | O(1) | reader | none | infallible |
| `generation` | never | never | O(1) | reader | acquire | infallible |
| `stateRef` | never | never | O(1) | reader | none | infallible |

The rendezvous layer performs no heap allocation, I/O, MMIO, volatile access,
target probing, or hidden global scheduler access.

## Error behavior

`pending`, `capacity`, `generation`, `stateRef`, `State.observe`,
`State.changedSince`, `State.remaining`, and `State.generation` are
infallible.

`arrive` returns only `Backend.WaitError`. A backend error returned from the
wait loop leaves the state unchanged; the caller's arrival CAS has already
committed. Callers must treat a returned `WaitError` as "the wait did not
complete", not "the arrival was rolled back". The next arriver of the same
generation still observes the committed decrement.

Backend errors mean the backend-specific wait operation did not complete as
a normal wake. This spec does not assign meanings such as timeout,
interrupted, canceled, or unsupported; those belong to the backend error
set.

## Implementation constraints

Implementation must:

- store one atomic `u64` word in `sync.rendezvous.State`;
- pack `remaining` in the low 32 bits and `generation` in the high 32 bits;
- use a strong `Token` type rather than exposing raw `u64` tokens;
- keep `Rendezvous(Backend)` free of runtime vtables;
- validate backend declarations at compile time where practical;
- reserve `remaining` and install the next generation in one CAS on the
  last-arrival path, so no observer ever sees `remaining == 0`;
- call `wakeAll(&state)` only after the generation advance is release-
  published;
- loop in the wait path to tolerate spurious backend success returns;
- never allocate in the rendezvous layer;
- avoid hidden globals and target-specific waits in the rendezvous layer;
- compile-error `Static(0)` and any `Static(N)` with `N > u32max`;
- assert `capacity_parties > 0` in `Bounded.init` under
  `stdx.core.debug.checksEnabled(.build_mode)`.

## std.Io lane

`sync.Rendezvous(Backend)` serves both spec-queue lanes:

1. Composes inside a downstream `std.Io` backend that satisfies the shared
   wait/wake contract.
2. Serves freestanding consumers via `Rendezvous(sync.spin.Backend)` where
   `std.Io` is unavailable.

## Examples

Backend shape:

```zig
const WaitQueueBackend = struct {
    queue: *WaitQueue,

    pub const WaitError = error{Canceled};

    pub fn wait(
        self: *WaitQueueBackend,
        state: *const stdx.sync.rendezvous.State,
        observed: stdx.sync.rendezvous.Token,
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
        state: *const stdx.sync.rendezvous.State,
    ) void {
        self.queue.wakeAll(state);
    }
};
```

Spin-only rendezvous in a freestanding context:

```zig
const Rv = stdx.sync.Rendezvous(stdx.sync.spin.Backend).Static(4);
var rv = Rv.init(.{});

// Called from four different CPUs.
rv.arrive() catch unreachable; // spin backend WaitError == error{}
```

Bounded rendezvous with a scheduler backend:

```zig
const Rv = stdx.sync.Rendezvous(WaitQueueBackend).Bounded;
var rv = Rv.init(worker_count, .{ .queue = &queue });

// Every worker:
try rv.arrive();
```

## Required tests

Tests live in `test/sync/rendezvous_test.zig`.

Required unit tests:

- `@sizeOf(sync.rendezvous.State) == 8`;
- `Rendezvous(sync.spin.Backend).Static(0)` is rejected at compile time;
- `Rendezvous(sync.spin.Backend).Static(1)`: every `arrive` returns
  immediately; `generation` increments by one each time;
- `Static(N)` initial state: `pending() == N`, `capacity() == N`,
  `generation() == 0`;
- `Static(N)` non-last arriver observes `pending()` decrement and blocks in
  a mock backend that reports every `wait` invocation;
- `Static(N)` last arriver advances the generation, resets `pending()` to
  `N`, and invokes `wakeAll` with `&self.state`;
- cyclic reuse: `Static(N)` completes generation G, then a fresh set of N
  arrivals completes generation G+1 with identical semantics;
- `Bounded.init(N, backend)` mirrors `Static(N)` semantics for the same N;
- `Bounded.init(0, backend)` traps under
  `stdx.core.debug.checksEnabled(.build_mode)`;
- `Bounded` and `Static` support the same generation-advance behavior on
  repeat use;
- mock backend `WaitError` propagates through `arrive` unchanged and leaves
  the state committed (no rollback).

Required model tests:

- simulate arrivals and waiter observe/enqueue/recheck races;
- prove a last-arrival CAS between observe and backend registration is found
  by `State.changedSince`;
- prove a last arrival after backend registration wakes through
  `wakeAll(&state)`;
- prove that under contention on generation G, all non-last arrivers return
  synchronizes-with the last arriver's release publication.

Required stress tests:

- against `sync.spin.Backend`: `M` threads run `K` rounds each on a
  `Static(M)` and observe exactly `K` generation advances with no lost
  wake and no double-release;
- against `sync.spin.Backend`: `M` threads on `Bounded.init(M, ...)`
  produce identical behavior to the `Static(M)` case;
- non-x86 build compiles the module.

Required compile-only tests:

- `Rendezvous(sync.spin.Backend).Static(4)` and
  `Rendezvous(sync.spin.Backend).Bounded` instantiate against
  `sync.spin.Backend`;
- rejection of a backend without `wait` / `wakeAll` or with a non-explicit
  `WaitError`.

Stress tests demonstrate exercised behavior; the lost-wakeup contract and
generation-advance CAS invariant in this spec are the normative proof
obligations.

## Open questions

None.
