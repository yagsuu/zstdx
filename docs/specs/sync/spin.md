# Sync spin backend

Status: Approved.

`stdx.sync.spin.Backend` is the zero-state wait/wake backend that pairs with
every wait-capable primitive in `stdx.sync` and `stdx.concurrent` when the
caller wants spin-only behavior. It is the canonical minimal implementation of
the shared wait/wake backend contract; other backends (scheduler-parking,
futex-backed, timeout-aware) match the same shape.

`sync.spin.Backend` exists because every wait-capable primitive would otherwise
invent its own spin variant. Fixing the seam here means every consuming spec
inherits spin-only composition for free.

## Owned scope

This spec owns:

- the `stdx.sync.spin` submodule;
- `sync.spin.Backend`, a zero-sized struct satisfying the shared wait/wake
  backend contract;
- `sync.spin.Backend.WaitError`, an empty error set;
- the shared wait/wake backend contract used by `Signal.Manual`, `Once`,
  `Barrier`, and every future wait-capable primitive under `stdx.sync` and
  `stdx.concurrent`;
- allocation, waiting, concurrency, and ordering contracts;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- spinlocks (`sync.RawSpinLock`, `sync.TicketLock`, `sync.SpinLock`);
- backoff or PAUSE policy beyond `std.atomic.spinLoopHint`;
- deadlines, timeouts, cancellation, or interrupt policy;
- IRQ save/restore (no `cli`/`sti`); the caller owns interrupt state;
- metrics, observability, or telemetry hooks;
- alternative backends (`sync.futex.Backend`, `sync.io.Backend`, etc.);
- root promotion of `sync.spin`.

## Public namespace

`sync.spin` lives under `stdx.sync`:

```zig
stdx.sync.spin
stdx.sync.spin.Backend
```

It is not root-promoted:

```zig
stdx.spin        // not exported
stdx.Backend     // not exported
```

Source ownership:

```text
src/sync.zig
src/sync/spin.zig
test/sync/spin_test.zig
```

`src/sync.zig` re-exports:

```zig
pub const spin = @import("sync/spin.zig");
```

`src/sync.zig` is a thin facade. It contains no logic beyond re-exporting.

## Shared wait/wake backend contract

Every wait-capable primitive in `stdx.sync` and `stdx.concurrent` that composes
a caller-supplied backend expects the backend to satisfy this contract:

```zig
pub const WaitError: type = /* backend-owned; empty is legal */;

pub fn wait(
    self: *Backend,
    state: *const State,   // primitive-specific type
    observed: Token,       // primitive-specific type
) WaitError!void;

pub fn wakeAll(self: *Backend, state: *const State) void;
```

Each consuming primitive substitutes its own `State` and `Token` types
(`Signal.State`/`Signal.Token`, `sync.once.State`/`sync.once.Token`, etc.) and validates
at factory instantiation that `backend.wait(state_ptr, observed)` and
`backend.wakeAll(state_ptr)` are callable. A backend may accept the concrete
primitive state/token types or more generic parameters such as
`*const anyopaque` / `anytype` when it does not inspect them.

`WaitError` must be an explicit error set. `anyerror` is not approved. An
empty error set (`error{}`) is legal; the primitive-side `try` monomorphizes
away when the concrete `WaitError` is empty.

`Backend` is stored by value inside the wait-capable primitive. Callers whose
backend state is large, mutable, or shared elsewhere pass a pointer type as
`Backend` (`*ParkingBackend`, `*FutexBackend`).

Semantic requirements on `Backend.wait`:

- may spin, yield, park, block, sleep, or return spuriously per the backend's
  own contract;
- must not park indefinitely if the primitive's state changed after `observed`
  was captured (the "lost-wakeup contract" documented per consuming
  primitive);
- must be safe to call any number of times per waiter.

Semantic requirements on `Backend.wakeAll`:

- called by the primitive after publishing a state transition that could
  unblock waiters for `state`;
- must wake every waiter currently blocked in `Backend.wait` for the same
  primitive instance identified by `state`, or otherwise make them return.

## Approved API

```zig
pub const Backend = struct {
    pub const WaitError = error{};

    pub fn wait(
        self: *Backend,
        state: *const anyopaque,
        observed: anytype,
    ) WaitError!void;

    pub fn wakeAll(self: *Backend, state: *const anyopaque) void;
};
```

Implementation shape:

```zig
const std = @import("std");

pub const Backend = struct {
    pub const WaitError = error{};

    pub fn wait(
        self: *Backend,
        state: *const anyopaque,
        observed: anytype,
    ) WaitError!void {
        _ = self;
        _ = state;
        _ = observed;
        std.atomic.spinLoopHint();
    }

    pub fn wakeAll(self: *Backend, state: *const anyopaque) void {
        _ = self;
        _ = state;
    }
};
```

## Semantics

`Backend` is a zero-sized struct. `@sizeOf(Backend) == 0`. Any two `Backend`
values are interchangeable.

`Backend{}` is the sole constructor. There is no `init` and no module-level
singleton; callers instantiate `sync.spin.Backend{}` at the call site or store
it inside a wait-capable primitive by value.

`wait` accepts any `state` pointer and any `observed` value. `wakeAll` accepts
any `state` pointer. The parameters are ignored by design so that
`sync.spin.Backend` satisfies every consuming primitive's compile-time
callability check without knowing the primitive's `State` and `Token` types.
`wait` executes one `std.atomic.spinLoopHint()` and returns. The consuming
primitive's algorithm supplies the outer loop; `wait` returning is not a wake
signal.

`std.atomic.spinLoopHint()` compiles to `pause` on x86_64, `yield` on aarch64,
and target-appropriate hints elsewhere. It performs no memory access, no
allocation, and no syscall. It is safe from any execution context including
NMI.

`wakeAll` is a no-op. Nothing is blocked on `Backend.wait` that requires
waking; the caller's next `wait` iteration observes the primitive state on
its own recheck.

## Instantiation with consuming primitives

Callers write:

```zig
var once: stdx.sync.Once(stdx.sync.spin.Backend) =
    .init(stdx.sync.spin.Backend{});

var signal: stdx.sync.Signal.Manual(stdx.sync.spin.Backend) =
    .init(.unset, stdx.sync.spin.Backend{});
```

When `Signal.Manual` instantiates against `sync.spin.Backend`, the compile-
time check that `backend.wait(state, token)` type-checks succeeds because
`*const Signal.State` coerces to `*const anyopaque` and `anytype` accepts
`Signal.Token`. The same reasoning applies to every future consuming
primitive.

Consuming specs cite this spec for the backend contract and add their own
`State` / `Token` / `WaitError` requirements.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `Backend{}` | never | never | O(1) | value type | none | infallible |
| `Backend.wait` | never | one `spinLoopHint` | O(1) | reentrant | none | infallible (`error{}`) |
| `Backend.wakeAll` | never | never | O(1) | reentrant | none | infallible |

`Backend` is safe from any execution context including NMI. It performs no
memory access to its parameters, no allocation, no syscall, no lock, and no
target probing.

## std.Io lane

`sync.spin.Backend` serves lane 2 exclusively: freestanding consumers where
`std.Io` is unavailable — kernel init, hypervisor setup, firmware pre-runtime,
controller polling loops, interrupt handlers. Lane-1 composition inside a
`std.Io` backend requires a different backend that yields to the scheduler;
that backend is a separate spec.

## Required tests

Tests live in `test/sync/spin_test.zig`.

Required tests:

- `@sizeOf(sync.spin.Backend) == 0`;
- `sync.spin.Backend.WaitError` equals `error{}` (checked via `@typeInfo`);
- `sync.spin.Backend{}.wait(&dummy_state, dummy_observed)` returns without
  error, exercised against a `dummy_state` of arbitrary pointee type and a
  `dummy_observed` of arbitrary value type;
- `sync.spin.Backend{}.wakeAll(&dummy_state)` returns;
- compile-only instantiation of `Signal.Manual(sync.spin.Backend)` and every
  other approved wait-capable primitive against `sync.spin.Backend`; a build
  failure of any of those instantiations is a spec violation of the failing
  primitive, not this spec;
- the `sync.spin` module compiles on every supported target, including
  non-x86 targets, with no target-specific asm emission beyond what
  `std.atomic.spinLoopHint` itself emits.

## Open questions

None.
