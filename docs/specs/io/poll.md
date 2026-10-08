# IO poll until

Status: Approved.

`stdx.io.poll.until` repeatedly invokes a caller-supplied predicate until the predicate returns a payload or an error, or a `time.Backoff` step reports deadline expiry. It composes a caller-supplied clock, `time.Deadline`, and caller-owned `time.Backoff`.

## Terminology

- **Predicate:** The callable supplied to `until`. A predicate returns `null` to continue, a payload to complete, or an error to stop.
- **Productive attempt:** A non-timeout `Backoff.next` result. `Backoff.attempts()` counts productive attempts.
- **Polling clock:** The clock argument passed to `until` and to `Backoff.next`.

## Cross-spec relationships

`until` depends on `time.Deadline` for the timeout error and deadline state, `time.Backoff` for phase progression and deadline clipping, and the monotonic-clock interface from `docs/specs/time/monotonic.md`. `until` executes the `Backoff.Step` returned by `Backoff.next`; it does not redefine backoff state transitions or clock semantics.

## Global invariants

- `until` MUST NOT allocate, lock, call a syscall, access a hidden global, or perform an atomic operation.
- `until` mutates only the caller-supplied `*time.Backoff` through `Backoff.next`. The caller retains ownership of the backoff before, during, and after the call.
- The caller MUST provide exclusive access to `*time.Backoff` for the complete call. Concurrent calls using the same backoff are unsupported.
- The caller MUST use one compatible clock for the supplied deadline and backoff. `until` cannot detect mixed clocks.
- `until` inherits clock, predicate, backoff, and yield-hook ordering and execution-context properties. It is usable in an execution context, including NMI, only when all supplied operations are usable in that context.

## API

```zig
pub fn until(
    clock: anytype,
    deadline: time.Deadline,
    backoff: *time.Backoff,
    predicate: anytype,
) PollReturnType(@TypeOf(predicate));

pub fn PollReturnType(comptime Predicate: type) type;
```

`PollReturnType` is a comptime helper for naming `until` return types. It has no runtime behavior.

### Predicate contract

The predicate type MUST be exactly one of these shapes:

```zig
fn () PredicateError!?T
*const fn () PredicateError!?T
```

or a struct value or pointer whose type declares one `call` method:

```zig
pub fn call(self: @This()) PredicateError!?T
pub fn call(self: *@This()) PredicateError!?T
pub fn call(self: *const @This()) PredicateError!?T
```

`until` invokes a function predicate as `predicate()` and a struct predicate as `predicate.call()`.

`PredicateError` MAY be `error{}`. It MUST NOT be `anyerror`. `T` MAY be `void`. `null` means that polling continues; a non-null value completes the call.

The implementation MUST reject each unsupported predicate shape with `@compileError`: a non-error-union return, an error union with a non-optional payload, `anyerror`, a function with parameters, a `call` method without exactly its receiver parameter, and a value that is neither a function nor a type with `call`. Zig reports its own error before this API's diagnostic when the source declares multiple `call` overloads.

For a valid predicate that returns `PredicateError!?T`:

```zig
PollReturnType(@TypeOf(predicate)) == (time.Deadline.TimeoutError || PredicateError)!T
```

`time.Deadline.TimeoutError` is `error{Timeout}`. Predicate errors are neither translated nor wrapped. When `PredicateError` is `error{}`, the result is `time.Deadline.TimeoutError!T`.

### Clock contract

The clock type MUST expose both methods:

```zig
pub fn now(self: *Self) stdx.time.Instant;
pub fn sleep(self: *Self, delta: stdx.time.Duration) void;
```

`until` verifies both signatures at the callsite. The methods MUST NOT return an error union or `anyerror`. A `*time.Clock.Monotonic(Backend)` with the required forwarded `sleep` method and a bare backend with both methods satisfy this contract.

A bare backend does not receive the monotonic-wrapper debug assertions. The caller is responsible for a clock implementation whose `now` and `sleep` behavior satisfies the composed time contracts.

### Poll-loop state transitions

Each iteration has these transitions:

1. `until` invokes the predicate.
2. If the predicate returns an error, `until` returns that error. It MUST NOT call `Backoff.next` for that iteration.
3. If the predicate returns a payload, `until` returns that payload. It MUST NOT call `Backoff.next` for that iteration.
4. If the predicate returns `null`, `until` calls `backoff.next(deadline, clock)` and dispatches the returned step.

The predicate runs before the first `Backoff.next` call. Therefore, `until(clock, Deadline.at(clock.now()), &backoff, predicate)` gives the predicate one observation even though the deadline is already expired. If that observation returns `null`, `Backoff.next` returns `.timeout` and `until` returns `error.Timeout` without incrementing the backoff attempt count.

### Step dispatch

After a null predicate result, `until` dispatches `Backoff.next(deadline, clock)` as follows:

| Step | Required dispatch | State effect owned by `until` |
| --- | --- | --- |
| `.spin` | Call `std.atomic.spinLoopHint()`. | Continue polling. |
| `.yield` | Call `backoff.policy.yield.?()`. | Continue polling. |
| `.sleep(d)` | Call `clock.sleep(d)`. | Continue polling. |
| `.timeout` | Return `error.Timeout`. | Do not invoke the predicate again. |

`Backoff.next` owns the deadline checks, phase state, productive-attempt count, and sleep-duration clipping. `until` MUST NOT duplicate those checks or alter the returned duration.

For `.yield`, `Backoff` guarantees a non-null hook. When `stdx.core.debug.checksEnabled()` is true, `until` MUST assert this invariant before invoking it.

For `.sleep(d)`, `until` passes the exact `Duration` returned by `Backoff.next` to `clock.sleep`. `until` does not independently read the clock, clip the sleep, or inspect a deadline.

For `.timeout`, `until` returns `error.Timeout` through `time.Deadline.TimeoutError`. The caller's backoff retains the productive-attempt count specified by `Backoff.next`.

## Implementation constraints

The implementation MUST call the predicate before `Backoff.next` on every iteration. It MUST dispatch only the four `Backoff.Step` cases stated above. It MUST preserve predicate errors and payloads without consuming a step. It MUST not add a deadline check, clock read, sleep, yield, barrier, allocation, lock, scheduler call, or cancellation behavior beyond the explicit dispatch operations.

## Testing

Tests MUST use a deterministic fake clock and predicates, recording calls, returned values/errors, attempts, yields, and sleep durations.

State-transition tests MUST verify that immediate success consumes no backoff step; each preceding `null` consumes one productive step; predicate errors consume no terminating step; and an expired deadline permits one predicate observation. Dispatch tests MUST verify predicate-before-step order and exact forwarded sleep durations.

Timeout and boundary tests MUST use a bounded fake-clock deadline and a never-ready predicate. They MUST verify that `.timeout` returns `error.Timeout`, does not increment `attempts()`, and does not execute another predicate call. Tests with a deadline equal to the current fake instant distinguish the one-observation progress rule from an implementation that checks the deadline first.

Compile-fail checks MUST cover unsupported predicate returns, `anyerror`, invalid arity, missing `call`, and invalid clock signatures. Return-type checks MUST verify that `PollReturnType` contains `Timeout` and the predicate error set.

Yield tests MUST verify that a configured hook is invoked and a null hook skips the yield phase.
