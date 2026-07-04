# IO poll until

Status: Approved.

`stdx.io.poll.until` is a wait-for-value poll loop that composes
`stdx.time.Deadline` and `stdx.time.Backoff` with a caller-supplied
predicate. It is the shared shape for device-init handshakes,
controller-ready checks, capability-negotiation polls, and any
"call a predicate; if it hasn't fired yet, back off and retry" loop.

`poll.until` is an algorithm, not a scheduler primitive. It does not
allocate, does not lock, does not synchronize, and never touches the
clock or the backoff outside the contracts owned by
`docs/specs/time/monotonic.md` and `docs/specs/time/backoff.md`.

## Owned scope

This spec owns:

- `stdx.io.poll.until(clock, deadline, backoff, predicate)` — free
  function, not a type factory;
- `stdx.io.poll.PollReturnType(Predicate)` — comptime helper that names
  the concrete error-union return type derived from a predicate type;
- the polling-clock composition seam (`now` + `sleep`);
- the predicate composition seam (bare function or struct-with-`call`);
- the fixed step-dispatch discipline against `time.Backoff.Step`;
- comptime rejection of unsupported clock and predicate shapes;
- debug-only structural assertion around the `Backoff.Step.yield` invariant;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- retry-policy composition (`time.RetryPolicy` — deferred spec);
- cancellation tokens or a built-in `error.Aborted` — cancellation is
  caller policy through the predicate's own error variant;
- attempt outcome tracking, retry-on-error batching, or logging hooks;
- multi-owner polling — `pollUntil` mutates `*Backoff`, single owner only;
- scheduler awareness beyond `Backoff.Policy.yield`;
- clock construction, backend selection, or feature detection;
- `std.Io` integration — polling backends compose `poll.until` inside a
  downstream `Io` vtable, not the other way around;
- root promotion of `poll` or `until`.

## Public namespace

`poll.until` lives under `stdx.io.poll`:

```zig
stdx.io.poll
stdx.io.poll.until
stdx.io.poll.PollReturnType
```

It is not root-promoted:

```zig
stdx.pollUntil     // not exported
stdx.io.pollUntil  // not exported
stdx.io.until      // not exported
```

Source ownership:

```text
src/io.zig
src/io/poll.zig
test/io/poll_test.zig
```

`src/io.zig` re-exports:

```zig
pub const poll = @import("io/poll.zig");
```

`src/io.zig` is a thin facade. It contains no logic beyond re-exporting
and aliasing.

## Approved API

```zig
pub fn until(
    clock: anytype,
    deadline: time.Deadline,
    backoff: *time.Backoff,
    predicate: anytype,
) PollReturnType(@TypeOf(predicate));

pub fn PollReturnType(comptime Predicate: type) type;
```

There is no `stdx.io.poll.forBit`, `poll.forValue`, `poll.forFlag`,
`poll.withCancel`, or `poll.batched`. The one `until` verb takes an
arbitrary predicate; specialized bit/value helpers live outside this
spec, in the consumer domain that names the register.

There is no `struct PollUntil` namespace wrapper. `poll` is the
namespace; `until` is the algorithm.

`PollReturnType` is exported so callers can name the concrete return
type in intermediate function signatures. Callers who write `try
poll.until(...)` at the callsite do not need to invoke it.

## Predicate contract

`predicate` is `anytype`. At the callsite the argument's type must
satisfy exactly one of the following shapes:

1. A bare function type or function pointer:
   ```zig
   fn () PredicateError!?T
   *const fn () PredicateError!?T
   ```
   Invoked as `predicate()`.
2. A value whose type declares a `call` method taking one parameter
   (the receiver) and returning `PredicateError!?T`:
   ```zig
   pub fn call(self: @This()) PredicateError!?T
   pub fn call(self: *@This()) PredicateError!?T
   pub fn call(self: *const @This()) PredicateError!?T
   ```
   Invoked as `predicate.call()`.

Both shapes must return `PredicateError!?T` for some inferred error set
`PredicateError` (may be `error{}`) and some payload type `T` (may be
`void`; `?void` collapses to `?void` at the Zig type level and the
`null`-vs-`{}` distinction still drives the loop).

Comptime rejection cases (each surfaced with a distinct
`@compileError` message):

- non-optional return payload (`E!T` instead of `E!?T`);
- non-error-union return (`?T` alone);
- `anyerror` in the return error set;
- callable with more than the receiver parameter;
- neither a callable function type nor a struct exposing `call`;
- multiple `call` overloads (Zig-level compile error surfaces first).

## Clock parameter

The `clock` argument's type must expose both:

```zig
pub fn now(self: *Self) stdx.time.Instant;
pub fn sleep(self: *Self, delta: stdx.time.Duration) void;
```

matching the polling-clock superset of the backend contract in
`docs/specs/time/monotonic.md`. Both methods are compile-time checked
at each `poll.until` callsite. `anyerror` return types and error-union
return types on either method are rejected.

A backend whose `now` satisfies `time.Clock.Monotonic(Backend)` also
satisfies the `now` half of this contract, so callers can pass either
a `*time.Clock.Monotonic(Backend)` (after adding a `sleep` method) or a
bare backend that exposes both methods.

Passing two different clocks to a single `poll.until` call is a caller
contract violation; `poll.until` is untagged and cannot detect it. This
matches `Deadline` and `Backoff`.

## Semantics

### Loop structure

`poll.until` runs the following loop until a payload, an error, or a
timeout is produced:

```text
loop:
    if predicate() → not null → return payload
    switch backoff.next(deadline, clock):
        .spin     → std.atomic.spinLoopHint()
        .yield    → backoff.policy.yield.?()
        .sleep(d) → clock.sleep(d)
        .timeout  → return error.Timeout
```

The predicate runs first inside the loop body. `Backoff.next` runs
after every predicate that returns `null`. The deadline check is
owned by `Backoff.next` per `docs/specs/time/backoff.md` and is not
duplicated inside `poll.until`.

### Progress rule

Exactly one predicate call runs before the first `Backoff.next` call.
`poll.until(clock, Deadline.at(clock.now()), &backoff, predicate)`
therefore still gives the predicate one chance to observe a completed
device state before returning `error.Timeout`. Verified by test.

### Spin dispatch

On `.spin`, `poll.until` invokes `std.atomic.spinLoopHint()` and loops.
No other action is taken.

### Yield dispatch

On `.yield`, `poll.until` invokes `backoff.policy.yield.?()` and loops.

`Backoff` guarantees that a `.yield` result is only produced when
`policy.yield != null` (`docs/specs/time/backoff.md`, "Step
transitions"). Under `stdx.core.debug.checksEnabled(.build_mode)`,
`poll.until` asserts `backoff.policy.yield != null` immediately before
the unwrap; the trap surfaces a `Backoff` invariant break rather than
a raw null-pointer unwrap.

### Sleep dispatch

On `.sleep(d)`, `poll.until` invokes `clock.sleep(d)` and loops. The
`Duration` passed to `sleep` is the value produced by `Backoff.next`,
already deadline-clipped per `docs/specs/time/backoff.md`.

### Timeout dispatch

On `.timeout`, `poll.until` returns `error.Timeout` through
`time.Deadline.TimeoutError`. `attempts()` on the caller-supplied
backoff reflects the number of productive attempts (`Backoff` does
not increment `attempt` on `.timeout`).

### Predicate error dispatch

A predicate that returns an error propagates that error unwrapped
through `PollReturnType(@TypeOf(predicate))`. No backoff step is
consumed in that iteration.

Callers implement cancellation by having the predicate return an
`error.Cancelled` (or their own name) when a cancel token fires. The
error variant flows through `PredicateError` and reaches the caller
without translation.

## Return type

For a predicate whose call returns `PredicateError!?T`:

```zig
PollReturnType(@TypeOf(predicate)) == (time.Deadline.TimeoutError || PredicateError)!T
```

`time.Deadline.TimeoutError` is `error{Timeout}` (see
`docs/specs/time/deadline.md`). `PredicateError` and `T` are recovered
by comptime shape analysis of the predicate type. The error union
`E || F` is Zig's `MergeErrorSets` builtin behavior; no cross-error
translation is performed.

When `PredicateError == error{}`, `PollReturnType` collapses to
`time.Deadline.TimeoutError!T`. When `T == void`, `poll.until` returns
`PollError!void`.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `poll.until` | never | delegates to `clock.sleep` and `policy.yield` | O(attempts) × (predicate + `Backoff.next`) | single-owner over `*Backoff` | inherits from clock, backoff, and predicate | `Timeout` on deadline expiry; predicate errors propagated |
| `PollReturnType` | never | never | comptime | pure comptime | none | infallible |

`poll.until` is safe from any execution context including NMI when the
supplied clock, predicate, and `policy.yield` hook are safe from that
context. `poll.until` itself performs no allocation, no locking, no
syscall, and no atomic operation.

## Debug assertion behavior

`poll.until` performs one runtime assertion under
`stdx.core.debug.checksEnabled(.build_mode)`:

- before unwrapping `backoff.policy.yield.?` on a `.yield` step,
  assert `backoff.policy.yield != null`.

Under `checksEnabled == false` the assertion compiles out and the
unwrap runs directly. The invariant remains a `Backoff` guarantee; the
debug trap merely locates the fault.

`poll.until` performs no other runtime assertions. Predicate return
shape, clock shape, and backoff policy validity are already checked at
their owning boundaries.

## std.Io lane

`poll.until` serves both lanes declared in the spec queue:

1. Composes inside a downstream `std.Io` backend whose `Io.Clock`
   exposes `now`/`sleep` matching this spec's contract. The polling
   backend is inside the `Io` implementation, not on top of it.
2. Serves freestanding consumers where `std.Io` is not available —
   kernel init, hypervisor setup, firmware pre-runtime, interrupt
   handlers, device polling — against any polling-clock backend the
   caller composes.

Distinct from any `std` primitive: `std.time.sleep` does not compose
with a deadline; `std.Thread.yield` does not compose with a predicate;
`std.Io` requires the vtable and a runtime.

## Examples

Wait for a device-ready bit with a bounded budget:

```zig
const stdx = @import("stdx");
const time = stdx.time;

const IsReady = struct {
    dev: *Device,
    pub fn call(self: *@This()) error{DeviceFault}!?void {
        if (self.dev.faulted()) return error.DeviceFault;
        return if (self.dev.ready()) {} else null;
    }
};

fn waitReady(dev: *Device, clock: anytype) !void {
    var backoff = time.Backoff.init(.{
        .spin_iterations = 32,
        .yield_iterations = 0,
        .yield = null,
        .initial_wait = try time.Duration.fromMicros(1),
        .max_wait = try time.Duration.fromMillis(1),
        .growth_shift = 1,
    });
    const deadline = try time.Deadline.now(
        clock,
        try time.Duration.fromMillis(500),
    );
    var ctx: IsReady = .{ .dev = dev };
    try stdx.io.poll.until(clock, deadline, &backoff, &ctx);
}
```

Wait for a completion entry and return its payload:

```zig
const Take = struct {
    q: *CompletionQueue,
    pub fn call(self: *@This()) error{Fatal}!?Completion {
        if (self.q.status().fatal()) return error.Fatal;
        return self.q.tryPop();
    }
};

fn drainOne(q: *CompletionQueue, clock: anytype) !Completion {
    var backoff = time.Backoff.init(...);
    const deadline = try time.Deadline.now(clock, try time.Duration.fromMillis(50));
    var ctx: Take = .{ .q = q };
    return try stdx.io.poll.until(clock, deadline, &backoff, &ctx);
}
```

Bare-function predicate for a stateless probe:

```zig
fn cr0Enabled() error{}!?void {
    return if (readCr0() & CR0_PE != 0) {} else null;
}

fn waitCr0(clock: anytype) !void {
    var backoff = time.Backoff.init(policy);
    const deadline = try time.Deadline.now(clock, try time.Duration.fromMillis(10));
    try stdx.io.poll.until(clock, deadline, &backoff, cr0Enabled);
}
```

## Required tests

Tests live in `test/io/poll_test.zig`.

Required tests:

- Immediate success: predicate returns non-null on the first call →
  `poll.until` returns the payload; the fake backoff records zero
  `next` calls; the fake clock records zero `sleep` calls.
- Late success: predicate returns `null` on N successive calls then a
  payload → `poll.until` returns the payload; `backoff.attempts() == N`.
- Timeout: predicate returns `null` forever with a bounded deadline →
  `poll.until` returns `error.Timeout` after the backoff hits `.timeout`.
- Progress rule: `deadline = Deadline.at(fake_clock.now())`, predicate
  returns a payload on the first call → returns the payload, not
  `error.Timeout`.
- Predicate error propagation: predicate returns `error.DeviceFault`
  → `poll.until` returns `error.DeviceFault`; return type at comptime
  includes `error.DeviceFault`.
- Caller cancellation: predicate returns `error.Cancelled` on the Nth
  call → `poll.until` returns `error.Cancelled`; no extra backoff step
  consumed in that iteration.
- Step ordering (`spin_iterations=2, yield_iterations=1,
  growth_shift=0`, `policy.yield` set): recorded event sequence starts
  with `predicate, spin, predicate, spin, predicate, yield, predicate,
  sleep, predicate, sleep, ...`; sleep durations are all
  `initial_wait`.
- Yield dispatch count: with `yield_iterations = 4`, the yield-hook
  counter increments exactly `4` times before the first sleep.
- Sleep dispatch fidelity: `clock.sleep(d)` is called with the exact
  `Duration` produced by `Backoff.next` (verified against sleep-log
  values).
- Debug assertion: with `policy.yield = null` but a synthetic backoff
  forced to return `.yield` (test-only fake `Backoff`), `poll.until`
  traps under `checksEnabled(.build_mode)`.
- Method-object predicate: `pub fn call(self: *Ctx) E!?T` shape is
  accepted; `self: Ctx` and `self: *const Ctx` also accepted.
- Bare-function predicate: `fn () E!?T` accepted through both function
  value and function pointer.
- Compile-only: predicate returning `E!T` (non-optional payload)
  rejected with `@compileError` naming the payload shape.
- Compile-only: predicate returning `?T` (no error union) rejected.
- Compile-only: predicate returning `anyerror!?T` rejected.
- Compile-only: callable with more than the receiver parameter
  rejected.
- Compile-only: value that is neither a callable nor a struct with
  `call` rejected.
- Compile-only: clock missing `sleep(*Self, Duration) void` rejected.
- Compile-only: clock whose `now` returns `!Instant` rejected.
- Compile-only: clock whose `sleep` returns `!void` rejected.
- Compile-only:
  `PollReturnType(@TypeOf(predicate)) == (error{Timeout} || PredicateError)!T`
  for a representative predicate.
- Compile-only:
  `PollReturnType(@TypeOf(pred_zero_err)) == error{Timeout}!T` when the
  predicate's error set is `error{}`.
- Non-x86 build compiles the module.

Tests use a `FakeClock` returning a caller-controlled `Instant` plus a
`sleep` log, and a `FakeBackoff` shim where the yield-null assertion
test needs one. No real monotonic clock is required.

## Open questions

None.
