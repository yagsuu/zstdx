# `stdx.io.poll`

`poll.until()` observes a predicate until it returns a value or error, or the
supplied deadline expires through the caller-owned `time.Backoff`.

## Predicate and clock

The predicate is a zero-argument function or function pointer, or a struct value
or pointer with a receiver-only `call()` method. Its return type is `E!?T`,
where `E` is a concrete error set other than `anyerror`. An empty error set and
`T = void` are valid. Unsupported predicate shapes fail at compile time.

| Predicate result | Polling result |
| --- | --- |
| `null` | Requests another attempt |
| Payload | Returns the payload immediately |
| Error | Returns the error unchanged |

`poll.Result(Predicate)` names `(time.Deadline.TimeoutError || E)!T`.

The clock supplies `now()` returning `time.Instant` and `sleep(duration)`
accepting `time.Duration` and returning `void`. Use a clock compatible with the
deadline's time domain and the [monotonic-clock contract](../time/monotonic.md).
The caller MUST provide exclusive access to the backoff throughout polling.

## Attempts and termination

The predicate runs before each backoff step, including with an expired deadline.

After each `null`, `poll.until()` calls `Backoff.next()` and executes its result:

| Step | Effect |
| --- | --- |
| `.spin` | Executes `std.atomic.spinLoopHint()`, then retries. |
| `.yield` | Calls `backoff.policy.yield.?.hook()`, then retries. |
| `.sleep(duration)` | Calls `clock.sleep(duration)` with the exact returned duration, then retries. |
| `.timeout` | Returns `error.Timeout` without another predicate call. |

[Backoff](../time/backoff.md) controls phase budgets, attempt counting, wait
growth, and deadline clipping. Polling preserves its resulting state.
Termination requires callbacks to return and the clock to reach the deadline
while the predicate remains pending.

## Execution context

The loop performs no allocation or locking itself. Its waiting, side effects,
ordering, and execution-context safety depend on the predicate, clock, and yield
hook. Callers MUST use operations suitable for the calling context and provide
any synchronization required by the observed resource.

## References

- [Polling declarations](../../../src/io/poll.zig)
- [Deadlines](../time/deadline.md)
