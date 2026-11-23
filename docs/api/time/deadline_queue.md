# `time.DeadlineQueue`

`stdx.time.DeadlineQueue` stores fixed-capacity payloads in exact deadline order,
with handles for cancellation and rescheduling. Use [TimerWheel](timer_wheel.md)
for coarse, bounded-horizon timers.

## Storage and lifetime

| Variant | Construction and capacity |
| --- | --- |
| `DeadlineQueue.Static(T, count)` | `DeadlineQueue.Static(T, count).init()` creates an empty queue with inline storage. `count > 0`. `bound` is the capacity. |
| `DeadlineQueue.Bounded(T)` | `DeadlineQueue.Bounded(T).wrap(slots, heap)` initializes borrowed `[]Slot` and `[]usize` of equal length. Capacity is `slots.len`. Zero capacity is both empty and full. |

Keep borrowed slices live and exclusive to the queue.
`Queue.*` denotes operations shared by both variants.
Payloads enter and leave by value, including zero-sized values.
Callers manage resources referenced by payloads.

## Deadlines and removal

Queue order uses `Deadline.instant().nanos()`. Equal deadlines have unspecified
pop order. `Deadline.never` is accepted and sorts after all finite deadlines.

| Operation | Result and effect |
| --- | --- |
| `Queue.insert(deadline, item)` | Returns a live handle, or `error.Full` without mutation. |
| `Queue.insertAssumeCapacity()` | Requires available capacity. |
| `Queue.peekDeadline()` | Returns the earliest deadline, or `null` when empty. |
| `Queue.popExpired(now)` | Removes an earliest entry if `now >= entry.deadline.instant()`. Otherwise returns `null` without mutation. |
| `Queue.popNext()` | Removes an earliest entry regardless of expiration, or returns `null` when empty. |
| `Queue.remove(handle)` | Cancels a live entry and returns its `Entry`. |
| `Queue.updateDeadline(handle, deadline)` | Reschedules a live entry and returns true, preserving its payload and handle. Accepts earlier, later, unchanged, and `Deadline.never` deadlines. |

Removal and pop return an `Entry` containing the stored `deadline` and `item`.
`Deadline.never` expires only at `maxInt(u64)`.

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
Slot generations are 64-bit. Callers MUST retire stale handles before generation reuse.

`Queue.isValid()` checks internal consistency.

## Execution and cost

Operations perform no allocation or waiting. Callers supply time and dispatch
returned payloads, and MUST synchronize conflicting access.

For live length `n` and capacity `c`:

| Operation | Cost |
| --- | --- |
| `DeadlineQueue.Static(T, count).init()`, `DeadlineQueue.Bounded(T).wrap()`, `Queue.isValid()` | O(c) |
| `Queue.clearRetainingCapacity()` | O(n) |
| Insertion, successful removal or pop, changed-deadline update | O(log(n + 1)) |
| Empty or unexpired pop, stale-handle operation, unchanged-deadline update | O(1) |
| Peek, containment, capacity and length queries | O(1) |

## References

- [Deadline queues](../../../src/time/deadline_queue.zig)
- [Monotonic time](monotonic.md) and [deadlines](deadline.md)
