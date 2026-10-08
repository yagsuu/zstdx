# Time deadline queue

Status: Approved.

`stdx.time.DeadlineQueue` is a fixed-capacity priority queue keyed by
`stdx.time.Deadline`. It stores caller payloads, returns handles for
cancellation and reprioritization, and exposes earliest-deadline peek and
expired-pop operations against a caller-supplied `Instant`.

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

## Cross-spec relationships

This spec depends on:

- `docs/specs/time/monotonic.md` for `Instant` and its monotonic nanosecond
  domain;
- `docs/specs/time/deadline.md` for `Deadline`, `Deadline.never`, and the
  `now.afterOrEq(deadline.instant())` expiration boundary.

Exact ordering uses `Deadline.instant().nanos()`. [TimerWheel](timer_wheel.md) provides coarse bucketed timers.

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
`core.debug.checksEnabled()` is true. `slots.len == 0` and
`heap.len == 0` are valid and produce a zero-capacity queue.

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
traps when `core.debug.checksEnabled()` is true.

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

The caller MUST use handles returned by this queue instance. A stale same-instance handle MUST return `null` without mutation. Foreign or fabricated handles are outside the contract; handle encodings do not identify their originating instance.

When removal succeeds, the handle becomes stale before `remove` returns. Other
live handles remain valid.

`remove` is the cancellation primitive. It performs no cancellation propagation,
wake dispatch, callback, or scheduler action.

## Deadline update

`updateDeadline(handle, deadline)` changes the deadline key of the entry
identified by a live handle and returns `true`.

A stale same-instance handle MUST return `false` without mutation.

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

Mutating operations require exclusive ownership of the queue. The primitive does
not provide internal synchronization. Concurrent callers must serialize
externally.

The primitive performs no atomic operation and establishes no inter-thread
happens-before relationship. Publication of payload contents to another thread
is the caller's synchronization responsibility.

Operations are safe from interrupt or NMI context only when the caller
guarantees exclusive access without blocking and copying `T` is valid in that
context. The primitive itself adds no context-unsafe side effect.

The API returns payloads by value and exposes no live payload pointers.

## Testing

Tests MUST use caller-controlled `Instant` values and a reference priority-queue model.

### Capacity and error boundaries

Construction tests MUST cover both storage variants, zero-capacity bounded storage, and enabled length checks. Full-queue tests MUST verify `error.Full` without changes to entries, handles, count, or order.

### Ordering and expiration

Tests MUST insert finite and `Deadline.never` keys and check peek/pop before, at, and after deadlines. A fixed-time drain MUST remove only expired entries. Equal-key checks MUST compare membership/count without assuming order.

### Handle and state transitions

Tests MUST check insertion, removal, reprioritization, clear, and slot reuse, including stale same-instance handles, preservation of other live handles, and no mutation on stale operations.

### Reference-model and contract tests

Mixed insert, remove, update, peek, expired-pop, next-pop, and clear operations MUST match a reference model that treats equal-key order as unordered. Tests MUST cover `void` and pointer payloads and call invariant validation after mutations.
