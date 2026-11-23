# `sync.Signal`

`stdx.sync.Signal.Manual(Backend)` provides a sticky manual-reset notification.
A set signal remains set until cleared; successful waits do not consume it.

`Manual.*` below denotes operations on `Signal.Manual(Backend)`.

## Construction and lifetime

`Signal.Status` has values `.unset` and `.set`.
`Signal.State.init(initial)` constructs state with that status.
`Signal.Manual(Backend).init(initial, backend)` constructs a signal and stores
the backend by value. Initialization must finish before concurrent use.

Callers MUST NOT copy an initialized signal or move it after sharing a pointer
with another execution context. The caller MUST keep the signal alive until
all operations and registered waiters have finished.

The [shared wait/wake backend contract](spin.md#shared-waitwake-backend-contract)
applies with `Signal.State` and `Signal.Token`. `Manual.WaitError` is
`Backend.WaitError`. Backend resources, execution contexts, and supported
waiter concurrency follow that contract and the selected backend.

## Observations and tokens

`Signal.State` stores status and a wrapping generation in one atomic
`usize`-sized word. `Signal.Token` is an `enum(usize)` snapshot.

| Operation | Contract |
| --- | --- |
| `Signal.State.observe()` | Acquire-loads state and returns a token. |
| `Signal.State.changedSince(token)` | Acquire-loads state and returns whether the current word differs from the token. |
| `Signal.State.isSet()` / `Manual.isSet()` | Acquire-loads state and returns whether it is set. |
| `Signal.Token.isSet()` | Returns the captured status without an atomic access. |
| `Manual.stateRef()` | Borrows a const pointer to the signal state for backend observation; the pointer follows the signal lifetime. |

These observations are infallible, allocation-free, non-waiting O(1)
operations.

Each status change increments the generation modulo
`2^(@bitSizeOf(usize) - 1)`. Redundant sets and clears leave the entire word
unchanged. A set/clear cycle normally changes the token even though the
status returns to its previous value. A positive multiple of
`2^(@bitSizeOf(usize) - 1)` transitions can reproduce the entire token.
Change detection is reliable only when fewer than that many transitions
occur between observation and comparison.

## Notification and waiting

| Operation | Contract |
| --- | --- |
| `Manual.set()` | Release-publishes an unset-to-set transition, then calls `Backend.wakeAll()` for this state once. If already set, leaves state unchanged and makes no backend call. |
| `Manual.clear()` | Release-publishes a set-to-unset transition. If already unset, leaves state unchanged. Makes no backend call. |
| `Manual.wait()` | Acquire-observes set before returning success. If set on entry, bypasses the backend. Otherwise calls `Backend.wait()` with an unset snapshot and rechecks state after each successful return. Does not clear state. |

`Manual.set()` and `Manual.clear()` are infallible.

`Manual.wait()` propagates backend errors unchanged without retry or state
mutation. Concurrent setters and clearers can change state before it returns.

## Concurrency, publication, and progress

Setters, clearers, and observers can run concurrently. The last successful
status transition determines the level. Multiple waiters are valid when the
backend supports them. A concurrent clear can remove the set level before a
woken waiter observes it; a wake alone does not guarantee wait success.

Status transitions have `.release` ordering; observations and failed
compare/exchange reloads have `.acquire` ordering. A wait that observes a set
transition acquires writes published by that transition. A redundant
`Manual.set()` publishes no new transition and provides no new release.

For queue or ring notifications, the paired data structure owns data
publication. Producers call `Manual.set()` after publishing data. The
consumer drains published data, clears the signal, then rechecks the data
structure before waiting. Callers must coordinate ownership of clearing.

Preemption after publication can delay wake completion.
Construction takes O(1) work. Set and clear perform O(1) work plus
compare/exchange retries; set can also perform backend wake work. Contention
and spurious weak-CAS failures have no finite retry bound or per-caller
fairness guarantee. Wait progress depends on signal transitions, scheduling,
and backend progress; waits have no finite bound.

The signal layer performs no heap allocation. Backend wait and wake costs
and execution-context restrictions remain backend-owned. A spin backend does
not make waiting safe when progress requires an interrupted or preempted
producer to resume.

## References

- [Signal declarations and operations](../../../src/sync/signal.zig)
- [Shared backend contract and spin behavior](spin.md)
