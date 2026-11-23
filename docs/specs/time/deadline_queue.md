# `time.DeadlineQueue`

`stdx.time.DeadlineQueue` stores fixed-capacity payloads in exact deadline order,
with handles for cancellation and rescheduling. Use [TimerWheel](timer_wheel.md)
for coarse, bounded-horizon timers.

## Storage and lifetime

| Variant | Construction and capacity |
| --- | --- |
| `DeadlineQueue.Static(T, count)` | `DeadlineQueue.Static(T, count).init()` creates an empty queue with inline storage; `count > 0`. `bound` is the capacity. |
| `DeadlineQueue.Bounded(T)` | `DeadlineQueue.Bounded(T).wrap(slots, heap)` initializes borrowed `[]Slot` and `[]usize` of equal length. Capacity is `slots.len`; zero capacity is both empty and full. |

Keep borrowed slices live and exclusive to the queue.
`Queue.*` denotes operations shared by both variants.
Payloads enter and leave by value, including zero-sized values.
Callers manage resources referenced by payloads.

## Deadlines and removal

Queue order uses `Deadline.instant().nanos()`. Equal deadlines have unspecified
pop order. `Deadline.never` is accepted and sorts after all finite deadlines.

`Queue.insert(deadline, item)` returns a live handle, or `error.Full` without
mutation. `Queue.insertAssumeCapacity()` requires available capacity.
`Queue.peekDeadline()` returns the earliest deadline, or `null` when empty.

`Queue.popExpired(now)` removes an earliest entry when
`now >= entry.deadline.instant()`, or returns `null` without mutation.
`Deadline.never` expires only at `maxInt(u64)`.

`Queue.popNext()` removes an earliest entry regardless of expiration, or returns
`null` when empty. Both pop operations return an `Entry` containing the stored
`deadline` and `item`.

`Queue.remove(handle)` cancels a live entry and returns its `Entry`.
`Queue.updateDeadline(handle, deadline)` reschedules a live entry and returns
`true`. Updates accept earlier, later, unchanged, and `Deadline.never` deadlines;
they preserve the payload and handle.

## Handles and clearing

Handles belong to the instance and initialization that issued them.
Callers MUST use returned handles without altering their encoding.

`Queue.contains(handle)` reports whether a handle is live. Removal and either
pop invalidate the affected handle before returning, without invalidating other
live handles. A stale same-instance handle produces `false` from
`Queue.contains()` and `Queue.updateDeadline()`, and `null` from
`Queue.remove()`, without mutation.

`Queue.clearRetainingCapacity()` discards all entries and invalidates their handles.
Callers MUST release payload-owned resources before clearing.
Slot generations are 64-bit; callers MUST retire stale handles before generation reuse.

`Queue.len()` counts live entries. `Queue.remaining()` is capacity minus length;
`Queue.isEmpty()` and `Queue.isFull()` test zero length and full capacity.
`Queue.isValid()` returns whether the queue's internal state is consistent.

## Execution and cost

Operations perform no allocation or waiting. Callers supply time and dispatch
returned payloads, and MUST synchronize conflicting access.

For live length `n` and capacity `c`:

| Operation | Cost |
| --- | --- |
| `Static.init()`, `Bounded.wrap()`, `Queue.isValid()` | O(c) |
| `Queue.clearRetainingCapacity()` | O(n) |
| Insertion, successful removal or pop, changed-deadline update | O(log(n + 1)) |
| Empty or unexpired pop, stale-handle operation, unchanged-deadline update | O(1) |
| Peek, containment, capacity and length queries | O(1) |

## References

- [Deadline queues](../../../src/time/deadline_queue.zig)
- [Monotonic time](monotonic.md) and [deadlines](deadline.md)
