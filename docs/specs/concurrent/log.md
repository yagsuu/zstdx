# `stdx.concurrent.EventLog`

`EventLog` stores bounded byte events in an inline ring. Writers drop on
contention and evict oldest whole events when capacity is exhausted.

## Storage and construction

`EventLog.Static(cap).init()` creates an empty ring. Capacity must be between
16 and `maxInt(u32)` bytes at compile time; it need not be a power of two.
`EventLog.Static(cap).capacity` is `cap`, and `max_payload` is `cap - 8`.
Each event consumes eight header bytes plus its payload length.

The ring copies payload bytes; callers keep inputs live through `EventLog.write()`.

`EventLog.clear()` requires exclusive access with no writer or drain active.
It zeroes storage and resets publication and drop counters. Callers MUST reset
all associated cursors after clearing.

## Writing and counters

`EventLog.write(payload)` returns `error.EmptyPayload` for an empty payload and
`error.PayloadTooLarge` above `max_payload`, without changing the log. These
errors precede contention handling.

A valid write makes one ownership attempt. Contention with a writer or drain
returns `error.WriterBusy` and counts one dropped event. Success copies the
entire payload, evicting as many oldest whole events as necessary, counts each
eviction as a drop, and publishes one event. Writes do not wait, spin, allocate,
or call callbacks.

`EventLog.published()` reports successful publications and
`EventLog.dropped()` reports contention drops plus evictions. Both counters wrap
modulo `2^64`. Publication is release-ordered and its query uses acquire ordering;
the drop query and `EventLog.isBusy()` are relaxed snapshots.

## Draining

Each reader owns an `EventLog.Cursor` initialized by `Cursor.init()`.
Cursors read retained events independently; callers MUST serialize use of each cursor.

`EventLog.drain(cursor, sink)` makes one ownership attempt shared with writers.
Contention returns `error.Busy` without output or cursor changes. A successful
drain holds ownership through all sink calls. Concurrent or reentrant writes
therefore return `WriterBusy`; nested drains return `Busy`.

The drain first reports previously unobserved drops with exactly:

```text
... N messages dropped ...\n
```

`N` is the wrapping counter difference. The cursor records that snapshot only
after the marker succeeds. Drops during sink calls are reported by a later
drain.

A fresh cursor starts at the oldest retained event. A cursor whose pending
sequence is no longer retained resumes at the oldest surviving event. A cursor
already at the publication end does not replay events merely because a new
contention drop occurred. Payloads are emitted in publication order, without
headers or added separators. Draining advances the cursor but does not remove
events or free ring capacity.

Sink errors propagate and release ownership. The cursor retains completed payloads
and retries the failing payload. Partial payloads or drop markers can repeat.

## Concurrency and execution context

Ownership acquisition and release use acquire/release ordering. Writers and
drains may race, but a drain excludes all successful writes while it runs.
Sink latency therefore determines how long writers can be rejected.
Callers MUST choose a sink suitable for the drain's execution context.

Writing performs bounded work proportional to copied bytes and evicted events;
draining scans retained events and writes pending output. Both use inline
storage without heap allocation. Interrupt or panic use requires suitable target
atomics and memory. Preempted ownership causes new operations to fail.

`EventLog.isValid()` checks ring structure without acquiring ownership. Callers
MUST quiesce writers and drains before validation. Clearing, moving, or destroying
the value also requires exclusive access.

## References

- [Event log declarations](../../../src/concurrent/log.zig)
- [Scoped diagnostic context](../diag/diagnostic.md)
