# Time backoff

Status: Approved.

`stdx.time.Backoff` is a structured retry-delay generator. Each call to
`next` returns a `Step` describing what the caller should do — spin,
yield, sleep for a duration, or give up because the deadline has passed.
The primitive owns the phase progression and deadline clipping; the caller
owns the actual spin/yield/sleep.

`Backoff` is a value, not a scheduler. It does not spin, does not yield,
does not sleep, and never touches the clock beyond querying the deadline.

## Owned scope

This spec owns:

- `time.Backoff`, the retry-delay state machine;
- `time.Backoff.Policy`, the caller-provided tuning of spin/yield/sleep
  phases and geometric growth;
- `time.Backoff.Step`, the tagged-union result of `next`;
- deadline-aware clipping via `stdx.time.Deadline` and a caller-supplied
  clock;
- the yield-hook seam as an optional function pointer on `Policy`;
- reset semantics for retry state;
- debug-only structural validation of `Policy` and `Backoff` under
  `stdx.core.debug.checksEnabled`;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- executing the spin, yield, or sleep — the caller invokes
  `std.atomic.spinLoopHint`, the yield hook, or a wait mechanism itself;
- scheduler awareness beyond the caller-supplied `yield` function pointer;
- randomization or jitter — deterministic-first;
- global default `Backoff.Policy` values;
- attempt outcome tracking, retry-on-error batching, or `RetryPolicy`
  composites;
- `std.Io` integration;
- dynamic allocation — every `Backoff` is a caller-owned value;
- root promotion of `Backoff`.

If jitter, outcome tracking, or an async composite becomes necessary, that
is a separate spec.

## Public namespace

`Backoff` lives under `stdx.time`:

```zig
stdx.time.Backoff
stdx.time.Backoff.Policy
stdx.time.Backoff.Step
```

It is not root-promoted:

```zig
stdx.Backoff // not exported
```

Source ownership:

```text
src/time.zig
src/time/backoff.zig
test/time/backoff_test.zig
```

`src/time.zig` re-exports:

```zig
pub const backoff = @import("time/backoff.zig");

pub const Backoff = backoff.Backoff;
```

`src/time.zig` is a thin facade. It contains no logic beyond re-exporting
and aliasing.

## Approved API

```zig
pub const Backoff = struct {
    pub const Policy = struct {
        spin_iterations: u32,
        yield_iterations: u32,
        yield: ?*const fn () void,
        initial_wait: Duration,
        max_wait: Duration,
        growth_shift: u3,

        pub fn assertValid(self: Policy) void;
    };

    pub const Step = union(enum) {
        spin,
        yield,
        sleep: Duration,
        timeout,
    };

    policy: Policy,
    attempt: u32,
    next_wait: Duration,

    pub fn init(policy: Policy) Backoff;
    pub fn reset(self: *Backoff) void;

    pub fn next(
        self: *Backoff,
        deadline: Deadline,
        clock: anytype,
    ) Step;

    pub fn attempts(self: *const Backoff) u32;

    pub fn assertValid(self: *const Backoff) void;
};
```

There is no `Backoff.spin`, `Backoff.yield`, or `Backoff.sleep` that
performs the action; every phase result is returned and the caller
executes it. There is no jitter parameter, no `Policy.random`, no
`Backoff.Batched`, no async future variant.

`policy`, `attempt`, and `next_wait` are public fields. Callers may inspect
`next_wait` between calls for logging or heuristic sizing, and may
overwrite `policy` in place before calling `reset()` when they need to
swap policies.

## Policy semantics

`Policy.spin_iterations` is the number of `.spin` results returned before
transitioning to the yield phase. Zero is legal.

`Policy.yield_iterations` is the number of `.yield` results returned
before transitioning to the sleep phase. Zero is legal.

`Policy.yield` is a nullable function pointer. When `null`, the yield
phase is skipped entirely regardless of `yield_iterations`: `next` moves
directly from spin to sleep. This lets freestanding callers set
`yield: null` without altering `yield_iterations`.

`Policy.initial_wait` is the first `.sleep(Duration)` value returned in
the sleep phase. Must be non-negative.

`Policy.max_wait` is the ceiling on `next_wait`. Growth saturates at this
value. Must be `>= initial_wait`.

`Policy.growth_shift` is the left-shift applied to `next_wait` after each
sleep step. `0` produces a constant-wait backoff. Range is `u3` (0..7),
allowing up to 128× growth per step. Values that would push `next_wait`
past `max_wait` saturate.

`Policy.assertValid` checks:

- `initial_wait.nanos() >= 0`;
- `max_wait.nanos() >= 0`;
- `initial_wait.nanos() <= max_wait.nanos()`.

`Policy.assertValid` runs unconditionally when called. `Backoff.init` and
`Backoff.assertValid` call it under `checksEnabled(.build_mode)` only.

## Backoff semantics

### Initialization

`Backoff.init(policy)` returns a `Backoff` with `policy` stored,
`attempt = 0`, `next_wait = policy.initial_wait`. Under
`checksEnabled(.build_mode)`, `init` calls `policy.assertValid()`.

### Step transitions

`next(deadline, clock)` returns the next phase result. Logic, in order:

1. If `deadline.expired(clock)` → return `.timeout`. `attempt` is
   unchanged.
2. Else if `attempt < policy.spin_iterations` → return `.spin`,
   increment `attempt`.
3. Else if `policy.yield != null` and
   `attempt < policy.spin_iterations + policy.yield_iterations` →
   return `.yield`, increment `attempt`.
4. Else enter sleep phase:
   - compute `remaining = deadline.remaining(clock)`;
   - if `remaining.nanos() <= 0` → return `.timeout`, `attempt`
     unchanged;
   - compute `wait_ns = min(next_wait.nanos(), remaining.nanos())`;
     this can never be negative because both operands are non-negative
     (remaining is guaranteed positive at this point);
   - grow `next_wait`: `new_ns = next_wait.nanos() << policy.growth_shift`
     saturated at `policy.max_wait.nanos()`; overflow of the shift is
     also saturated at `max_wait`;
   - assign `next_wait = Duration.fromNanos(new_ns)`;
   - increment `attempt`;
   - return `.sleep(Duration.fromNanos(wait_ns))`.

Notes:

- The deadline check runs *first*; a caller who is already past the
  deadline never enters spin or yield phases.
- Sleep-phase deadline clipping is per-step: `.sleep(Duration)` is
  guaranteed to not overshoot the deadline.
- Increment of `attempt` on `.timeout` is intentionally omitted so that
  `attempts()` reports the count of "productive" attempts, not the count
  of `next` calls.

### Reset

`reset()` restores `attempt = 0` and `next_wait = policy.initial_wait`.
`policy` is not modified. Callers who want to swap policies overwrite
`self.policy` directly before calling `reset()`.

### Attempts

`attempts()` returns `self.attempt`, saturated at `maxInt(u32)`. The
counter is not expected to overflow in practical workloads; the return
type is `u32` matching the field.

### `assertValid`

`Backoff.assertValid` checks:

- `self.policy.assertValid()` (recursed);
- `self.next_wait.nanos() >= 0`;
- `self.next_wait.nanos() <= self.policy.max_wait.nanos()`.

Runs unconditionally when called. Consumers gate the call under
`checksEnabled(.build_mode)` per `core/debug.md` convention.

## Clock parameter

Every `next` call takes a `clock: anytype`. The clock's type must expose
`pub fn now(self: *Self) stdx.time.Instant` matching the backend contract
in `docs/specs/time/monotonic.md`. Compile-time signature check at each
callsite. `anyerror` returns and error-union returns are rejected.

Two `next` calls on the same `Backoff` should use the same clock. Mixing
clocks is a caller contract violation. `Backoff` is not tagged; the
primitive cannot detect the mix.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `Policy.assertValid` | never | never | O(1) | value type | none | asserts on invalid policy |
| `Backoff.init` | never | never | O(1) | value type | none | asserts under `checksEnabled` |
| `Backoff.reset` | never | never | O(1) | single-owner | none | infallible |
| `Backoff.next` | never | never | O(1) + backend `now` | single-owner | backend-defined | infallible; returns `.timeout` on expiry |
| `Backoff.attempts` | never | never | O(1) | reader | none | infallible |
| `Backoff.assertValid` | never | never | O(1) | reader | none | asserts on invalid state |

`Backoff` is safe from any execution context including NMI when the
supplied clock backend and yield hook (if any) are safe from that
context. The primitive itself performs no allocation, no locking, no
syscall, and no atomic operation.

## Debug assertion behavior

`Backoff.init` calls `policy.assertValid()` under
`stdx.core.debug.checksEnabled(.build_mode)`. Explicit
`Backoff.assertValid` calls run unconditionally, matching the
`assertValid` convention in `core/debug.md`.

Common misconfigurations caught by the debug check:

- `initial_wait > max_wait`;
- negative `initial_wait` or `max_wait`;
- `next_wait` drifted above `max_wait` due to caller mutation.

## std.Io lane

`Backoff` serves both lanes declared in the spec queue:

1. Composes inside a downstream `std.Io` backend where the `yield` hook
   wraps the runtime's yield primitive and `.sleep(Duration)` is
   translated into an `Io`-issued sleep.
2. Serves freestanding consumers (`Policy.yield = null`) in kernel init,
   hypervisor setup, firmware pre-runtime, device polling, and interrupt
   handlers, where `.sleep(Duration)` is executed against a
   caller-controlled clock or busy-loop.

Distinct from `std.Io`-native backoff: no vtable, no runtime, no
allocation, freestanding-safe.

## Examples

Spin then sleep, deadline-bounded, freestanding:

```zig
const stdx = @import("stdx");
const time = stdx.time;

const policy: time.Backoff.Policy = .{
    .spin_iterations = 32,
    .yield_iterations = 0,
    .yield = null,
    .initial_wait = try time.Duration.fromMicros(1),
    .max_wait = try time.Duration.fromMillis(1),
    .growth_shift = 1,
};

fn waitReady(dev: *Device, clock: anytype) !void {
    var bo = time.Backoff.init(policy);
    const deadline = try time.Deadline.now(
        clock,
        try time.Duration.fromMillis(500),
    );
    while (!dev.isReady()) {
        switch (bo.next(deadline, clock)) {
            .spin => std.atomic.spinLoopHint(),
            .yield => unreachable, // yield disabled
            .sleep => |d| clock.sleep(d),
            .timeout => return error.Timeout,
        }
    }
}
```

Hosted use with a runtime-provided yield:

```zig
const policy: time.Backoff.Policy = .{
    .spin_iterations = 8,
    .yield_iterations = 8,
    .yield = &std.Thread.yield,
    .initial_wait = try time.Duration.fromMicros(10),
    .max_wait = try time.Duration.fromMillis(10),
    .growth_shift = 2,
};
```

Reset for a fresh retry loop:

```zig
var bo = time.Backoff.init(policy);
// ... first attempt loop ...
bo.reset();
// ... second attempt loop, from initial_wait again ...
```

Overwriting policy in place before reset:

```zig
bo.policy.max_wait = try time.Duration.fromMillis(50);
bo.reset();
```

## Required tests

Tests live in `test/time/backoff_test.zig`.

Required tests:

- `Backoff.init(policy)` with `spin_iterations=3`, `yield_iterations=2`,
  `yield` set, produces the phase sequence
  `spin, spin, spin, yield, yield, sleep(initial_wait), ...` under a
  `Deadline.never`;
- The sleep values are `initial_wait`, `initial_wait << growth_shift`,
  `(initial_wait << growth_shift) << growth_shift`, ..., saturated at
  `max_wait`;
- `Policy.yield = null` with `yield_iterations = 2` skips yield entirely:
  phase sequence is `spin, spin, spin, sleep(initial_wait), ...`;
- Deadline clipping: `initial_wait = 100ms`, deadline with remaining
  `30ms` → `.sleep(30ms)`, next call → `.timeout`;
- Already-expired deadline: first `next` call returns `.timeout` and
  `attempts()` stays `0`;
- Exact-boundary deadline (`remaining == 0`) → `.timeout`;
- `reset()` restores `attempt = 0` and `next_wait = initial_wait`; policy
  unchanged; a subsequent `next` returns `.spin` (assuming
  `spin_iterations > 0`);
- `attempts()` matches the count of non-`.timeout` `next` results;
- `Backoff.assertValid` traps under `checksEnabled(.build_mode)` when
  `initial_wait > max_wait`;
- `Backoff.assertValid` traps under `checksEnabled(.build_mode)` when
  `next_wait` is mutated above `max_wait`;
- `growth_shift = 0` produces constant `next_wait` across sleep steps;
- Compile-only: passing a clock without `now(*Self) Instant` is rejected;
- Compile-only: `@sizeOf(Policy)` and `@sizeOf(Backoff)` are stable
  (recorded as invariants; test asserts against a fixed number so a size
  regression is caught);
- Non-x86 build compiles the module.

Tests use a `FakeClock` returning a caller-controlled `Instant`; no real
monotonic clock is required.

## Open questions

None.
