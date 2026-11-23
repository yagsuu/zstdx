# Wait/wake backends and `sync.spin.Backend`

Wait-capable primitives use a caller-supplied backend to separate state
publication from waiting policy. `stdx.sync.spin.Backend` supplies spin-only
waiting.

## Shared wait/wake backend contract

Each primitive supplies its own `State` and `Token` types. A backend declares
an explicit `WaitError` error set, `Backend.wait()`, and `Backend.wakeAll()`.
`error{}` is valid. `anyerror` is not.

The required call shape is:

```zig
backend.wait(state, observed) // WaitError!void
backend.wakeAll(state)       // void
```

Here `state` is a `*const State` identifying the primitive instance, and
`observed` is a `Token` captured by that primitive. Methods can accept the
concrete types or compatible generic parameters.

Primitives store the backend by value. A backend can reference shared resources,
whose ownership and synchronization remain with the caller. The caller MUST
keep the primitive at a stable address during shared use and keep its backend
resources alive until operations and registered waiters have finished.

### `Backend.wait()`

`Backend.wait()` may spin, yield, park, block, sleep, or return spuriously,
according to the backend contract. It must support repeated calls by a waiter.
A successful backend return requests a state recheck. The primitive decides
whether its wait has completed.

A blocking backend MUST prevent a lost wakeup between observing state and
parking. It registers the waiter, then checks
`State.changedSince(observed)`. If the state changed, the backend removes that
registration and returns success instead of parking. Registration, recheck,
and parking MUST coordinate with `Backend.wakeAll()` so a wake after the
recheck cannot leave the waiter parked indefinitely.

The backend defines error meanings, deadlines, and cancellation. Each primitive
specifies error propagation and its state after an error.

### `Backend.wakeAll()`

The primitive publishes an unblocking state transition before calling
`Backend.wakeAll(state)`. The backend MUST make every waiter blocked for that
state instance return. Publication can be visible before wake completion.
Preemption of the publishing caller can delay the wake call.

The backend contract defines allocation, locking, waiting, execution-context
restrictions, scheduler interaction, and supported concurrent callers.
Primitive-specific concurrency requirements still apply. Neither a wake nor
a successful backend wait replaces the primitive's state observation and
memory-ordering guarantees.

## `sync.spin.Backend`

`sync.spin.Backend{}` constructs a zero-sized value with alignment 1.
Values are interchangeable. `Backend.WaitError` is `error{}`.

| Operation | Contract |
| --- | --- |
| `Backend.wait()` | Executes one `std.atomic.spinLoopHint()` and returns success. |
| `Backend.wakeAll()` | Returns immediately. |

Both operations are reentrant, allocation-free, non-blocking O(1) operations.
The caller rechecks readiness. Spin hints are target-dependent.

Interrupt and NMI callers MUST ensure progress can occur while they spin.

## References

- [Spin backend](../../../src/sync/backend/spin.zig)
- [Backend declaration validation](../../../src/sync/backend/impl.zig)
- [Signal](signal.md)
- [Latch](latch.md)
