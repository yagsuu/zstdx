# Time deadline

Status: Approved.

`stdx.time.Deadline` is a strong monotonic-instant anchor with an
"expired?" predicate, a signed-remaining-duration query, and a
`error.Timeout` shortcut for poll loops. It composes with any clock
matching the backend contract in `docs/specs/time/monotonic.md`.

`Deadline` is a value, not a scheduler primitive. It never sleeps, never
parks, and never touches the backend beyond calling `Backend.now()`.

## Owned scope

This spec owns:

- `stdx.time.Deadline` (`enum(u64) { _ }`, monotonic-nanosecond anchor);
- `Deadline.at(instant)`, `Deadline.now(clock, delta)`, `Deadline.never`
  factories;
- `Deadline.instant`, `Deadline.isNever`, `Deadline.expired`,
  `Deadline.remaining`, `Deadline.expireBy` operations;
- the operation-local error sets `Deadline.OverflowError` and
  `Deadline.TimeoutError`;
- the `clock: anytype` composition seam (duck-typed against `Instant`
  `Backend.now`);
- monotonic-clock consumption contract;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- sleeping, blocking, waiting, or scheduler interaction — those are the
  clock backend or a wait-capable primitive's job;
- wallclock or coarse-monotonic deadlines;
- `time.Backoff` or `time.RetryPolicy` (owned by `time/backoff.md`);
- poll-loop composition (owned by `io/poll-until.md`);
- multi-clock deadlines — `Deadline` is untagged and inherits `Instant`'s
  "caller keeps clocks straight" stance;
- deadline arithmetic beyond the factories named above; callers use
  `Instant`/`Duration` directly through `deadline.instant()`;
- root promotion of `Deadline`.

## Public namespace

`Deadline` lives under `stdx.time`:

```zig
stdx.time.Deadline
```

It is not root-promoted:

```zig
stdx.Deadline // not exported
```

Source ownership:

```text
src/time.zig
src/time/deadline.zig
test/time/deadline_test.zig
```

`src/time.zig` re-exports:

```zig
pub const deadline = @import("time/deadline.zig");

pub const Deadline = deadline.Deadline;
```

`src/time.zig` is a thin facade. It contains no logic beyond re-exporting
and aliasing.

## Approved API

```zig
pub const Deadline = enum(u64) {
    _,

    pub const Raw = u64;
    pub const OverflowError = error{Overflow};
    pub const TimeoutError = error{Timeout};

    // Sentinel meaning "never expires".
    // Represented as maxInt(u64) so `expired` naturally reports false
    // against any clock reading in the practical domain.
    pub const never: Deadline = @enumFromInt(std.math.maxInt(u64));

    pub fn at(instant: Instant) Deadline;
    pub fn now(clock: anytype, delta: Duration) OverflowError!Deadline;

    pub fn instant(self: Deadline) Instant;
    pub fn isNever(self: Deadline) bool;

    pub fn expired(self: Deadline, clock: anytype) bool;
    pub fn remaining(self: Deadline, clock: anytype) Duration;
    pub fn expireBy(self: Deadline, clock: anytype) TimeoutError!void;
};
```

There is no shared `Deadline.Error` alias. `Deadline.now` can only return
`error.Overflow`; `Deadline.expireBy` can only return `error.Timeout`, so poll
loops do not inherit overflow in their error sets.

There is no `Deadline.add`, no `Deadline.beforeOrEq`, no `Deadline.min`,
and no `Deadline.max`. Callers who need arithmetic escape through
`deadline.instant()`, operate on `Instant`/`Duration`, and construct a new
`Deadline` via `at`.

There is no wallclock variant, no `Deadline.Wall`, no coarse-monotonic
variant. Every `Deadline` is monotonic.

## Clock parameter

Every operation that takes a `clock: anytype` requires the argument's type
to expose:

```zig
pub fn now(self: *Self) stdx.time.Instant;
```

matching the `Backend.now` signature approved in
`docs/specs/time/monotonic.md`. Both a `*time.Clock.Monotonic(Backend)`
wrapper and a bare backend satisfy the signature. The signature is
compile-time checked at each callsite; `anyerror` returns and error-union
returns are rejected via `@compileError`.

Passing two different clocks to two calls on the same `Deadline` is a
caller contract violation. `Deadline` is not tagged; the primitive cannot
detect the mix. Callers who mix clocks keep them straight themselves,
matching the stance from `Instant`.

## Semantics

### Representation

`Deadline` is `enum(u64) { _ }`. The stored value is the target
nanosecond-count on the monotonic clock the caller intends to check
against. Storage is one `u64` word; `@sizeOf(Deadline) == 8`.

`Deadline.never` is `Deadline.at(Instant.fromNanos(maxInt(u64)))`. It is
approximately 584 years past the backend epoch — outside every practical
clock reading.

### Construction

`Deadline.at(instant)` returns `@enumFromInt(instant.nanos())`. Infallible.

`Deadline.now(clock, delta)` computes `clock.now().add(delta)` and wraps
the result as a `Deadline`. It propagates `error.Overflow` from
`Instant.add` unchanged through `Deadline.OverflowError`: overflow occurs when
`delta` is large enough to push past `maxInt(u64)` or below `0`. Negative
`delta` is legal; `Deadline.now(clock, Duration.fromNanos(-1))` produces a
deadline in the past, and `expired(clock)` returns `true` immediately.

### Instant projection

`deadline.instant()` returns `Instant.fromNanos(@intFromEnum(self))`.
Infallible.

### Never sentinel

`deadline.isNever()` returns `@intFromEnum(self) == maxInt(u64)`.

For `Deadline.never`:

- `expired(clock)` returns `false` for any clock reading strictly less
  than `maxInt(u64)`. A clock that could return `maxInt(u64)` on a live
  monotonic reading is outside the practical envelope; the primitive does
  not defend against it.
- `remaining(clock)` returns
  `Duration.fromNanos(maxInt(i64))` — saturated at the positive
  `Duration` domain limit — regardless of the actual arithmetic result.
  This is the sole point where `Deadline` diverges from the naive
  `Instant.since` computation: `never.instant().since(clock.now())` would
  overflow the `i64` domain, and returning that would be a caller
  landmine.
- `expireBy(clock)` returns `void` for any live clock reading.

### Expired predicate

`deadline.expired(clock)` computes `clock.now().afterOrEq(deadline.instant())`
and returns the result. Boundary: when `clock.now() == deadline.instant()`,
`expired` returns `true`. Rationale: `afterOrEq` matches the "return
timeout at the deadline" convention downstream consumers expect.

### Remaining duration

`deadline.remaining(clock)` computes
`deadline.instant().since(clock.now())` and returns the signed `Duration`.

- Positive when the deadline is in the future.
- Zero at the exact boundary (`clock.now() == deadline.instant()`).
- Negative when the deadline has passed.

The sign carries the "just barely expired" information that a
saturating-at-zero design would erase.

For `Deadline.never`, `remaining` saturates at
`Duration.fromNanos(maxInt(i64))` as described above.

### expireBy

`deadline.expireBy(clock)` returns `error.Timeout` through
`Deadline.TimeoutError` if `expired(clock)` is `true`, and `void` otherwise.
It is the composition point for poll loops and device-init handshakes:

```zig
while (!device.ready()) {
    try deadline.expireBy(clock);
}
```

The error name is `Timeout`, matching the canonical spelling used across
consumers.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `Deadline.at` | never | never | O(1) | value type | none | infallible |
| `Deadline.now` | never | never | O(1) + backend | value type | backend-defined | `Overflow` on u64 wrap |
| `Deadline.never` | never | never | O(0) constant | value type | none | infallible |
| `instant` | never | never | O(1) | value type | none | infallible |
| `isNever` | never | never | O(1) | value type | none | infallible |
| `expired` | never | never | O(1) + backend | value type | backend-defined | infallible |
| `remaining` | never | never | O(1) + backend | value type | backend-defined | infallible; may return negative |
| `expireBy` | never | never | O(1) + backend | value type | backend-defined | `Timeout` on past-deadline |

`Deadline` is safe from any execution context including NMI when paired
with a backend whose `now` is safe from that context. The primitive itself
performs no allocation, no locking, no syscall, and no atomic operation.

## Debug assertion behavior

`Deadline` has no cross-field invariant and provides no `assertValid`.
The monotonic-clock invariant (non-decreasing `now`) is owned and asserted
by `stdx.time.Clock.Monotonic(Backend)` under
`stdx.core.debug.checksEnabled`; `Deadline` does not repeat that check.

## std.Io lane

`Deadline` serves both lanes declared in the spec queue:

1. Composes inside a downstream `std.Io` backend whose `Instant` matches
   `stdx.time.Instant`.
2. Serves freestanding consumers (kernel init, hypervisor setup, firmware
   pre-runtime, device polling) against any `Clock.Monotonic(Backend)`.

Distinct from `std.Io.Deadline`: no `Io` vtable, no runtime, no
allocation, freestanding-safe.

## Examples

Device init handshake with a bounded wait:

```zig
const stdx = @import("stdx");

fn waitReady(dev: *Device, clock: anytype) !void {
    const deadline = try stdx.time.Deadline.now(
        clock,
        try stdx.time.Duration.fromMillis(500),
    );
    while (!dev.isReady()) {
        try deadline.expireBy(clock);
    }
}
```

Optional deadline composition using `never` as the sentinel:

```zig
fn drain(queue: *Queue, clock: anytype, timeout: ?stdx.time.Duration) !void {
    const deadline = if (timeout) |d|
        try stdx.time.Deadline.now(clock, d)
    else
        stdx.time.Deadline.never;

    while (queue.pop()) |item| {
        process(item);
        try deadline.expireBy(clock);
    }
}
```

Signed remaining for backoff sizing:

```zig
fn attemptDelay(deadline: stdx.time.Deadline, clock: anytype) stdx.time.Duration {
    const left = deadline.remaining(clock);
    if (left.isNegative()) return stdx.time.Duration.zero;
    // Cap the next backoff at half the remaining time.
    const half_ns = @divFloor(left.nanos(), 2);
    return stdx.time.Duration.fromNanos(half_ns);
}
```

## Required tests

Tests live in `test/time/deadline_test.zig`.

Required tests:

- `Deadline.at(inst).instant() == inst` for `Instant.fromNanos(0)`,
  a mid value, and `Instant.fromNanos(maxInt(u64) - 1)`;
- `Deadline.now(&fake_clock, Duration.fromMillis(10))` produces a deadline
  exactly `10_000_000` nanoseconds past `fake_clock.now()`;
- `Deadline.now(&fake_clock, Duration.fromNanos(-1))` produces a deadline
  one nanosecond before `fake_clock.now()`, and `expired` returns `true`
  on the very next call;
- `Deadline.now(&fake_clock, Duration.fromNanos(maxInt(i64)))` where
  `fake_clock.now()` is near `maxInt(u64)` returns `error.Overflow`;
- `Deadline.never.isNever()` is `true`; `Deadline.at(Instant.zero()).isNever()`
  is `false`;
- `Deadline.never.expired(&fake_clock)` is `false` for any fake clock
  reading below `maxInt(u64)`;
- `Deadline.never.remaining(&fake_clock)` equals
  `Duration.fromNanos(maxInt(i64))` for every clock reading in the
  practical domain;
- `Deadline.never.expireBy(&fake_clock)` returns `void`;
- `expired(clock)` transitions from `false` to `true` exactly when
  `clock.now() == deadline.instant()`;
- `remaining(clock)` returns a positive duration before the deadline,
  `Duration.zero` at exact boundary, and a negative duration after;
- `expireBy(clock)` returns `error.Timeout` at and after the boundary,
  `void` before;
- Compile-only: `@typeInfo(@TypeOf(Deadline.expireBy)).@"fn".return_type.?`
  is `Deadline.TimeoutError!void` and does not include `error.Overflow`;
- Compile-only: passing a clock type without a `now(*Self) Instant`
  method is rejected with `@compileError`;
- Compile-only: passing a clock whose `now` returns `!Instant` is
  rejected;
- `@sizeOf(Deadline) == 8`;
- Non-x86 build compiles the module.

Tests use a `FakeClock` implementation that returns a caller-controlled
`Instant`; no real monotonic clock is required.

## Open questions

None.
