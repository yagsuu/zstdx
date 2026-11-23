# `sync.Rendezvous`

`stdx.sync.Rendezvous(Backend)` is a reusable barrier that completes each generation after a fixed number of arrivals.

## Variants and lifetime

Here, `Rendezvous` denotes either constructed variant.

| Variant | Construction | Capacity |
| --- | --- | --- |
| `Rendezvous(Backend).Static(count)` | `Rendezvous(Backend).Static(count).init(backend)` | Compile-time `count`, exposed as `bound`; `1..maxInt(u32)`. |
| `Rendezvous(Backend).Bounded` | `Rendezvous(Backend).Bounded.init(count, backend)` | Runtime `u32` count greater than zero. |

Construction starts generation zero with the full capacity pending and stores the backend by value. Initialize before concurrent use. Do not copy an initialized rendezvous or move it after sharing its address. Keep the instance and backend resources alive until all arrivals and backend accesses finish.

## `Rendezvous.arrive()`

Each call commits one arrival to the current generation. Non-final callers wait until that generation changes. The final caller atomically restores the full pending count and advances the generation, then calls `Backend.wakeAll()` without entering the wait path. Capacity one completes every arrival.

Generation publication precedes wake completion. Other callers may observe completion and begin the next generation before the final caller returns from `Backend.wakeAll()`.

A backend wait error returns unchanged after the arrival has committed. The arrival remains counted; the error does not cancel the generation or remove a participant from future generations. A retry is another arrival, potentially in the same generation. The caller must coordinate recovery with the other participants.

The barrier counts arrivals without participant identity or thread affinity. Callers must arrange the intended number of arrivals per generation and synchronize accesses between generations. Readers must finish using a generation's payload before a later generation overwrites it.

Every completed generation restores the original capacity.

## Ordering and observations

Every committed arrival has acquire-release ordering. Successful completion makes writes before all arrivals in that generation visible to its completing participants. Non-final callers acquire-observe generation completion before successful return. A wait error does not establish completion.

`Rendezvous.pending()` acquire-loads the remaining arrivals; valid state never exposes zero. `Rendezvous.generation()` acquire-loads the wrapping `u32` generation. Separate queries need not describe the same instant. `Rendezvous.capacity()` returns the fixed capacity. Queries may run concurrently with arrivals.

`Rendezvous.stateRef()` borrows the state for backend observation and remains valid only while the instance remains alive at the same address. `State.observe()` returns an acquire snapshot whose `Token.pending()` and `Token.generation()` describe one instant. `State.pending()` and `State.generation()` are acquire queries.

`State.changedSince(token)` acquire-loads and compares generations only. A pending-count decrement does not invalidate a token. Generation wrap can hide a multiple of `2^32` completions; backends must keep token lifetimes within that bound. `State.init(count)` requires a nonzero count. Callers must not modify live state directly.

## Backend and execution context

`Backend` follows the [wait/wake contract](spin.md#shared-waitwake-backend-contract)
with `sync.rendezvous.State` and `sync.rendezvous.Token`.

`Rendezvous.arrive()` tolerates spurious successful waits by checking the generation again. Waiting and wake completion follow backend policy. The primitive adds no heap allocation. Contention retries and waiting have no fixed bound or fairness guarantee.

Use a backend safe for the calling context, and ensure every required participant can progress. `Rendezvous.arrive()` MUST NOT run in NMI or nested-interrupt context.

`Static(0)` is a compile-time error, matching the `BitSet.Static(0)` rule in
`docs/specs/bits/set/static.md`. `Static(capacity_parties)` with
## References

- [Reusable rendezvous](../../../src/sync/rendezvous.zig)
