# `stdx.concurrent.spsc.Ring`

`stdx.concurrent.spsc.Ring` transfers items in FIFO order between one producer
and one consumer through fixed-capacity storage.

## Variants and initialization

Here, `Ring` denotes either type returned by the factories below.

| Factory | Storage and initialization |
| --- | --- |
| `stdx.concurrent.spsc.Ring.Static(T, count)` | Owns inline slots. `count` must be nonzero and a power of two. Invalid counts fail compilation. `stdx.concurrent.spsc.Ring.Static(T, count).init()` initializes an empty ring. |
| `stdx.concurrent.spsc.Ring.Bounded(T)` | Borrows caller-owned `[]Slot`. `Ring.init(slots)` requires a nonempty, power-of-two slice. |

`T` must have nonzero size. Allocate bounded storage as the returned type's `Slot`.

Initialize the ring in place before use. Initialization and reinitialization
require exclusive access. Reinitialization discards all queued items without
cleanup. Do not copy an initialized ring or move it after sharing its address.
Borrowed slots must remain alive, address-stable, and exclusive to the ring
until all operations finish. Access slot contents only through ring operations.

The ring does not allocate or destroy payloads. Push and pop copy `T` by value.
Pointer payloads retain their aliases. The caller manages referenced resources,
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
caller the returned value. The ring can subsequently overwrite its old slot.

Transfer operations take O(1) work plus copying `T`, without retry loops,
allocation, or waiting. A stalled consumer can leave the ring full.

## Observations and diagnostics

`Ring.isEmpty()` reports consumer-side availability. A concurrent push can make
an empty observation stale. A concurrent pop can make `error.Full` stale.

`Ring.isValid()` requires exclusive or quiescent access. It returns whether
capacity is nonzero and a power of two, and the modular distance from head to
tail is at most capacity.

## Publication and reuse

The producer release-publishes the tail after writing the payload. The consumer
acquire-loads that tail before reading the payload. After copying the item, the
consumer release-publishes the head. The producer acquire-loads the head before
reusing released storage. Each role loads its own counter with monotonic
ordering.

Counters wrap using `usize` arithmetic. Callers MUST preserve ring metadata.

Notification and waiting policy belong to the caller. Producers must not use
`Ring.isEmpty()` to decide whether to signal. The ring's release/acquire edges
provide payload visibility. An external signal only notifies the consumer.
When composing a clearable signal with the ring, clear the signal and recheck
with `Ring.popFront()` before waiting.

## References

- [SPSC ring](../../../../src/concurrent/spsc/ring.zig)
