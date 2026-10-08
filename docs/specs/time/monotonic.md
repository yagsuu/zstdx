# Time monotonic clock

Status: Approved.

`stdx.time.Instant` and `stdx.time.Duration` are strong nanosecond-domain value
types. `stdx.time.Clock.Monotonic(Backend)` is a caller-composed wrapper that
enforces the monotonic-reader contract on top of a caller-supplied backend.

## API

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
    last: if (stdx.core.debug.checksEnabled()) Instant else void,

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

`Backend` is stored by value. For shared or large backend state, use a small backend struct containing a pointer and implementing the required methods.

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

`init` stores `backend` by value. When `core.debug.checksEnabled()` is true, `last` starts at `Instant.zero()`. In ReleaseFast and ReleaseSmall, `last` has type `void`.

Reading:

```zig
pub fn now(self: *Self) Instant;
```

`now` calls `self.backend.now()` and returns the result. Under
`core.debug.checksEnabled()`, `now` asserts that the returned instant is not
less than the previously returned instant, then updates the stored last value.

When `core.debug.checksEnabled()` is false, `now` is exactly one backend call
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

Under `core.debug.checksEnabled()`, `sleep` asserts
`delta.nanos() >= 0` before forwarding. Zero is legal.

When `core.debug.checksEnabled()` is false, `sleep` is exactly one backend
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
one comparison plus one store under `core.debug.checksEnabled()`.
`Clock.Monotonic.sleep`, when generated, delegates all work to the backend
and adds one non-negative-delta assertion under
`core.debug.checksEnabled()`. Actual sleeping, blocking, or scheduler
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
  builds gated by `core.debug.checksEnabled()` assert on non-monotonic
  returns.
- `Clock.Monotonic.sleep`, when generated, never returns an error at the
  wrapper layer; builds gated by `core.debug.checksEnabled()` assert on
  negative deltas.

## Implementation constraints

Implementation must:

- define `Instant` as `enum(u64) { _ }` and `Duration` as `enum(i64) { _ }`;
- avoid unchecked overflow in `Instant.add`, `Duration.fromMicros`,
  `Duration.fromMillis`, `Duration.fromSeconds`;
- compile the debug-mode monotonicity assertion out entirely when
  `core.debug.checksEnabled()` is false, including the `last` field storage;
- validate `Backend.now` signature at compile time and reject error-union
  returns with a `@compileError` naming the required signature;
- generate `Clock.Monotonic(Backend).sleep` iff `Backend` declares `sleep`;
- validate the declared `Backend.sleep` signature at compile time and
  reject mismatched parameters, error-union returns, or `anyerror` returns
  with a `@compileError` naming the required signature;
- compile the debug-mode non-negative-delta assertion on `sleep` out
  entirely when `core.debug.checksEnabled()` is false;
- avoid runtime target probing;
- avoid hidden global state;
- avoid allocation;
- keep `Clock.Monotonic` free of atomics — the concurrency contract is
  single-owner, not lock-free;
- lower `Clock.Monotonic.now` and `Clock.Monotonic.sleep` to direct backend
  calls in ReleaseFast and ReleaseSmall.

## Testing

Tests MUST use fixed values and caller-controlled backend sequences.

### Value-domain boundaries

Tests MUST cover zero, both signs, equality, representable instant separation, signed-duration endpoints, and unit-conversion overflow.

### Backend interface model

Compile-time checks MUST cover required `now`, optional `sleep`, receiver and return types, rejected error unions, and absence of generated `sleep` when unsupported.

### Clock transitions

Backend sequences MUST cover increasing, constant, and decreasing readings and record sleep durations. Check monotonicity and non-negative sleep assertions in Debug/ReleaseSafe, unchanged forwarding and absent validation storage in ReleaseFast/ReleaseSmall, and by-value backend ownership.
