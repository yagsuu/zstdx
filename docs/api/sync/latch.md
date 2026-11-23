# `sync.latch`

`stdx.sync.Latch(Backend)` provides one-shot countdown latches. Any number of
waiters can wait for a fixed number of arrivals. Release is sticky. The latch
has no reset or generation counter.

`Latch.*` denotes operations shared by `Latch(Backend).Static(count)` and
`Latch(Backend).Bounded`.

## Variants and construction

| Type or operation | Contract |
| --- | --- |
| `Latch(Backend).Static(count)` | Compile-time count in `1...std.math.maxInt(u32)`. Invalid counts are compile errors. `bound: usize` is the compile-time count. |
| `Latch(Backend).Static(count).init(backend)` | Initializes the pending count to `bound`. |
| `Latch(Backend).Bounded.init(count, backend)` | Accepts a `u32` count and initializes the pending count and `bound: u32` to `count`. Zero is a caller-contract violation and traps when `stdx.core.debug.checksEnabled()` is true. |
| `Latch.capacity()` | Returns the original count as `u32`. Arrivals do not change capacity. |

Both variants store the backend by value. Spin-only latches MUST instantiate
`Latch(sync.spin.Backend)`.

Initialization must finish before concurrent use.
Copying an initialized latch or moving a latch after sharing a pointer
with another execution context is outside the contract.

The caller MUST keep the latch, backend, and referenced backend resources alive
until all operations and registered waiters have finished.

## State and observations

`State` tracks the pending count as a `u32`, with zero indicating released.
The count never increases, wraps, or leaves zero.
`Token` is an `enum(u32)` snapshot. Its queries perform no atomic access.

| Operation | Contract |
| --- | --- |
| `State.init(count)` | Accepts a `u32` count. Zero violates the caller contract and traps when `stdx.core.debug.checksEnabled()` is true. |
| `State.observe()` | Returns a pending-count snapshot as a `Token`. |
| `State.changedSince(token)` | Returns whether the pending count differs from the snapshot. |
| `State.pending()` / `Latch.pending()` | Acquire-observes the pending count. |
| `State.isReleased()` / `Latch.isReleased()` | Acquire-observes whether the count is zero. |

## Arrival and waiting

| Operation | Contract |
| --- | --- |
| `Latch.arrive()` | Decrements a positive pending count once. Non-final arrivals return without backend calls. The unique final arrival publishes zero, then calls `Backend.wakeAll()` for the latch state exactly once. |
| `Latch.wait()` | Acquire-observes release before returning success. If released on entry, returns without calling the backend. Otherwise repeats `Backend.wait()` and state observations until release or an error. |
| `Latch.arrive()` at zero | Violates the caller contract. It traps when debug checks are enabled. In ReleaseFast and ReleaseSmall it leaves zero unchanged, without wrapping or another wake. |

Waiters MUST NOT decrement the counter. Arrivers MUST NOT enter the backend
wait path. Spurious successful backend returns do not complete a wait unless
the latch is observed released.

`Latch.wait()` returns only `Backend.WaitError`. Backend errors propagate
unchanged, without retry or rollback. `Latch.wait()` does not change the count.
Concurrent arrivals can still change or release the latch.

## Concurrency, ordering, and progress

Any number of contexts can call `Latch.arrive()` or `Latch.wait()` concurrently
on the same latch. A context can perform both roles. All observation operations
and `Latch.capacity()` can run concurrently with arrivals and waits.

Each arrival acquires prior arrivals' publications and release-publishes its
preceding writes (`.acq_rel`). State observations have `.acquire` ordering.
An observation of zero, including a successful `Latch.wait()`, MUST make writes
sequenced before every arrival visible to the observing context.
Concurrent accesses outside this protocol require caller-owned synchronization.

Construction and observations take O(1) work. Arrival performs O(1) work plus
compare/exchange retries and, for the final arrival, backend wake work.
Retries can result from peer contention or spurious weak-CAS failure. There is no finite retry bound.
The latch adds no blocking to arrival. Backend wake behavior is
backend-owned. Wait progress depends on the remaining arrivals, scheduling,
and backend progress. There is no finite wait bound or per-caller fairness
guarantee.

`Latch.arrive()` is not safe from NMI or nested-interrupt context. Preemption
between the final CAS and `Backend.wakeAll()` delays wake completion, not release
publication. Parked waiters can remain blocked until the final arriver resumes.
`Latch.wait()` is not safe from NMI with a blocking backend. With
`sync.spin.Backend`, an NMI waiter can spin indefinitely until a non-NMI
arriver completes the countdown.
Callers requiring NMI safety MUST use different primitives.

## Backend obligations

The [shared wait/wake contract](spin.md#shared-waitwake-backend-contract)
applies with `sync.latch.State` and `sync.latch.Token`.
Backend methods must support concurrent latch callers.

Once the pending count changes, it cannot return to a previous token value.
The latch layer performs no heap allocation.

## References

- [Countdown, observation, and wait operations](../../../src/sync/latch.zig)
- [Public integration](../../../src/sync/module.zig)
- [Backend declaration validation](../../../src/sync/backend/impl.zig)
- [Shared backend contract and spin behavior](spin.md)
