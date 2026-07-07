# Synchronization signal

Status: Approved.

`stdx.sync.Signal` is a manual-reset sticky notification primitive. It separates
notification state from scheduler, wait-queue, futex, or spin policy by using an
explicit compile-time backend for wait-capable signals.

## Owned scope

This spec owns:

- `sync.Signal.State`, the atomic sticky signal state;
- `sync.Signal.Token`, an observed state/generation snapshot;
- `sync.Signal.Manual(Backend)`, a wait-capable manual-reset signal family;
- `set`, `clear`, `isSet`, and `wait` semantics;
- the backend interface required by `wait` and `set`;
- lost-wakeup prevention via token comparison and backend recheck;
- allocation, waiting, concurrency, and ordering contracts;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- mutexes, semaphores, condition variables, barriers, latches, channels, or
  counted events;
- auto-reset events, pulse events, edge-only notifications, or one-shot
  completion objects;
- timeouts, deadlines, clocks, cancellation tokens, or interrupt policy;
- futex, kernel wait queue, scheduler, thread parking, preemption, or priority
  inheritance implementations;
- signal handler safety or POSIX signal semantics;
- data visibility for queues or rings paired with the signal;
- heap allocation or dynamic waiter allocation.

A backend may provide scheduler-specific behavior. That behavior is explicit in
the `Signal.Manual(Backend)` type and is not owned by this spec.

## Public namespace

`Signal` lives under `stdx.sync`:

```zig
stdx.sync.Signal
```

It is not root-promoted:

```zig
stdx.Signal // not exported
```

Source ownership:

```text
src/sync.zig
src/sync/signal.zig
test/sync/signal_test.zig
```

`src/sync.zig` re-exports:

```zig
pub const signal = @import("sync/signal.zig");

pub const Signal = signal.Signal;
```

`src/sync.zig` is a thin facade. It contains no logic beyond re-exporting and
aliasing.

## Approved API

```zig
pub const Signal = struct {
    pub const InitialState = enum {
        unset,
        set,
    };

    pub const Token = enum(usize) {
        _,

        pub fn isSet(self: Token) bool;
    };

    pub const State = struct {
        word: std.atomic.Value(usize),

        pub fn init(initial: InitialState) State;

        pub fn isSet(self: *const State) bool;
        pub fn observe(self: *const State) Token;
        pub fn changedSince(self: *const State, token: Token) bool;
    };

    pub fn Manual(comptime Backend: type) type;
};
```

### `Manual(Backend)` returned type

```zig
pub const Self = struct {
    state: Signal.State,
    backend: Backend,

    pub const WaitError = Backend.WaitError;

    pub fn init(initial: Signal.InitialState, backend: Backend) Self;

    pub fn isSet(self: *const Self) bool;
    pub fn set(self: *Self) void;
    pub fn clear(self: *Self) void;
    pub fn wait(self: *Self) WaitError!void;

    pub fn stateRef(self: *const Self) *const Signal.State;
};
```

There is no `reset` alias, no `notify` alias, no `pulse`, no `waitTimeout`, no
`waitUntil`, no `tryWait`, and no auto-reset variant in this spec.

`clear` is the only spelling for returning a manual signal to the unset state.
`set` is the only spelling for publishing the set state and waking waiters.

## Backend interface

`Signal.Manual(Backend)` requires `Backend` to satisfy the shared wait/wake
backend contract defined in `docs/specs/sync/spin.md`, specialized to
`Signal.State` and `Signal.Token`:

```zig
pub const WaitError = error{Canceled};

pub fn wait(
    self: *Backend,
    state: *const stdx.sync.Signal.State,
    observed: stdx.sync.Signal.Token,
) WaitError!void;

pub fn wakeAll(self: *Backend, state: *const stdx.sync.Signal.State) void;
```

The concrete `WaitError` members are backend-specific; `error{Canceled}` above
is illustrative. `WaitError` must be an explicit error set. `anyerror` is not
approved. `stdx.sync.spin.Backend` uses `error{}` and is the reference
spin-only backend.

`Backend` is stored by value in the signal. If backend state is large, mutable,
or shared elsewhere, callers should make `Backend` a pointer or small handle
type.

`Backend.wait` may block, sleep, park, yield, spin, or return spuriously
according to the backend's own contract. `Signal.wait` loops on spurious
success returns until the signal is observed set or a backend error is
returned.

`Backend.wakeAll` is called by `set` when the signal transitions from unset
to set. The signal passes `&self.state` so shared wait-queue, futex, or
scheduler backends can wake waiters for this signal instance. `wakeAll` must
wake every waiter that could be blocked in `Backend.wait` for this signal, or
otherwise make those waiters return according to the backend's contract.

The allocation, waiting, locking, interrupt, and scheduler behavior of backend
functions is backend-owned behavior. The signal layer adds no heap allocation and
no hidden global scheduler policy.

## State and token representation

`Signal.State` contains one atomic `usize` word.

Conceptually:

```text
bit 0      set flag: 0 = unset, 1 = set
bits 1..N  generation counter
```

`Signal.Token` is a strong snapshot of that word.

`Token.isSet()` returns whether the token's set bit is set.

`State.observe()` acquire-loads the current word and returns it as a token.

`State.changedSince(token)` acquire-loads the current word and compares it with
`token`. It returns true when any set/clear transition changed the word.

`State.isSet()` acquire-loads the current word and returns the set flag.

`set` and `clear` bump the generation when they change the set flag. Redundant
`set` while already set and redundant `clear` while already unset do not need to
bump the generation.

Generation wrap while a waiter holds an old token is outside the primitive's
practical test envelope. Implementations must use the full available `usize`
space except the set bit to make wrap unreachable in ordinary operation.

## Construction

`Signal.State.init(.unset)` returns unset state. `Signal.State.init(.set)` returns
set state.

`Signal.Manual(Backend).init(initial, backend)` returns a signal with the state
initialized and the backend value stored. It must complete before any concurrent
use.

After initialization, copying a wait-capable signal is outside the primitive's
contract. Once any pointer to a signal is shared with another execution context,
moving the signal is outside the primitive's contract.

## Set semantics

`set()` transitions the signal to set.

Required behavior:

- if the previous state was unset, atomically set the flag, bump the generation,
  and release-publish the transition;
- after a successful unset-to-set transition, call `backend.wakeAll(&self.state)`;
- if the previous state was already set, leave the word unchanged and do not need
  to call `wakeAll`;
- never clear the signal;
- never inspect queue or ring data.

`set()` is a doorbell. It does not prove any paired ring or queue item is
readable. The paired data structure owns its own acquire/release publication.

Producer pattern:

```zig
try ring.tryPushBack(item);
ready.set();
```

`ready.set()` occurs only after successful item publication.

## Clear semantics

`clear()` transitions the signal to unset.

Required behavior:

- if the previous state was set, atomically clear the flag, bump the generation,
  and release-publish the transition;
- if the previous state was already unset, leave the word unchanged;
- do not call `wakeAll`;
- do not wait.

For ring doorbells, the consumer clears only after draining currently published
items and must recheck the ring before waiting.

## Wait semantics

`wait()` returns success only after observing the signal set.

Required algorithm shape:

```zig
while (true) {
    const token = self.state.observe();
    if (token.isSet()) return;

    try self.backend.wait(&self.state, token);
}
```

`wait()`:

- returns immediately when the signal is already set;
- may call `Backend.wait` only after observing an unset token;
- propagates `Backend.WaitError` unchanged;
- does not clear the signal;
- tolerates spurious backend returns by looping;
- does not allocate in the signal layer.

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
`Signal.Manual`.

## Concurrency contract

Any number of producer contexts may call `set` concurrently.

Any number of contexts may call `isSet`, `State.observe`, and
`State.changedSince` concurrently.

`clear` may race with `set`; the last successful state transition determines the
current level. Consumers using a ring doorbell should keep clear ownership with
the single consumer to avoid policy races.

Any number of waiters may call `wait` if the backend supports multiple waiters.
Because the required backend operation is `wakeAll`, a set signal is manual-reset
and level-triggered for all current and future waiters.

If a backend supports only one waiter, that restriction must be part of the
backend's contract; using multiple waiters with such a backend is outside the
signal contract.

## Ordering contract

State observation uses acquire ordering. State transitions use release ordering.
Read-modify-write loops that both observe and publish state may use `.acq_rel`.

`set` release-publishes the signal transition before calling `wakeAll(&state)`.

`wait` acquire-observes the set state before returning success.

Signal ordering does not replace the paired data structure's ordering. For a
ring, the ring publishes item data and the signal wakes the consumer to recheck.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `State.init` | never | never | O(1) | none | exclusive construction | initializes word |
| `State.observe` | never | never | O(1) | none | any caller | acquire snapshot |
| `State.changedSince` | never | never | O(1) | none | any caller | acquire compare |
| `Manual` | never | never | comptime | none | type factory | validates backend shape |
| `Manual.init` | never | never | O(1) | old state | exclusive construction | initializes state/backend |
| `isSet` | never | never | O(1) | none | any caller | acquire load |
| `set` transition | signal layer never | backend wake | O(1) plus backend | waiters woken | multi-producer | release transition |
| `set` already set | never | never | O(1) | none | multi-producer | acquire/release or acquire check |
| `clear` transition | never | never | O(1) | none | caller-coordinated | release transition |
| `clear` already unset | never | never | O(1) | none | caller-coordinated | acquire/release or acquire check |
| `wait` already set | never | never | O(1) | none | backend-defined waiters | acquire set |
| `wait` unset | signal layer never | backend wait | backend-defined | none | backend-defined waiters | token recheck |

The signal layer performs no heap allocation, I/O, MMIO, volatile access, target
probing, or hidden global scheduler access.

## Error behavior

`set`, `clear`, `isSet`, `State.observe`, and `State.changedSince` are infallible.

`wait` returns only `Backend.WaitError`. Backend errors leave the signal state
unchanged.

Backend errors mean the backend-specific wait operation did not complete as a
normal wake. The signal spec does not assign meanings such as timeout,
interrupted, canceled, or unsupported; those belong to the backend error set.

## Implementation constraints

Implementation must:

- store one atomic word in `Signal.State`;
- use a strong `Token` type rather than exposing raw `usize` tokens;
- keep `Signal.Manual(Backend)` free of runtime vtables;
- validate backend declarations at compile time where practical;
- call `wakeAll(&state)` only after the signal is release-published set;
- loop in `wait` to tolerate spurious backend success returns;
- never call backend code from `clear`;
- never allocate in the signal layer;
- avoid hidden globals and target-specific waits in the signal layer.

## Required tests

Required unit tests:

1. `.unset` initializes unset;
2. `.set` initializes set;
3. `set` changes unset to set;
4. redundant `set` remains set;
5. `clear` changes set to unset;
6. redundant `clear` remains unset;
7. `observe` tokens report set state correctly;
8. `changedSince` detects set and clear transitions;
9. `wait` returns immediately when already set without calling backend wait;
10. `wait` calls backend wait with an unset token;
11. `wait` loops after a spurious backend success return while still unset;
12. `wait` propagates backend errors unchanged;
13. `set` calls `wakeAll` with the signal state on unset-to-set transition;
14. redundant `set` does not require `wakeAll`.

Required model tests:

1. simulate waiter observe/enqueue/recheck races;
2. prove a set between observe and backend registration is found by
   `changedSince`;
3. prove a set after backend registration wakes through `wakeAll(&state)`;
4. prove clear-then-recheck doorbell protocol does not lose a ring wake.

Required stress tests:

1. multiple producer threads call `set` while one or more waiters call `wait`;
2. waiters do not remain parked after a set transition when the backend contract
   is satisfied;
3. spurious backend wakes do not produce false successful waits while unset.

Stress tests demonstrate exercised behavior; the lost-wakeup contract in this
spec is the normative proof obligation.

## Examples

Backend shape:

```zig
const WaitQueueBackend = struct {
    queue: *WaitQueue,

    pub const WaitError = error{ Canceled };

    pub fn wait(
        self: *WaitQueueBackend,
        state: *const stdx.sync.Signal.State,
        observed: stdx.sync.Signal.Token,
    ) WaitError!void {
        self.queue.enqueueCurrent();
        if (state.changedSince(observed)) {
            self.queue.cancelCurrent();
            return;
        }
        try self.queue.parkCurrent();
    }

    pub fn wakeAll(self: *WaitQueueBackend, state: *const stdx.sync.Signal.State) void {
        self.queue.wakeAll(state);
    }
};
```

Signal usage:

```zig
const Ready = stdx.sync.Signal.Manual(WaitQueueBackend);

var ready = Ready.init(.unset, .{ .queue = &queue });

try ring.tryPushBack(item);
ready.set();
```

## Open questions

None.
