# `stdx.concurrent.spsc.Ring`

`stdx.concurrent.spsc.Ring` transfers items in FIFO order between one producer
and one consumer through fixed-capacity storage.

## Variants and initialization

Here, `Ring` denotes either type returned by the factories below.

## What this spec is

This spec owns:

- `concurrent.spsc.Ring.Static(T, N)` and `concurrent.spsc.Ring.Bounded(T)`;
- caller-provided `Bounded(T).Slot` storage;
- one-attempt producer enqueue and one-attempt consumer dequeue of published front items;
- cache-line isolation of `head` and `tail` via `mem.CachePad`;
- fixed-capacity, full-capacity, no-mutation-on-error, and pointer-stability contracts;
- atomic slot-publication and slot-release ordering; and
- required unit, model, ordering, and stress tests.

The ring does not allocate or destroy payloads. Push and pop copy `T` by value;
pointer payloads retain their aliases. The caller manages referenced resources,
including resources in items discarded by reinitialization.

## Transfer and concurrency

Exactly one producer context may call `Ring.tryPushBack()`. Exactly one consumer
context may call `Ring.popFront()` and `Ring.isEmpty()`. The producer and consumer
may operate concurrently.

| Operation | Result and effect |
| --- | --- |
| `Ring.tryPushBack(item)` | Publishes one item at the FIFO back, or returns `error.Full` when the observed occupancy fills capacity. A failed attempt stores no item and changes no ring state. |
| `Ring.popFront()` | Returns and removes one published front item, or returns `null` without changing ring state when no item is observed. Successful removal releases the slot for reuse. |

All slots contribute to usable capacity, including at capacity one. A failed
push leaves the caller responsible for the item. A successful pop gives the
caller the returned value; the ring can subsequently overwrite its old slot.

```zig
stdx.concurrent.spsc
stdx.concurrent.spsc.Ring
stdx.concurrent.spsc.Ring.Static
stdx.concurrent.spsc.Ring.Bounded
```

## Observations and diagnostics

`Ring.capacity()` returns the fixed slot count and can be called from any
context after initialization. It remains stable until reinitialization.

`src/concurrent.zig` re-exports:

`Ring.isValid()` requires exclusive or quiescent access. It returns whether
capacity is nonzero and a power of two, and the modular distance from head to
tail is at most capacity.

## Publication and reuse

The producer release-publishes the tail after writing the payload. The consumer
acquire-loads that tail before reading the payload. After copying the item, the
consumer release-publishes the head; the producer acquire-loads the head before
reusing released storage. Each role loads its own counter with monotonic
ordering.

`src/concurrent.zig` is a thin facade. It contains no logic beyond
re-exporting.

Notification and waiting policy belong to the caller. Producers must not use
`Ring.isEmpty()` to decide whether to signal. The ring's release/acquire edges
provide payload visibility; an external signal only notifies the consumer.
When composing a clearable signal with the ring, clear the signal and recheck
with `Ring.popFront()` before waiting.

## References

### `Static(T, capacity_items)` returned type

    head: stdx.mem.CachePad(std.atomic.Value(usize)) =
    tail: stdx.mem.CachePad(std.atomic.Value(usize)) =
    head: stdx.mem.CachePad(std.atomic.Value(usize)) =
    tail: stdx.mem.CachePad(std.atomic.Value(usize)) =
`head` and `tail` are `stdx.mem.CachePad(std.atomic.Value(usize))`. Cache-line
- keep `head` and `tail` in `stdx.mem.CachePad(std.atomic.Value(usize))`;