# `stdx.concurrent.mpsc.Ring`

`stdx.concurrent.mpsc.Ring` transfers items from multiple producers to one
consumer through a fixed-capacity FIFO ring.

## Variants and initialization

Here, `Ring` denotes either type returned by the factories below.

## What this spec is

This spec owns:

`Ring.init()` requires exclusive access and initializes counters and slot
publication metadata. Initialize the ring in place before use. Reinitialization
discards all queued items without cleanup. Do not copy an initialized ring or
move it after sharing its address. Borrowed slots must remain alive,
address-stable, and exclusive to the ring until all operations finish. Access
slot contents only through ring operations.

The ring does not allocate or destroy payloads. Push and pop copy `T` by value;
pointer payloads retain their aliases. The caller manages referenced resources,
including resources in items discarded by reinitialization.

## Transfer and concurrency

Any number of producer contexts may call `Ring.tryPushBack()` concurrently.
Exactly one consumer context may call `Ring.popFront()` and `Ring.isEmpty()`,
concurrently with the producers.

| Operation | Result and effect |
| --- | --- |
| `Ring.tryPushBack(item)` | Reserves one FIFO position, writes the item, and publishes that position. It returns `error.Full` if the observed reservation distance from head fills capacity, or `error.Contended` if another producer changes tail before its single strong compare-and-swap succeeds. |
| `Ring.popFront()` | Returns and removes one published front item, or returns `null` without mutation when the front position is unpublished. Removal releases capacity for reuse. |

```zig
stdx.concurrent.mpsc
stdx.concurrent.mpsc.Ring
stdx.concurrent.mpsc.Ring.Static
stdx.concurrent.mpsc.Ring.Bounded
```

All slots contribute to usable capacity, including at capacity one. Capacity
includes both published items and unpublished reservations. FIFO order follows
successful reservation order, even when later producers finish publication
first. The consumer cannot skip an unpublished front reservation.

```text
src/concurrent.zig            -- domain facade
src/concurrent/mpsc.zig       -- sub-namespace facade
src/concurrent/mpsc/ring.zig  -- Ring implementation
test/concurrent/mpsc/ring_test.zig
```


## Observations and progress

`Ring.capacity()` returns the fixed slot count and can be called from any
context after initialization. It remains stable until reinitialization.

```zig
const mpsc = stdx.concurrent.mpsc;
```

`Ring.isValid()` requires exclusive or quiescent access. It returns whether
capacity is nonzero and a power of two, and the modular distance from head to
reservation tail is at most capacity.

Push and pop make bounded attempts without retry loops, allocation, sleeping,
or scheduler calls. Push makes at most one reservation compare-and-swap.
Their work is constant in capacity, plus the cost of copying `T`. A producer
can repeatedly lose reservation races; the ring provides no starvation-freedom
guarantee. Retry, backoff, and notification policy belong to the caller.

Producers MUST NOT use `Ring.isEmpty()` to decide whether to signal. Signal
after each successful push unless a stronger caller-owned notification protocol
provides the required wakeups. The ring's release/acquire edges provide payload
visibility; an external signal only notifies the consumer.
When composing a clearable signal with the ring, clear the signal and recheck
with `Ring.popFront()` before waiting.

## Publication and reuse ordering

```zig
pub const Self = struct {
    slots: [item_capacity]Slot = undefined,
    head: stdx.mem.CachePad(std.atomic.Value(usize)) =
        .{ .value = std.atomic.Value(usize).init(0) },
    tail: stdx.mem.CachePad(std.atomic.Value(usize)) =
        .{ .value = std.atomic.Value(usize).init(0) },

    pub const Slot = struct {
        sequence: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        item: T = undefined,
    };
    pub const Error = error{ Full, Contended };
    pub const item_capacity = capacity_items;


## References

    pub fn tryPushBack(self: *Self, item: T) Error!void;
    pub fn popFront(self: *Self) ?T;

    head: stdx.mem.CachePad(std.atomic.Value(usize)) =
    tail: stdx.mem.CachePad(std.atomic.Value(usize)) =
  on distinct cache lines via `stdx.mem.CachePad`, so that a producer's write