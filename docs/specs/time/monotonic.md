# Time monotonic clock

Status: Approved.

`stdx.time.Instant` and `stdx.time.Duration` are strong nanosecond-domain value
types. `stdx.time.Clock.Monotonic(Backend)` is a caller-composed wrapper that
enforces the monotonic-reader contract on top of a caller-supplied backend.

Together they give polling protocols (device init handshakes, completion
timeouts, retry loops) one vocabulary. The wrapper enforces the monotonic
contract on `now` and forwards a backend-supplied `sleep` verbatim when
present. Both methods reduce to a direct backend call in release builds.

## Owned scope

This spec owns:

- `stdx.time.Instant` (`enum(u64) { _ }`, monotonic nanoseconds);
- `stdx.time.Duration` (`enum(i64) { _ }`, signed nanoseconds);
- `stdx.time.Clock.Monotonic(Backend)` wrapper;
- backend interface required by `Clock.Monotonic`, including the optional
  `sleep` capability method that `Clock.Monotonic` forwards verbatim when the
  backend exposes it;
- debug-only monotonicity assertion gated by `core.debug.checksEnabled`;
- debug-only non-negative-delta assertion on the forwarded `sleep`, gated by
  `core.debug.checksEnabled`;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- `time.Deadline` composites;
- `time.Backoff` or `time.RetryPolicy`;
- wallclock or system-time variants (`Clock.System`, `Clock.Wall`,
  `Clock.CoarseMonotonic`);
- scheduler policy, cancellation semantics, drift correction, or leap-second
  policy — `Clock.Monotonic` forwards a backend-provided `sleep` verbatim and
  adds no scheduler, cancellation, or dispatch behavior of its own;
- duration formatting, parsing, or unit-string helpers;
- picosecond, sub-nanosecond, or `u128` domains;
- concrete backend implementations (HPET, TSC, APIC, PIT, `clock_gettime`,
  synthetic test clocks);
- backend construction, initialization failure, or feature detection;
- global default clocks;
- root exports.

## Public namespace

Time primitives live under `stdx.time`:

```zig
stdx.time.Instant
stdx.time.Duration
stdx.time.Clock
stdx.time.Clock.Monotonic
```

They are not root-promoted:

```zig
stdx.Instant // not exported
stdx.Duration // not exported
stdx.Clock // not exported
```

Source ownership:

```text
src/time.zig
src/time/monotonic.zig
test/time/monotonic_test.zig
```

`src/time.zig`:

```zig
//! Time primitives. Spec: docs/specs/time/monotonic.md.

pub const monotonic = @import("time/monotonic.zig");

pub const Instant = monotonic.Instant;
pub const Duration = monotonic.Duration;
pub const Clock = monotonic.Clock;
```

`src/time.zig` is a thin facade. It contains no logic beyond re-exporting and
aliasing.

## Approved API

```zig
pub const Instant = enum(u64) {
    _,

    pub const Raw = u64;
    pub const Error = error{ Overflow };

    pub fn fromNanos(ns: u64) Instant;
    pub fn nanos(self: Instant) u64;

    pub fn zero() Instant;

    pub fn add(self: Instant, delta: Duration) Error!Instant;
    pub fn since(self: Instant, base: Instant) Duration;
    pub fn afterOrEq(self: Instant, other: Instant) bool;
};

pub const Duration = enum(i64) {
    _,

    pub const Raw = i64;
    pub const Error = error{ Overflow };

    pub const zero: Duration = @enumFromInt(0);

    pub fn fromNanos(ns: i64) Duration;
    pub fn nanos(self: Duration) i64;

    pub fn fromMicros(us: i64) Error!Duration;
    pub fn fromMillis(ms: i64) Error!Duration;
    pub fn fromSeconds(s: i64) Error!Duration;

    pub fn isPositive(self: Duration) bool;
    pub fn isNegative(self: Duration) bool;
};

pub const Clock = struct {
    pub fn Monotonic(comptime Backend: type) type;
};
```

### `Clock.Monotonic(Backend)` returned type

```zig
pub const Self = struct {
    backend: Backend,
    last: if (stdx.core.debug.checksEnabled) Instant else void,

    pub fn init(backend: Backend) Self;
    pub fn now(self: *Self) Instant;

    // Generated iff `Backend` exposes `sleep`.
    pub fn sleep(self: *Self, delta: Duration) void;
};
```

Backend contract:

```zig
pub fn now(self: *Backend) stdx.time.Instant;

// Optional capability method; when present, `Clock.Monotonic(Backend)`
// generates a forwarding `sleep` method with the same signature.
pub fn sleep(self: *Backend, delta: stdx.time.Duration) void;
```

`Backend` is stored by value inside `Clock.Monotonic(Backend)`. Callers whose
backend state is large, mutable, or shared elsewhere pass a pointer type as
`Backend` (`*HpetClock`, `*PosixClock`).

The `Backend.now` signature is verified at compile time when
`Clock.Monotonic(Backend)` is instantiated. `anyerror` and error-union return
types are rejected.

## `Instant` semantics

`Instant` is a monotonic point-in-time value with `u64` nanoseconds of range.
The domain covers approximately 584 years relative to the backend's epoch.

`Instant.fromNanos(ns)` is infallible. Every `u64` value is a valid `Instant`.

`Instant.nanos()` returns the backing `u64` value.

`Instant.zero()` returns `fromNanos(0)`. The epoch semantics of "zero" are
backend-defined; consumers use it only as a sentinel or as an initializer for
uninitialized state.

`Instant.add(delta)` returns `self.nanos() + delta.nanos()` as an `Instant`.
Because `delta` is signed, `add` performs a checked signed addition against
the unsigned `Instant` domain:

- returns `error.Overflow` when the result would exceed `maxInt(u64)`;
- returns `error.Overflow` when the result would go below `0`.

`Instant.since(base)` returns `self.nanos() - base.nanos()` as a signed
`Duration`. It is infallible. The returned duration is negative when
`self < base`, zero when equal, positive when `self > base`. The `i64` domain
covers `±292` years of separation; callers whose consumers can exceed that
range are outside the primitive's contract.

`Instant.afterOrEq(other)` returns `self.nanos() >= other.nanos()`. It is the
supported ordering predicate for deadline checks:

```zig
if (clock.now().afterOrEq(deadline)) return error.Timeout;
```

Equality uses native enum equality:

```zig
if (a == b) { ... }
```

This spec intentionally does not add `.lessThan` or `.compare` methods.
Ordering is done at the call site via `afterOrEq` or by comparing raw values.

Cross-clock comparison is a caller contract violation. `Instant` is not
tag-parameterized; a program that mixes two `Clock.Monotonic` instances with
different epochs is expected to keep them straight itself.

## `Duration` semantics

`Duration` is a signed nanosecond difference. Negative durations model "before"
relationships (`later.since(earlier)` positive, `earlier.since(later)` negative).

`Duration.fromNanos(ns)` is infallible. Every `i64` value is a valid duration.

`Duration.nanos()` returns the backing `i64`.

`Duration.zero` is the constant `Duration` with value `0`.

`Duration.fromMicros(us)` returns `us * 1_000` as a `Duration`. It returns
`error.Overflow` when the multiplication would overflow `i64`.

`Duration.fromMillis(ms)` returns `ms * 1_000_000` as a `Duration`. It returns
`error.Overflow` when the multiplication would overflow `i64`.

`Duration.fromSeconds(s)` returns `s * 1_000_000_000` as a `Duration`. It
returns `error.Overflow` when the multiplication would overflow `i64`.

`Duration.isPositive()` returns `self.nanos() > 0`.

`Duration.isNegative()` returns `self.nanos() < 0`.

Equality uses native enum equality. Additional arithmetic (`add`, `sub`,
`mul`, `div`) is not owned by this spec; consumers use `nanos()`, do the math,
and convert back with `fromNanos`.

## `Clock.Monotonic(Backend)` semantics

`Clock.Monotonic(Backend)` is a wrapper around a caller-supplied backend that
adds a debug-only monotonicity assertion on `now` and, when the backend
exposes a `sleep` capability, forwards `sleep` verbatim with a debug-only
non-negative-delta assertion. The wrapper adds no other behavior.

Construction:

```zig
pub fn init(backend: Backend) Self;
```

`init` stores `backend` by value and initializes the debug-only `last` field
to `Instant.zero()` when `core.debug.checksEnabled` is true. In release builds
`last` has type `void` and occupies no space.

Reading:

```zig
pub fn now(self: *Self) Instant;
```

`now` calls `self.backend.now()` and returns the result. Under
`core.debug.checksEnabled`, `now` asserts that the returned instant is not
less than the previously returned instant, then updates the stored last value.

Under `core.debug.checksEnabled == false`, `now` is exactly one backend call
plus a return.

The wrapper is not thread-safe. `Clock.Monotonic(Backend)` is a single-owner
value; concurrent callers must serialize externally or hold their own
per-thread wrapper. The monotonic contract is a caller invariant, not a
lock.

Sleeping:

```zig
pub fn sleep(self: *Self, delta: Duration) void;
```

`sleep` is generated on `Self` iff `Backend` exposes a matching
`pub fn sleep(self: *Backend, delta: Duration) void` at instantiation. When
present, `sleep` calls `self.backend.sleep(delta)` and returns.

Under `core.debug.checksEnabled(.build_mode)`, `sleep` asserts
`delta.nanos() >= 0` before forwarding. Non-positive deltas are legal on
the backend seam.

Under `core.debug.checksEnabled == false`, `sleep` is exactly one backend
call plus a return.

Sleep granularity, preemption, signal restart, partial completion, and
`sleep(Duration.zero)` semantics are backend policy.

### Backend interface

A backend type must expose:

```zig
pub fn now(self: *Backend) stdx.time.Instant;
```

A backend may additionally expose:

```zig
pub fn sleep(self: *Backend, delta: stdx.time.Duration) void;
```

`now` signature is validated at compile time when `Clock.Monotonic(Backend)`
is instantiated:

- the identifier `now` must resolve to a `pub` function;
- the function must be callable with `*Backend` as its sole argument;
- the return type must be `stdx.time.Instant`;
- error unions and `anyerror` returns are rejected with `@compileError`.

`sleep` signature, when the identifier `sleep` is declared on `Backend`, is
also validated at compile time:

- the identifier `sleep` must resolve to a `pub` function;
- the function must be callable with `*Backend` and `stdx.time.Duration` as
  its sole arguments in that order;
- the return type must be `void`;
- error unions and `anyerror` returns are rejected with `@compileError`.

A backend that does not declare `sleep` produces a `Clock.Monotonic(Backend)`
without a `sleep` method; any callsite invoking `Self.sleep` is rejected by
the compiler. A backend that declares `sleep` with a mismatched signature
is rejected with a `@compileError` naming the required signature.

Backend `now` is required to return monotonically non-decreasing values on
consecutive calls from the same wrapper. A backend that cannot honor this
contract must not be used with `Clock.Monotonic`; the wrapper's debug
assertion catches violations in test and debug builds.

Backend `now` is infallible by contract. Backends whose underlying source can
fail must resolve the failure at construction time and reject the backend
before it reaches `Clock.Monotonic.init`.

Backend `sleep`, when declared, is infallible by contract. A backend whose
underlying sleep source can fail must resolve the failure internally: retry
against remaining delta, return early on a shorter observed sleep, or
otherwise reduce the operation to a `void` return. The wrapper does not
signal cancellation through `sleep`.

Backend `sleep(delta)` for `delta.nanos() <= 0` must return immediately
without observable side effects.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `Instant.fromNanos` | never | never | O(1) | value type | none | infallible |
| `Instant.nanos` | never | never | O(1) | value type | none | infallible |
| `Instant.zero` | never | never | O(1) | value type | none | infallible |
| `Instant.add` | never | never | O(1) | value type | none | `Overflow` on u64 wrap |
| `Instant.since` | never | never | O(1) | value type | none | infallible; may return negative |
| `Instant.afterOrEq` | never | never | O(1) | value type | none | infallible |
| `Duration.fromNanos` | never | never | O(1) | value type | none | infallible |
| `Duration.nanos` | never | never | O(1) | value type | none | infallible |
| `Duration.fromMicros` | never | never | O(1) | value type | none | `Overflow` on i64 mul |
| `Duration.fromMillis` | never | never | O(1) | value type | none | `Overflow` on i64 mul |
| `Duration.fromSeconds` | never | never | O(1) | value type | none | `Overflow` on i64 mul |
| `Duration.isPositive` | never | never | O(1) | value type | none | infallible |
| `Duration.isNegative` | never | never | O(1) | value type | none | infallible |
| `Clock.Monotonic` | never | never | comptime | type factory | validates backend | rejects bad backend |
| `Clock.Monotonic.init` | never | never | O(1) | exclusive construction | none | infallible |
| `Clock.Monotonic.now` | never | never | O(1) + backend | single-owner | backend-defined | infallible; debug assertion on non-monotonic backend |
| `Clock.Monotonic.sleep` | never | delegates to backend | O(1) + backend | single-owner | none | infallible; debug assertion on negative delta |

Time primitives perform no heap allocation, hidden global access, or target
probing. `Clock.Monotonic.now` delegates all work to the backend and adds
one comparison plus one store under `core.debug.checksEnabled`.
`Clock.Monotonic.sleep`, when generated, delegates all work to the backend
and adds one non-negative-delta assertion under
`core.debug.checksEnabled`. Any actual sleeping, blocking, or scheduler
interaction occurs inside the backend, not the wrapper.

## Error behavior

- `Instant.add` returns `error.Overflow` on `u64` overflow or underflow.
- `Instant.since` never fails. It may return a negative `Duration`.
- `Duration.fromMicros`, `Duration.fromMillis`, `Duration.fromSeconds` return
  `error.Overflow` when the multiplication would overflow `i64`.
- All other operations are infallible.
- `Clock.Monotonic(Backend)` with a backend missing `now`, or with an
  incorrect `now` signature, is a compile error.
- `Clock.Monotonic(Backend)` with a backend declaring `sleep` at a
  mismatched signature is a compile error.
- A backend without a declared `sleep` is legal; the resulting
  `Clock.Monotonic(Backend)` has no `sleep` method, and any callsite
  invoking `sleep` fails to compile.
- `Clock.Monotonic.now` never returns an error at the wrapper layer; debug
  builds gated by `core.debug.checksEnabled` assert on non-monotonic
  returns.
- `Clock.Monotonic.sleep`, when generated, never returns an error at the
  wrapper layer; debug builds gated by `core.debug.checksEnabled` assert on
  negative deltas.

## Implementation constraints

Implementation must:

- define `Instant` as `enum(u64) { _ }` and `Duration` as `enum(i64) { _ }`;
- avoid unchecked overflow in `Instant.add`, `Duration.fromMicros`,
  `Duration.fromMillis`, `Duration.fromSeconds`;
- compile the debug-mode monotonicity assertion out entirely when
  `core.debug.checksEnabled` is false, including the `last` field storage;
- validate `Backend.now` signature at compile time and reject error-union
  returns with a `@compileError` naming the required signature;
- generate `Clock.Monotonic(Backend).sleep` iff `Backend` declares `sleep`;
- validate the declared `Backend.sleep` signature at compile time and
  reject mismatched parameters, error-union returns, or `anyerror` returns
  with a `@compileError` naming the required signature;
- compile the debug-mode non-negative-delta assertion on `sleep` out
  entirely when `core.debug.checksEnabled` is false;
- avoid runtime target probing;
- avoid hidden global state;
- avoid allocation;
- keep `Clock.Monotonic` free of atomics — the concurrency contract is
  single-owner, not lock-free;
- lower `Clock.Monotonic.now` and `Clock.Monotonic.sleep` to direct backend
  calls in release builds.

## Planned use

A driver composes `Clock.Monotonic(HpetBackend)` — where `HpetBackend`
reads an HPET main counter — into its controller for handshake timeouts,
status-polling backoff, and admin/completion command timeouts.

Similar deadlines arise in ACPI GPE polling and PM timer waits, PCI MSI-X
programming, and firmware runtime-services windows.

Test consumers construct a `TestBackend` that increments a counter on each
`now()` call. Test backends are per-test scaffolding, not part of this spec.

## Examples

Backend shape:

```zig
const HpetBackend = struct {
    counter: *volatile stdx.io.Mmio.Register(u64),
    period_fs: u64, // femtoseconds per tick, from HPET capability register

    pub fn now(self: *HpetBackend) stdx.time.Instant {
        const ticks = self.counter.load();
        const ns = (ticks * self.period_fs) / 1_000_000;
        return .fromNanos(ns);
    }
};
```

Wrapper composition:

```zig
const HpetClock = stdx.time.Clock.Monotonic(HpetBackend);

var clock: HpetClock = .init(.{ .counter = counter_reg, .period_fs = period });
const start = clock.now();
```

Deadline loop:

```zig
const start = clock.now();
const deadline = try start.add(try stdx.time.Duration.fromMillis(500));

while (true) {
    const csts = regs.csts.load();
    stdx.barrier.mmio.acquire();
    if (csts_ready(csts)) break;

    if (clock.now().afterOrEq(deadline)) return error.Timeout;
    stdx.arch.x86_64.Cpu.pause();
}
```

Elapsed check:

```zig
const elapsed = clock.now().since(start);
if (elapsed.isNegative()) {
    // Backend violated monotonic contract; caught by debug assertion in debug builds.
}
```

## Required tests

### `Instant`

- `fromNanos(0).nanos() == 0`;
- `fromNanos(1).nanos() == 1`;
- `fromNanos(maxInt(u64)).nanos() == maxInt(u64)`;
- `zero() == fromNanos(0)`;
- `add(fromNanos(0), fromNanos(0))` returns `fromNanos(0)`;
- `add(fromNanos(100), fromNanos(50))` returns `fromNanos(150)`;
- `add(fromNanos(100), fromNanos(-50))` returns `fromNanos(50)`;
- `add(fromNanos(maxInt(u64)), fromNanos(1))` returns `error.Overflow`;
- `add(fromNanos(0), fromNanos(-1))` returns `error.Overflow`;
- `since(fromNanos(100), fromNanos(50)).nanos() == 50`;
- `since(fromNanos(50), fromNanos(100)).nanos() == -50`;
- `since(fromNanos(100), fromNanos(100)).nanos() == 0`;
- `afterOrEq` covers strictly less, equal, and strictly greater.

### `Duration`

- `fromNanos(0).nanos() == 0`;
- `fromNanos(1_000).nanos() == 1_000`;
- `fromNanos(-1_000).nanos() == -1_000`;
- `zero.nanos() == 0`;
- `fromMicros(1).nanos() == 1_000`;
- `fromMillis(1).nanos() == 1_000_000`;
- `fromSeconds(1).nanos() == 1_000_000_000`;
- `fromMillis(maxInt(i64) / 1_000_000 + 1)` returns `error.Overflow`;
- `fromMicros(maxInt(i64) / 1_000 + 1)` returns `error.Overflow`;
- `fromSeconds(maxInt(i64) / 1_000_000_000 + 1)` returns `error.Overflow`;
- `isPositive` and `isNegative` cover positive, zero, and negative values.

### `Clock.Monotonic(Backend)` compile-time validation

- a backend with `pub fn now(self: *Backend) Instant` compiles;
- a backend missing `now` produces a compile error;
- a backend whose `now` returns `!Instant` produces a compile error;
- a backend whose `now` returns `anyerror!Instant` produces a compile error;
- a backend whose `now` takes no argument or a wrong-typed argument produces a
  compile error.
- a backend with a matching `pub fn sleep(self: *Backend, delta: Duration) void`
  produces a `Clock.Monotonic(Backend)` exposing `sleep`;
- a backend without `sleep` produces a `Clock.Monotonic(Backend)` without
  `sleep`; a callsite invoking `Self.sleep` fails to compile;
- a backend whose `sleep` returns `!void` produces a compile error;
- a backend whose `sleep` returns `anyerror!void` produces a compile error;
- a backend whose `sleep` takes wrong-typed arguments produces a compile
  error.

### `Clock.Monotonic(Backend)` runtime

A `TestBackend` returning a caller-controlled sequence drives the wrapper.

- `init(backend)` stores the backend by value;
- `now()` returns exactly what the backend returned;
- calling `now()` 1000 times against a strictly increasing backend produces
  the same 1000 values;
- calling `now()` against a constant backend produces the same value on every
  call and does not fault under `core.debug.checksEnabled`;
- under `core.debug.checksEnabled == true`, a decreasing backend causes the
  second `now()` call to trip an assertion;
- under `core.debug.checksEnabled == false`, the same decreasing backend does
  not trip an assertion;
- under `core.debug.checksEnabled == false`,
  `@sizeOf(Clock.Monotonic(TestBackend)) == @sizeOf(TestBackend)`.
- against a backend recording every `sleep(delta)` call: `clock.sleep(d)`
  forwards `d` unchanged to the backend;
- under `core.debug.checksEnabled == true`,
  `clock.sleep(Duration.fromNanos(-1))` trips the debug assertion;
- under `core.debug.checksEnabled == false`, the same call forwards to the
  backend without a trap;
- `clock.sleep(Duration.zero)` forwards to the backend and returns.

## Open questions

None.
