# Time deadline queue

Status: Approved.

`stdx.time.DeadlineQueue` is a fixed-capacity priority queue keyed by
`stdx.time.Deadline`. It stores caller payloads, returns handles for
cancellation and reprioritization, and exposes earliest-deadline peek and
expired-pop operations against a caller-supplied `Instant`.

`DeadlineQueue` is a mechanism, not a scheduler. It never sleeps, parks, wakes,
resumes, calls callbacks, touches a clock backend, or owns cancellation policy.

## What this spec is

This spec owns:

- `stdx.time.DeadlineQueue`;
- `DeadlineQueue.Static(T, capacity_items)` with inline fixed storage;
- `DeadlineQueue.Bounded(T)` with caller-provided fixed storage;
- queue handles and stale-handle invalidation;
- exact ordering by `Deadline.instant().nanos()`;
- insertion, removal, deadline update, earliest-deadline peek, expired pop,
  earliest pop, clearing, capacity, and invariant-check operations;
- allocation, waiting, capacity, no-mutation-on-error, ownership,
  invalidation, and concurrency contracts;
- required tests.

## What this spec is not

This spec does not own:

- sleeping, blocking, parking, yielding, spinning on external state, or
  scheduler interaction;
- wake dispatch, fiber resumption, task completion, callback execution, or
  cancellation propagation;
- a replacement for Zig `std.Io.Timeout`, `std.Io.sleep`, `Future`,
  `Executor`, `Runtime`, or a user-facing async API;
- hardware timer programming, clock construction, clock selection, clock
  resolution policy, drift correction, wallclock time, or system time;
- intrusive timer nodes or multi-membership nodes;
- dynamic allocation, managed storage, unmanaged allocator-taking storage, or
  automatic growth;
- stable FIFO ordering for equal deadlines;
- priority inversion, fairness, scheduler, or ready-queue policy;
- coarse bucketed timers or cascading wheels;
  `docs/specs/time/timer_wheel.md` owns timer wheels.

## Terminology

A **deadline key** is the unsigned nanosecond value returned by
`deadline.instant().nanos()`.

An entry is **expired at `now`** when
`now.afterOrEq(entry.deadline.instant())` is true. At the exact boundary where
`now == entry.deadline.instant()`, the entry is expired.

A **live handle** is a handle returned by `insert` or `insertAssumeCapacity`
whose entry has not been removed, popped, or cleared. A **stale handle** is any
handle whose entry has already been removed, popped, cleared, or whose slot has
been reused with a different generation.

A **finite clock reading** is any monotonic reading below `maxInt(u64)`, matching
the finite `Instant` domain in `docs/specs/time/deadline.md`.

## Public namespace and source ownership

`DeadlineQueue` lives under `stdx.time`:

```zig
stdx.time.DeadlineQueue
```

Source ownership:

```text
src/time.zig
src/time/deadline_queue.zig
test/time/deadline_queue_test.zig
```

`src/time.zig` re-exports:

```zig
pub const deadline_queue = @import("time/deadline_queue.zig");

pub const DeadlineQueue = deadline_queue.DeadlineQueue;
```

`src/time.zig` is a thin facade. It contains no logic beyond re-exporting and
aliasing.

## Cross-spec relationships

This spec depends on:

- `docs/specs/time/monotonic.md` for `Instant` and its monotonic nanosecond
  domain;
- `docs/specs/time/deadline.md` for `Deadline`, `Deadline.never`, and the
  `now.afterOrEq(deadline.instant())` expiration boundary.

This spec composes with but does not own:

- `docs/specs/io/poll.md`; single-operation poll loops continue to use
  `time.Deadline` and `time.Backoff` directly;
- Zig `std.Io.Timeout`; downstream backends may translate `std.Io.Timeout`
  into queue entries internally, but `DeadlineQueue` does not expose or depend
  on `std.Io`;
- `docs/specs/heaps/indexed-heap.md`; an implementation may use an indexed heap
  substrate, but this spec's public contract is time-specific and does not
  depend on that public heap API;
- `docs/specs/time/timer_wheel.md` for coarse high-fanout timer buckets.

## Data structures and representation

The queue is conceptually a min-priority queue ordered by deadline key.
Implementations may use any representation that satisfies the public behavior,
complexity, handle-invalidation, and no-allocation contracts.

The `Handle` integer encoding, slot fields, heap layout, free-list layout,
struct field order, and struct padding are not ABI, wire-format, or packed-layout
guarantees. Callers may copy, compare, store, and pass `Handle` values returned
by the queue. Callers must not fabricate handles or depend on their encoded
integer values.

`Slot` is public only to provide caller storage to `Bounded(T)`. Callers must
treat slot contents as implementation-owned after passing the storage to
`wrap`.

## Global invariants

Every initialized queue preserves these invariants:

- `len() <= capacity()`;
- `remaining() == capacity() - len()`;
- `isEmpty() == (len() == 0)`;
- `isFull() == (len() == capacity())`;
- every live entry has exactly one live handle;
- every live handle identifies exactly one live entry;
- stale handles do not identify any live entry;
- `peekDeadline()` returns `null` iff the queue is empty;
- when non-empty, `peekDeadline()` returns a deadline whose key is minimal among
  all live entries;
- `popExpired(now)` never pops an entry whose deadline is not expired at `now`;
- `popNext()` removes an entry whose key is minimal among all live entries;
- equal-deadline pop order is unspecified;
- no operation allocates, frees heap memory, waits, sleeps, parks, wakes,
  invokes callbacks, calls a clock backend, touches hidden global state, or
  performs scheduler interaction.

`Deadline.never` is a valid deadline. It sorts by its stored key,
`maxInt(u64)`, after all finite deadlines. A queue containing only
`Deadline.never` entries is non-empty and `peekDeadline()` returns
`Deadline.never`; callers interpret that as no finite timer arm.

## API

```zig
pub const DeadlineQueue = struct {
    pub fn Static(comptime T: type, comptime capacity_items: usize) type;
    pub fn Bounded(comptime T: type) type;
};
```

### Common associated types

Both returned types expose these associated types:

```zig
pub const Handle = enum(u128) { _ };

pub const Entry = struct {
    deadline: time.Deadline,
    item: T,
};

pub const Error = error{Full};
```

`Handle` is a strong value type. Native equality compares handle identity. The
encoding is implementation-owned and has no stable ABI meaning.

`Entry` is returned by removal and pop operations. It contains the removed
entry's deadline and payload. It does not contain the handle because the handle
is stale once the entry is removed.

`T` may be any Zig value type, including zero-sized types. Callers who need
stable external object identity store a pointer, index, or other handle as `T`.
The queue exposes no live payload pointer API.

### `Static(T, capacity_items)` returned type

```zig
pub const Self = struct {
    pub const item_capacity = capacity_items;

    pub const Handle = enum(u128) { _ };
    pub const Entry = struct {
        deadline: time.Deadline,
        item: T,
    };
    pub const Error = error{Full};

    pub fn init() Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn insert(
        self: *Self,
        deadline: time.Deadline,
        item: T,
    ) Error!Handle;

    pub fn insertAssumeCapacity(
        self: *Self,
        deadline: time.Deadline,
        item: T,
    ) Handle;

    pub fn peekDeadline(self: *const Self) ?time.Deadline;

    pub fn popExpired(self: *Self, now: time.Instant) ?Entry;
    pub fn popNext(self: *Self) ?Entry;

    pub fn remove(self: *Self, handle: Handle) ?Entry;

    pub fn updateDeadline(
        self: *Self,
        handle: Handle,
        deadline: time.Deadline,
    ) bool;

    pub fn contains(self: *const Self, handle: Handle) bool;

    pub fn assertValid(self: *const Self) void;
};
```

### `Bounded(T)` returned type

```zig
pub const Self = struct {
    pub const Slot = struct { /* implementation-owned fields */ };

    pub const Handle = enum(u128) { _ };
    pub const Entry = struct {
        deadline: time.Deadline,
        item: T,
    };
    pub const Error = error{Full};

    pub fn wrap(slots: []Slot, heap: []usize) Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn insert(
        self: *Self,
        deadline: time.Deadline,
        item: T,
    ) Error!Handle;

    pub fn insertAssumeCapacity(
        self: *Self,
        deadline: time.Deadline,
        item: T,
    ) Handle;

    pub fn peekDeadline(self: *const Self) ?time.Deadline;

    pub fn popExpired(self: *Self, now: time.Instant) ?Entry;
    pub fn popNext(self: *Self) ?Entry;

    pub fn remove(self: *Self, handle: Handle) ?Entry;

    pub fn updateDeadline(
        self: *Self,
        handle: Handle,
        deadline: time.Deadline,
    ) bool;

    pub fn contains(self: *const Self, handle: Handle) bool;

    pub fn assertValid(self: *const Self) void;
};
```

`Bounded(T).wrap(slots, heap)` requires `slots.len == heap.len`. Length mismatch
is a caller contract violation and traps when
`core.debug.checksEnabled(.build_mode)` is true. `slots.len == 0` and
`heap.len == 0` are valid and produce a zero-capacity queue.

There is no `enqueue`, `dequeue`, `front`, `back`, `peek`, `peekItem`,
`peekEntry`, `pop`, `update`, `cancel`, iterator, live payload pointer,
callback, `deinit`, `clearAndFree`, allocator-taking method, or root export.

## Initialization

`Static(T, N).init()` returns an empty queue with capacity `N`. `N` must be
greater than zero.

`Bounded(T).wrap(slots, heap)` returns an empty queue with capacity
`slots.len`. It initializes the queue's logical state over caller-provided
storage. The caller must not read or write `slots` or `heap` while the queue may
use them.

Initialization performs no allocation and no clock read. A zero-capacity
bounded queue is both empty and full, and every `insert` returns `error.Full`
without mutation.

## Capacity and accessors

`len()` returns the number of live entries.

`capacity()` returns `capacity_items` for `Static` and `slots.len` for
`Bounded`.

`remaining()` returns `capacity() - len()`.

`isEmpty()` returns `len() == 0`.

`isFull()` returns `len() == capacity()`.

These operations are infallible, never allocate, never wait, and never mutate
logical queue state.

## Insertion

`insert(deadline, item)` adds a live entry keyed by `deadline` and returns a new
live handle.

When the queue is full, `insert` returns `error.Full` and leaves the queue
unchanged: length, existing entries, existing handles, and heap order are
unchanged.

`insertAssumeCapacity(deadline, item)` adds a live entry and returns a new live
handle. Calling it when `isFull()` is true is a caller contract violation and
traps when `core.debug.checksEnabled(.build_mode)` is true.

The returned handle remains live until the entry is removed by `remove`,
`popExpired`, `popNext`, or `clearRetainingCapacity`. Later insertions do not
invalidate existing live handles.

Inserting `Deadline.never` is valid.

## Earliest-deadline peek

`peekDeadline()` returns `null` when the queue is empty.

When the queue is non-empty, `peekDeadline()` returns a deadline whose key is
minimal among all live entries. If multiple entries have that minimal key, any
one of their equal deadlines may be returned.

`peekDeadline()` does not expose the payload and does not validate whether the
returned deadline is expired. The caller compares it with its own clock reading
or uses it to arm a backend timer.

## Expired pop

`popExpired(now)` removes and returns one expired entry when the earliest live
entry is expired at `now`.

If the queue is empty, it returns `null`.

If the earliest live entry is not expired at `now`, it returns `null` and leaves
the queue unchanged. Because the earliest entry has the minimal deadline key, no
later entry is expired when the earliest entry is not expired.

An entry is expired at `now` when:

```zig
now.afterOrEq(entry.deadline.instant())
```

At the exact boundary, the entry pops. This matches `Deadline.expired`.

When an entry is popped, its handle becomes stale before `popExpired` returns.
The returned `Entry` owns the removed payload value.

Callers that need to drain all expired entries read the clock once and loop:

```zig
const now = clock.now();
while (queue.popExpired(now)) |entry| {
    dispatchTimeout(entry.item);
}
```

`popExpired` never calls `clock.now()` itself.

## Earliest pop

`popNext()` removes and returns one entry whose deadline key is minimal among
all live entries. It ignores expiration and never reads a clock.

`popNext()` returns `null` when the queue is empty.

When an entry is popped, its handle becomes stale before `popNext` returns. The
returned `Entry` owns the removed payload value.

Callers that own resources through `T` and need to recover payloads before
clearing must drain with `popNext()` before `clearRetainingCapacity()`.

## Removal

`remove(handle)` removes the entry identified by a live handle and returns its
`Entry`.

If `handle` is stale or was not produced by this queue instance, `remove`
returns `null` and leaves the queue unchanged. A fabricated handle that happens
to match a live implementation encoding is outside the caller contract; callers
must use only handles returned by this queue.

When removal succeeds, the handle becomes stale before `remove` returns. Other
live handles remain valid.

`remove` is the cancellation primitive. It performs no cancellation propagation,
wake dispatch, callback, or scheduler action.

## Deadline update

`updateDeadline(handle, deadline)` changes the deadline key of the entry
identified by a live handle and returns `true`.

If `handle` is stale or was not produced by this queue instance,
`updateDeadline` returns `false` and leaves the queue unchanged.

A successful update preserves the handle's liveness. Updating to an earlier
deadline, a later deadline, the same deadline, or `Deadline.never` is valid.

`updateDeadline` does not mutate the payload.

## Handle containment

`contains(handle)` returns `true` iff `handle` is live in this queue instance at
the time of the call.

`contains` performs no mutation. It is a convenience check only; in concurrent
programs, callers still need external synchronization around any later mutating
operation.

## Clearing

`clearRetainingCapacity()` removes every live entry and invalidates every live
handle. Capacity and caller-provided storage are retained.

It does not return payloads, call destructors, invoke callbacks, wake waiters,
or free memory. Callers that own resources through payload values must drain
with `popNext()` before clearing.

After clearing, the queue is empty and accepts new insertions up to the same
capacity. Handles created before clearing are stale and must not affect new
entries.

## Equal-deadline ordering

The queue does not guarantee FIFO, LIFO, stable, or deterministic ordering among
entries whose deadline keys are equal.

## Handle invalidation and generation reuse

Implementations must prevent stale handles from affecting newly inserted entries
after slot reuse. Slot reuse must change a generation component so a handle
removed from an old occupant does not remove or update a later occupant of the
same slot.

The generation domain must be at least 64 bits. After a slot generation wraps,
stale-handle protection for handles from earlier generations is unspecified.

The following operations invalidate handles:

- `remove(handle)` invalidates `handle` on success;
- `popExpired(now)` invalidates the popped entry's handle;
- `popNext()` invalidates the popped entry's handle;
- `clearRetainingCapacity()` invalidates every live handle.

The following operations do not invalidate other live handles:

- `insert`;
- `insertAssumeCapacity`;
- `peekDeadline`;
- `updateDeadline`;
- `contains`;
- accessors;
- `assertValid`.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `init` | never | never | O(capacity) or O(1) | single-owner | none | infallible |
| `wrap` | never | never | O(capacity) or O(1) | single-owner | none | asserts on storage length mismatch |
| accessors | never | never | O(1) | reader under external synchronization | none | infallible |
| `clearRetainingCapacity` | never | never | O(n) or better | exclusive owner | none | infallible |
| `insert` | never | never | O(log n) | exclusive owner | none | `Full` with no mutation |
| `insertAssumeCapacity` | never | never | O(log n) | exclusive owner | none | asserts if full |
| `peekDeadline` | never | never | O(1) | reader under external synchronization | none | infallible |
| `popExpired` | never | never | O(log n) when popping; O(1) when not expired | exclusive owner | none | infallible |
| `popNext` | never | never | O(log n) | exclusive owner | none | infallible |
| `remove` | never | never | O(log n) for live handle; O(1) for stale handles | exclusive owner | none | infallible; null on stale |
| `updateDeadline` | never | never | O(log n) for live handle; O(1) for stale handles | exclusive owner | none | infallible; false on stale |
| `contains` | never | never | O(1) | reader under external synchronization | none | infallible |
| `assertValid` | never | never | O(n) | reader under external synchronization | none | asserts on invariant break |

`n` is `len()`.

## Implementation constraints

Implementations must not allocate, free heap memory, call a clock backend, call
scheduler APIs, call user callbacks, access hidden globals, or perform syscalls.

Mutating operations require exclusive ownership of the queue. The primitive does
not provide internal synchronization. Concurrent callers must serialize
externally.

The primitive performs no atomic operation and establishes no inter-thread
happens-before relationship. Publication of payload contents to another thread
is the caller's synchronization responsibility.

Operations are safe from interrupt or NMI context only when the caller
guarantees exclusive access without blocking and copying `T` is valid in that
context. The primitive itself adds no context-unsafe side effect.

The implementation must not move payloads during heap maintenance in any way
that exposes a live payload pointer because the API exposes no live payload
pointers. Whether the internal representation moves bytes is not observable
except through returned `Entry` values.

## Testing

Testing MUST use caller-controlled `Instant` values and a reference priority-queue model. This method verifies queue behavior without a clock backend, allocator, scheduler, or callback.

### Capacity and error boundaries

Construction tests cover static and bounded storage, including zero-capacity bounded queues and debug storage-length validation. Full-queue tests verify `error.Full` and no mutation of length, entries, handles, or ordering; they also verify the checked and assume-capacity insertion contracts. These tests prove capacity and no-mutation-on-error requirements.

### Ordering and expiration

Tests insert finite and `Deadline.never` keys, then observe `peekDeadline`, `popNext`, and `popExpired` before, at, and after a deadline. Drain tests hold one `now` value constant and verify that only expired entries leave the queue. Equal-key tests compare membership and count rather than order. These tests prove minimum-key selection, the inclusive expiration boundary, sentinel ordering, and intentionally unspecified equal-key order.

### Handle and state transitions

Tests exercise insertion, removal, reprioritization, clearing, stale-handle queries, and slot reuse. They verify each stated invalidation boundary, preservation of other live handles, payload ownership on removal, and no mutation for stale handles. These transitions prove generation protection and handle lifetime.

### Reference-model and contract tests

Randomized sequences of insert, remove, update, peek, expired pop, next pop, and clear compare observable state with a reference model that treats equal-key order as unordered. Contract tests verify allocator independence, `void` and pointer payloads, absence of the root export, and invariant checking after public mutations and deliberate corruption. Together these tests prove ordering, capacity, payload, representation, and invariant contracts across long operation sequences.
