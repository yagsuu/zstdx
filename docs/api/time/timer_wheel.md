# `time.TimerWheel`

`stdx.time.TimerWheel` stores fixed-capacity payloads with tick-quantized
deadlines and handles for cancellation and rescheduling. Callers advance time
and drain expired entries explicitly. Use [DeadlineQueue](deadline_queue.md)
for exact deadline ordering or deadlines beyond the wheel horizon.

## Configuration and storage

`TimerWheel.Config.tick_ns` is the tick interval in nanoseconds and must be
nonzero. `bucket_count` must be a power of two of at least two.
`(bucket_count - 1) * tick_ns` must fit in `u64`. Invalid configurations fail
at compile time.

| Variant | Construction and capacity |
| --- | --- |
| `TimerWheel.Static(T, count, config)` | `TimerWheel.Static(T, count, config).init(start)` creates an empty wheel with inline storage. `count > 0`. `bound` is the entry capacity. |
| `TimerWheel.Bounded(T, config)` | `TimerWheel.Bounded(T, config).wrap(slots, buckets, start)` initializes borrowed `[]Slot` and `[]Bucket`. `buckets.len` MUST equal `config.bucket_count`. Capacity is `slots.len`. Zero capacity is both empty and full. |

Keep borrowed slices live and exclusive to the wheel.
`Wheel.*` denotes operations shared by both variants.
Payloads enter and leave by value, including zero-sized values.
Callers manage resources referenced by payloads.

## Time and accepted deadlines

`Wheel.origin()` is `start`. Tick `k` starts at
`start.nanos() + k * config.tick_ns`. The initial cursor is tick zero.
`Wheel.cursor()` returns the current tick's start instant.

For a finite deadline at or before the cursor, the due tick is the current
tick. For a later deadline, the due tick is
`ceil((deadline.instant().nanos() - start.nanos()) / config.tick_ns)`.
The accepted horizon is:

```text
current_tick <= due_tick < current_tick + config.bucket_count
```

`Deadline.never`, a due tick outside this horizon, or an unrepresentable due
instant produces `error.OutOfRange`, subject to the insertion precedence below.
Future deadlines round up by less than one tick. Exact tick boundaries have no
rounding error. Late advancement or draining delays delivery.

`Wheel.advanceTo(now)` moves the cursor to the greatest tick start at or before
`now` and makes all entries due at or before that tick eligible to pop.
It does not remove entries. The caller MUST pass `now >= Wheel.cursor()`.
Debug checks assert this requirement. Passing a later instant within the same
tick leaves the cursor unchanged.

`Wheel.popExpired()` removes one eligible entry, or returns `null` without
mutation when none is pending. It uses the existing cursor: call
`Wheel.advanceTo()` to account for elapsed time before draining.
Pop order is unspecified, including among entries with different original
deadlines or due ticks. Each returned `Entry` contains the original,
unquantized `deadline` and stored `item`.

`Wheel.nextWake()` returns `null` when empty, the cursor with pending expired
entries, or the earliest future quantized due instant.

## Insertion, cancellation, and rescheduling

`Wheel.insert(deadline, item)` returns a live handle.
`error.Full` and `error.OutOfRange` leave the wheel unchanged.

Error precedence differs by storage variant:

| Operation | Precedence |
| --- | --- |
| `TimerWheel.Static(T, count, config).insert()` | A full wheel returns `error.Full` before checking the deadline. |
| `TimerWheel.Bounded(T, config).insert()` | An invalid deadline returns `error.OutOfRange` before checking capacity. |

`Wheel.insertAssumeCapacity()` requires available capacity and returns
`error.OutOfRange` for an invalid deadline without mutation.

`Wheel.remove(handle)` cancels a live entry and returns its `Entry`, whether
the entry is future or already expired.

`Wheel.updateDeadline(handle, deadline)` reschedules a live entry, preserving
its payload and handle, and returns true. Due deadlines become immediately
eligible. Future deadlines postpone delivery. Stale handles return false.
An invalid deadline for a live handle returns `error.OutOfRange` without mutation.

## Handles and clearing

Handles belong to the instance and initialization that issued them.
Callers MUST use returned handles without altering their encoding.

`Wheel.contains(handle)` reports whether a handle is live. Successful removal
and pop invalidate the affected handle before returning. A stale same-instance
handle returns `false` from `Wheel.contains()` and `null` from `Wheel.remove()`
without mutation. Insertion, advancement, and updates preserve other live handles.

`Wheel.clearRetainingCapacity()` discards entries and invalidates their handles,
retaining storage, capacity, origin, and cursor. Callers MUST release payload-owned
resources before clearing. Slot generations are 64-bit. Callers MUST retire stale
handles before generation reuse.

`Wheel.len()` includes expired entries not yet removed or popped.
`Wheel.isValid()` checks internal consistency.

## Execution and cost

Operations perform no allocation or waiting. Callers supply time and dispatch
returned payloads, and MUST synchronize conflicting access.

For entry capacity `c`, bucket count `b`, ticks advanced `t`, and entries made
expired `e`:

| Operation | Cost |
| --- | --- |
| `TimerWheel.Static(T, count, config).init()`, `TimerWheel.Bounded(T, config).wrap()`, `Wheel.clearRetainingCapacity()`, `Wheel.isValid()` | O(c + b) |
| `Wheel.advanceTo()` | O(min(t, b) + e) |
| `Wheel.nextWake()` | O(b), or O(1) with pending expired entries |
| Insertion, pop, removal, update, containment, capacity and cursor queries | O(1) |

## References

- [Timer wheels](../../../src/time/timer_wheel.zig)
- [Monotonic time](monotonic.md) and [deadlines](deadline.md)
