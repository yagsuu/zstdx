# `stdx.concurrent.mpsc.Ring`

`stdx.concurrent.mpsc.Ring` transfers items from multiple producers to one
consumer through a fixed-capacity FIFO ring.

## Variants and initialization

Here, `Ring` denotes either type returned by the factories below.

| Factory | Storage and initialization |
| --- | --- |
| `stdx.concurrent.mpsc.Ring.Static(T, count)` | Owns inline slots. `count` must be nonzero and a power of two. Invalid counts fail compilation. `stdx.concurrent.mpsc.Ring.Static(T, count).init()` initializes an empty ring. |
| `stdx.concurrent.mpsc.Ring.Bounded(T)` | Borrows caller-owned `[]Slot`. `Ring.init(slots)` requires a nonempty, power-of-two slice. |

`T` must have nonzero size. Allocate bounded storage as the returned type's `Slot`.

Initialize the ring in place before use. Initialization and reinitialization
require exclusive access. Reinitialization
discards all queued items without cleanup. Do not copy an initialized ring or
move it after sharing its address. Borrowed slots must remain alive,
address-stable, and exclusive to the ring until all operations finish. Access
slot contents only through ring operations.

The ring does not allocate or destroy payloads. Push and pop copy `T` by value.
Pointer payloads retain their aliases. The caller manages referenced resources,
including resources in items discarded by reinitialization.

## Transfer and concurrency

Any number of producer contexts may call `Ring.tryPushBack()` concurrently.
Exactly one consumer context may call `Ring.popFront()` and `Ring.isEmpty()`,
concurrently with the producers.

| Operation | Result and effect |
| --- | --- |
| `Ring.tryPushBack(item)` | Reserves one FIFO position, writes the item, and publishes that position. It returns `error.Full` if the observed reservation distance from head fills capacity, or `error.Contended` if another producer changes tail before its single strong compare-and-swap succeeds. |
| `Ring.popFront()` | Returns and removes one published front item, or returns `null` without mutation when the front position is unpublished. Removal releases capacity for reuse. |

Push errors leave the ring unchanged by that attempt. The caller retains the item.
Successful pop transfers the copied value. Its old slot can be reused.

All slots contribute to usable capacity, including at capacity one. Capacity
includes both published items and unpublished reservations. FIFO order follows
successful reservation order, even when later producers finish publication
first. The consumer cannot skip an unpublished front reservation.

A producer that reserves a position MUST finish publication. A stalled or
abandoned reservation blocks later consumption and can leave the ring full.
Callers MUST ensure required producers can resume. Interrupt-context retries
must not wait for a producer they interrupted.

## Observations and progress

`Ring.isEmpty()` and a `null` pop report an unreadable front. Later items may
already be published and producers may observe `error.Full`. Concurrent progress
can make either availability observation stale.

`Ring.isValid()` requires exclusive or quiescent access. It returns whether
capacity is nonzero and a power of two, and the modular distance from head to
reservation tail is at most capacity.

Push and pop make bounded attempts without retry loops, allocation, sleeping,
or scheduler calls. Push makes at most one reservation compare-and-swap.
Their work is constant in capacity, plus the cost of copying `T`. A producer
can repeatedly lose reservation races. The ring provides no starvation-freedom
guarantee. Retry, backoff, and notification policy belong to the caller.

Producers MUST NOT use `Ring.isEmpty()` to decide whether to signal. Signal
after each successful push unless a stronger caller-owned notification protocol
provides the required wakeups. The ring's release/acquire edges provide payload
visibility. An external signal only notifies the consumer.
When composing a clearable signal with the ring, clear the signal and recheck
with `Ring.popFront()` before waiting.

## Publication and reuse ordering

Reservation uses monotonic ordering. Producers acquire-observe released head
advances before reusing storage. Publication release-orders each payload write.
The consumer acquire-observes publication before copying the item and
release-publishes its head advance after the copy.

Counters and publication tickets wrap using `usize` arithmetic.
Callers MUST preserve ring metadata.

## References

- [MPSC ring](../../../../src/concurrent/mpsc/ring.zig)
