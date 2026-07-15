# Time timer wheel

Status: Approved.

`stdx.time.TimerWheel` is a single-level, fixed-tick, fixed-capacity hashed
timer wheel keyed by `stdx.time.Deadline`. It stores caller payloads, returns
handles for cancellation and reprioritization, advances explicitly against a
caller-supplied `Instant`, and drains entries whose quantized bucket is due.

`TimerWheel` is a coarse timer mechanism, not a scheduler. It never sleeps,
parks, wakes, resumes, calls callbacks, touches a clock backend, or owns
cancellation policy. It may expire entries later than their original deadline by
less than one configured tick; it must not expire entries early.

## What this spec is

This spec owns:

- `stdx.time.TimerWheel`;
- `TimerWheel.Config`;
- `TimerWheel.Static(T, capacity_items, config)` with inline fixed storage;
- `TimerWheel.Bounded(T, config)` with caller-provided fixed storage;
- a single-level fixed-tick bucket wheel;
- deadline-to-tick quantization;
- finite-horizon `error.OutOfRange` behavior;
- explicit cursor advancement by caller-supplied `Instant`;
- timer handles and stale-handle invalidation;
- insertion, removal, deadline update, next-wake, expired pop, clearing,
  capacity, and invariant-check operations;
- allocation, waiting, capacity, no-mutation-on-error, ownership,
  invalidation, and concurrency contracts;
- required tests.

## What this spec is not

This spec does not own:

- exact deadline ordering; use `docs/specs/time/deadline-queue.md`;
- sleeping, blocking, parking, yielding, spinning on external state, or
  scheduler interaction;
- wake dispatch, fiber resumption, task completion, callback execution, or
  cancellation propagation;
- a replacement for Zig `std.Io.Timeout`, `std.Io.sleep`, `Future`,
  `Executor`, `Runtime`, or a user-facing async API;
- hardware timer programming, clock construction, clock selection, clock
  resolution policy, drift correction, wallclock time, or system time;
- hierarchical or cascading timer wheels;
- overflow wheels, overflow lists, or automatic far-future rearming;
- intrusive timer nodes or multi-membership nodes;
- dynamic allocation, managed storage, unmanaged allocator-taking storage, or
  automatic growth;
- stable FIFO ordering within a bucket;
- priority inversion, fairness, scheduler, or ready-queue policy;
- root promotion of `TimerWheel`.

## Terminology

A **tick** is one configured `tick_ns` interval measured from the wheel origin.
Tick `0` starts at `origin`. Tick `k` starts at `origin + k * tick_ns`.

The **cursor tick** is the greatest tick whose start instant is not later than
the last `Instant` passed to `advanceTo`. The **cursor instant** is the start
instant of the cursor tick.

A **due tick** is the tick at which an entry becomes eligible to pop. Deadlines
that do not fall exactly on a tick boundary are rounded up to the next tick.

An entry is **expired** when its due tick is less than or equal to the cursor
tick and it has not yet been popped or removed.

A **live handle** is a handle returned by `insert` or `insertAssumeCapacity`
whose entry has not been removed, popped, or cleared. A **stale handle** is any
handle whose entry has already been removed, popped, cleared, or whose slot has
been reused with a different generation.

A **wheel horizon** is the set of due ticks accepted by insertion and update:
`current_tick <= due_tick < current_tick + config.slot_count`.

## Public namespace and source ownership

`TimerWheel` lives under `stdx.time`:

```zig
stdx.time.TimerWheel
```

It is not root-promoted:

```zig
stdx.TimerWheel // not exported
```

Source ownership:

```text
src/time.zig
src/time/timer_wheel.zig
test/time/timer_wheel_test.zig
```

`src/time.zig` re-exports:

```zig
pub const timer_wheel = @import("time/timer_wheel.zig");

pub const TimerWheel = timer_wheel.TimerWheel;
```

`src/time.zig` is a thin facade. It contains no logic beyond re-exporting and
aliasing.

## Cross-spec relationships

This spec depends on:

- `docs/specs/time/monotonic.md` for `Instant` and its monotonic nanosecond
  domain;
- `docs/specs/time/deadline.md` for `Deadline` and `Deadline.never`.

This spec composes with but does not own:

- `docs/specs/time/deadline-queue.md`; exact or far-future timers use
  `DeadlineQueue` instead of `TimerWheel`;
- Zig `std.Io.Timeout`; downstream backends may translate `std.Io.Timeout`
  values into wheel entries internally when coarse timing is acceptable, but
  `TimerWheel` does not expose or depend on `std.Io`;
- hardware timer programming; callers use `nextWake()` to decide whether and
  when to arm their backend timer.

## Data structures and representation

The wheel is conceptually a ring of `config.slot_count` buckets. Each live entry
is assigned to exactly one bucket by `due_tick % config.slot_count`. Entries in a
bucket are unordered.

Implementations may use any representation that satisfies the public behavior,
complexity, handle-invalidation, and no-allocation contracts.

The `Handle` integer encoding, slot fields, bucket fields, list layout, struct
field order, and struct padding are not ABI, wire-format, or packed-layout
guarantees. Callers may copy, compare, store, and pass `Handle` values returned
by the wheel. Callers must not fabricate handles or depend on their encoded
integer values.

`Slot` and `Bucket` are public only to provide caller storage to `Bounded(T)`.
Callers must treat slot and bucket contents as implementation-owned after
passing storage to `wrap`.

## Global invariants

Every initialized wheel preserves these invariants:

- `len() <= capacity()`;
- `remaining() == capacity() - len()`;
- `isEmpty() == (len() == 0)`;
- `isFull() == (len() == capacity())`;
- `config.tick_ns > 0`;
- `config.slot_count >= 2`;
- `config.slot_count` is a power of two;
- the cursor tick never decreases;
- `cursor()` is the start instant of the cursor tick;
- every live non-expired entry has a due tick inside the wheel horizon at the
  time it is inserted or updated;
- every live entry has exactly one live handle;
- every live handle identifies exactly one live entry;
- stale handles do not identify any live entry;
- `popExpired()` never pops an entry before its due tick;
- original deadlines are never expired early; non-boundary deadlines expire at
  the next tick boundary after the deadline;
- bucket pop order is unspecified;
- no operation allocates, frees heap memory, waits, sleeps, parks, wakes,
  invokes callbacks, calls a clock backend, touches hidden global state, or
  performs scheduler interaction.

`Deadline.never` is not accepted by the wheel. Insertion or update to
`Deadline.never` returns `error.OutOfRange` and leaves the wheel unchanged.

## API

```zig
pub const TimerWheel = struct {
    pub const Config = struct {
        tick_ns: u64,
        slot_count: usize,
    };

    pub fn Static(
        comptime T: type,
        comptime capacity_items: usize,
        comptime config: Config,
    ) type;

    pub fn Bounded(
        comptime T: type,
        comptime config: Config,
    ) type;
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

pub const Error = error{ Full, OutOfRange };
pub const RangeError = error{ OutOfRange };
```

`Handle` is a strong value type. Native equality compares handle identity. The
encoding is implementation-owned and has no stable ABI meaning.

`Entry` is returned by removal and pop operations. It contains the original
unquantized deadline and payload. It does not contain the handle because the
handle is stale once the entry is removed.

`T` may be any Zig value type, including zero-sized types. Callers who need
stable external object identity store a pointer, index, or other handle as `T`.
The wheel exposes no live payload pointer API.

### `Static(T, capacity_items, config)` returned type

```zig
pub const Self = struct {
    pub const item_capacity = capacity_items;
    pub const wheel_config = config;

    pub const Handle = enum(u128) { _ };
    pub const Entry = struct {
        deadline: time.Deadline,
        item: T,
    };
    pub const Error = error{ Full, OutOfRange };
    pub const RangeError = error{ OutOfRange };

    pub fn init(origin: time.Instant) Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn origin(self: *const Self) time.Instant;
    pub fn cursor(self: *const Self) time.Instant;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn advanceTo(self: *Self, now: time.Instant) void;

    pub fn insert(
        self: *Self,
        deadline: time.Deadline,
        item: T,
    ) Error!Handle;

    pub fn insertAssumeCapacity(
        self: *Self,
        deadline: time.Deadline,
        item: T,
    ) RangeError!Handle;

    pub fn nextWake(self: *const Self) ?time.Instant;

    pub fn popExpired(self: *Self) ?Entry;

    pub fn remove(self: *Self, handle: Handle) ?Entry;

    pub fn updateDeadline(
        self: *Self,
        handle: Handle,
        deadline: time.Deadline,
    ) RangeError!bool;

    pub fn contains(self: *const Self, handle: Handle) bool;

    pub fn assertValid(self: *const Self) void;
};
```

### `Bounded(T, config)` returned type

```zig
pub const Self = struct {
    pub const wheel_config = config;

    pub const Slot = struct { /* implementation-owned fields */ };
    pub const Bucket = struct { /* implementation-owned fields */ };

    pub const Handle = enum(u128) { _ };
    pub const Entry = struct {
        deadline: time.Deadline,
        item: T,
    };
    pub const Error = error{ Full, OutOfRange };
    pub const RangeError = error{ OutOfRange };

    pub fn wrap(
        slots: []Slot,
        buckets: []Bucket,
        origin: time.Instant,
    ) Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn origin(self: *const Self) time.Instant;
    pub fn cursor(self: *const Self) time.Instant;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn advanceTo(self: *Self, now: time.Instant) void;

    pub fn insert(
        self: *Self,
        deadline: time.Deadline,
        item: T,
    ) Error!Handle;

    pub fn insertAssumeCapacity(
        self: *Self,
        deadline: time.Deadline,
        item: T,
    ) RangeError!Handle;

    pub fn nextWake(self: *const Self) ?time.Instant;

    pub fn popExpired(self: *Self) ?Entry;

    pub fn remove(self: *Self, handle: Handle) ?Entry;

    pub fn updateDeadline(
        self: *Self,
        handle: Handle,
        deadline: time.Deadline,
    ) RangeError!bool;

    pub fn contains(self: *const Self, handle: Handle) bool;

    pub fn assertValid(self: *const Self) void;
};
```

`Bounded(T, config).wrap(slots, buckets, origin)` requires
`buckets.len == config.slot_count`. Length mismatch is a caller contract
violation and traps when `core.debug.checksEnabled(.build_mode)` is true.
`slots.len == 0` is valid and produces a zero-entry-capacity wheel.

There is no `enqueue`, `dequeue`, `front`, `back`, `peek`, `peekItem`,
`peekEntry`, `pop`, iterator, live payload pointer, callback, `deinit`,
`clearAndFree`, allocator-taking method, or root export.

## Config validation

`Config.tick_ns` is the fixed tick size in nanoseconds. It must be greater than
zero.

`Config.slot_count` is the number of buckets in the wheel. It must be at least
`2` and a power of two.

Invalid config values are compile errors when `Static` or `Bounded` is
instantiated.

The implementation must reject configs whose accepted due-instant arithmetic
cannot be represented in the `Instant` `u64` nanosecond domain.

## Initialization

`Static(T, N, config).init(origin)` returns an empty wheel with entry capacity
`N`, bucket count `config.slot_count`, and cursor tick `0` at `origin`.

`Bounded(T, config).wrap(slots, buckets, origin)` returns an empty wheel with
entry capacity `slots.len`, bucket count `buckets.len`, and cursor tick `0` at
`origin`.

Initialization performs no allocation and no clock read. For zero-entry-capacity
wheels, initialization succeeds, `isFull()` and `isEmpty()` both return true,
and every `insert` returns `error.Full` unless the deadline is out of range, in
which case it returns `error.OutOfRange` first.

## Capacity and accessors

`len()` returns the number of live entries, including expired entries not yet
popped.

`capacity()` returns `capacity_items` for `Static` and `slots.len` for
`Bounded`.

`remaining()` returns `capacity() - len()`.

`isEmpty()` returns `len() == 0`.

`isFull()` returns `len() == capacity()`.

`origin()` returns the wheel origin passed to `init` or `wrap`.

`cursor()` returns the start instant of the current cursor tick.

These operations are infallible, never allocate, never wait, and never mutate
logical wheel state.

## Tick quantization and range

For a deadline `d`, the wheel computes a due tick against the wheel origin and
current cursor.

If `d.isNever()` is true, the deadline is out of range.

If `d.instant().nanos() <= cursor().nanos()`, the due tick is the current cursor
tick. Inserting or updating to such a deadline makes the entry immediately
expired and available to `popExpired()`.

Otherwise, the due tick is:

```text
ceil((d.instant().nanos() - origin().nanos()) / config.tick_ns)
```

The due instant is:

```text
origin().nanos() + due_tick * config.tick_ns
```

The due tick is accepted only when:

```text
current_tick <= due_tick < current_tick + config.slot_count
```

If the due tick falls outside that horizon, or if computing the due instant
would overflow the `Instant` domain, insertion or update returns
`error.OutOfRange` and leaves the wheel unchanged.

Accepted entries must not expire before their original deadline. They may expire
at their original deadline if it lies exactly on a tick boundary, otherwise at
the next tick boundary. Maximum lateness is less than `config.tick_ns`
nanoseconds.

## Cursor advancement

`advanceTo(now)` advances the wheel cursor to include all ticks whose start
instant is not later than `now`.

It computes:

```text
target_tick = floor((now.nanos() - origin().nanos()) / config.tick_ns)
```

when `now >= origin()`. Passing `now` before `cursor()` is a caller contract
violation and traps when `core.debug.checksEnabled(.build_mode)` is true.
Release builds do not guarantee recovery from backwards time.

If `target_tick == current_tick`, `advanceTo` does not move the cursor.

If `target_tick > current_tick`, `advanceTo` moves the cursor forward and makes
every live entry with `due_tick <= target_tick` expired. It does not return
entries; callers drain them with `popExpired()`.

If the tick jump is greater than or equal to `config.slot_count`, the
implementation may scan every bucket once and move all due entries instead of
iterating one tick at a time. Runtime must remain bounded by
`O(min(ticks_advanced, slot_count) + entries_moved_due)`.

`advanceTo` performs no clock read. Callers read the clock once and pass the
result:

```zig
const now = clock.now();
wheel.advanceTo(now);
while (wheel.popExpired()) |entry| {
    dispatch(entry.item);
}
```

## Insertion

`insert(deadline, item)` adds a live entry keyed by `deadline` and returns a new
live handle.

`insert` checks deadline range before capacity:

1. If `deadline` is `Deadline.never`, outside the wheel horizon, or would
   overflow due-instant arithmetic, return `error.OutOfRange` and leave the
   wheel unchanged.
2. Else if the wheel is full, return `error.Full` and leave the wheel
   unchanged.
3. Else insert the entry into the expired list or the appropriate bucket and
   return its handle.

`insertAssumeCapacity(deadline, item)` performs the same deadline range check
and returns `error.OutOfRange` on range failure. Calling it when `isFull()` is
true and the deadline is in range is a caller contract violation and traps when
`core.debug.checksEnabled(.build_mode)` is true.

The returned handle remains live until the entry is removed by `remove`,
`popExpired`, or `clearRetainingCapacity`. Later insertions do not invalidate
existing live handles.

## Expired pop

`popExpired()` removes and returns one expired entry.

If no expired entry is pending, it returns `null` and leaves the wheel unchanged.

`popExpired()` does not call `advanceTo` and does not read a clock. Callers must
call `advanceTo(now)` before draining time that has passed.

When an entry is popped, its handle becomes stale before `popExpired` returns.
The returned `Entry` owns the removed payload value.

Bucket order and same-tick order are unspecified. Tests and consumers must not
rely on FIFO ordering within a bucket.

## Removal

`remove(handle)` removes the entry identified by a live handle from a bucket or
from the expired list and returns its `Entry`.

If `handle` is stale or was not produced by this wheel instance, `remove`
returns `null` and leaves the wheel unchanged. A fabricated handle that happens
to match a live implementation encoding is outside the caller contract; callers
must use only handles returned by this wheel.

When removal succeeds, the handle becomes stale before `remove` returns. Other
live handles remain valid.

`remove` is the cancellation primitive. It performs no cancellation propagation,
wake dispatch, callback, or scheduler action.

## Deadline update

`updateDeadline(handle, deadline)` changes the deadline of the entry identified
by a live handle.

If `handle` is stale or was not produced by this wheel instance,
`updateDeadline` returns `false` and leaves the wheel unchanged.

If `deadline` is `Deadline.never`, outside the wheel horizon, or would overflow
due-instant arithmetic, `updateDeadline` returns `error.OutOfRange` and leaves
the wheel unchanged.

On success, `updateDeadline` moves the entry to the expired list or target
bucket, preserves the handle's liveness, and returns `true`. Updating to an
earlier deadline, a later deadline, the same deadline, or an already-due deadline
is valid when the new due tick is in range.

`updateDeadline` does not mutate the payload.

## Next wake

`nextWake()` returns a coarse wake instant for the next caller-owned
advance/drain attempt.

It returns `null` when no live entries exist and no expired entries are pending.

If expired entries are pending, it returns `cursor()`.

Otherwise `nextWake()` returns the due instant for an earliest non-empty future
bucket. The returned instant is the bucket's quantized due instant, not
necessarily any entry's original deadline. It may be later than an original
deadline by less than `config.tick_ns` nanoseconds.

`nextWake()` does not arm a timer, sleep, or call a backend. Hardware timer or
scheduler programming is caller-owned.

## Handle containment

`contains(handle)` returns `true` iff `handle` is live in this wheel instance at
the time of the call.

`contains` performs no mutation. It is a convenience check only; in concurrent
programs, callers still need external synchronization around any later mutating
operation.

## Clearing

`clearRetainingCapacity()` removes every live entry and invalidates every live
handle. Capacity, bucket storage, slot storage, origin, and cursor tick are
retained.

It does not return payloads, call destructors, invoke callbacks, wake waiters,
or free memory. Callers that own resources through payload values must remove or
pop entries before clearing if they need to recover payloads.

After clearing, the wheel is empty and accepts new insertions up to the same
capacity and within the current cursor horizon. Handles created before clearing
are stale and must not affect new entries.

## Bucket ordering

The wheel does not guarantee FIFO, LIFO, stable, or deterministic ordering among
entries in the same bucket or among entries that become expired on the same
`advanceTo` call.

Consumers that need fairness or deterministic same-bucket ordering must encode
that policy in their payloads or in a scheduler-owned ready queue after popping
expired entries.

Tests must not assert a specific pop order within a bucket. They must assert
only that all expected entries are returned and that no not-yet-due entry is
returned.

## Handle invalidation and generation reuse

Implementations must prevent stale handles from affecting newly inserted entries
after slot reuse. Slot reuse must change a generation component so a handle
removed from an old occupant does not remove or update a later occupant of the
same slot.

The generation domain must be at least 64 bits. After a slot generation wraps,
stale-handle protection for handles from earlier generations is unspecified.

The following operations invalidate handles:

- `remove(handle)` invalidates `handle` on success;
- `popExpired()` invalidates the popped entry's handle;
- `clearRetainingCapacity()` invalidates every live handle.

The following operations do not invalidate other live handles:

- `advanceTo`;
- `insert`;
- `insertAssumeCapacity`;
- `nextWake`;
- `updateDeadline`;
- `contains`;
- accessors;
- `assertValid`.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `init` | never | never | O(capacity + slot_count) or better | single-owner | none | infallible |
| `wrap` | never | never | O(capacity + slot_count) or better | single-owner | none | asserts on bucket length mismatch |
| accessors | never | never | O(1) | reader under external synchronization | none | infallible |
| `clearRetainingCapacity` | never | never | O(capacity + slot_count) or better | exclusive owner | none | infallible |
| `advanceTo` | never | never | O(min(ticks advanced, slot_count) + entries moved due) | exclusive owner | none | asserts on backwards time |
| `insert` | never | never | O(1) | exclusive owner | none | `OutOfRange`, `Full`; no mutation on error |
| `insertAssumeCapacity` | never | never | O(1) | exclusive owner | none | `OutOfRange`; asserts if full |
| `nextWake` | never | never | O(slot_count) or better | reader under external synchronization | none | infallible |
| `popExpired` | never | never | O(1) | exclusive owner | none | infallible |
| `remove` | never | never | O(1) | exclusive owner | none | infallible; null on stale |
| `updateDeadline` | never | never | O(1) | exclusive owner | none | `OutOfRange`; false on stale; no mutation on failure |
| `contains` | never | never | O(1) | reader under external synchronization | none | infallible |
| `assertValid` | never | never | O(capacity + slot_count) | reader under external synchronization | none | asserts on invariant break |

## Implementation constraints

Implementations must not allocate, free heap memory, call a clock backend, call
scheduler APIs, call user callbacks, access hidden globals, or perform syscalls.

Mutating operations require exclusive ownership of the wheel. The primitive does
not provide internal synchronization. Concurrent callers must serialize
externally.

The primitive performs no atomic operation and establishes no inter-thread
happens-before relationship. Publication of payload contents to another thread
is the caller's synchronization responsibility.

Operations are safe from interrupt or NMI context only when the caller
guarantees exclusive access without blocking and copying `T` is valid in that
context. The primitive itself adds no context-unsafe side effect.

Implementations must not expose live payload pointers. Whether the internal
representation moves bytes is not observable except through returned `Entry`
values.

## Testing

### Config validation

Required tests:

- `tick_ns == 0` is rejected at compile time;
- `slot_count < 2` is rejected at compile time;
- non-power-of-two `slot_count` is rejected at compile time;
- configs whose accepted due-instant arithmetic cannot be represented in the
  `Instant` domain are rejected;

### Construction and capacity

Required tests:

- `Static(T, 0, config).init(origin)` creates an empty full wheel;
- `Static(T, N, config).init(origin)` creates an empty wheel with capacity `N`;
- `Bounded(T, config).wrap(slots, buckets, origin)` uses `slots.len` as entry
  capacity;
- `Bounded(T, config).wrap` traps when `core.debug.checksEnabled(.build_mode)`
  is true and `buckets.len != config.slot_count`;
- `origin()` and `cursor()` both equal the initialization origin;
- `len`, `capacity`, `remaining`, `isEmpty`, and `isFull` track public
  mutations.

### Tick quantization and range

Required tests:

- a deadline at the cursor instant is immediately expired;
- a deadline inside the current tick but after the cursor instant is assigned to
  the next tick and does not expire early;
- a deadline exactly on a future tick boundary expires at that boundary;
- a deadline one nanosecond after a tick boundary expires at the following tick;
- the farthest in-horizon quantized due tick is accepted;
- the first due tick at or beyond `current_tick + slot_count` returns
  `error.OutOfRange` without mutation;
- `Deadline.never` returns `error.OutOfRange` without mutation.

### Insertion and full behavior

Required tests:

- inserting into an empty wheel succeeds and returns a live handle;
- inserting into a full wheel returns `error.Full` without mutation when the
  deadline is in range;
- range validation takes precedence over full capacity;
- `insertAssumeCapacity` succeeds after an explicit capacity check;
- `insertAssumeCapacity` returns `error.OutOfRange` for an out-of-range
  deadline;
- `insertAssumeCapacity` traps when `core.debug.checksEnabled(.build_mode)` is
  true and the wheel is full and the deadline is in range.

### Advancement

Required tests:

- advancing within the same tick does not expire next-tick entries;
- advancing to the exact due tick expires entries assigned to that tick;
- advancing by multiple ticks expires every entry whose due tick is skipped;
- advancing by at least `slot_count` ticks expires all in-horizon live entries;
- backwards `advanceTo` traps when `core.debug.checksEnabled(.build_mode)` is
  true.

### Expired pop

Required tests:

- `popExpired` returns `null` before entries are due;
- due entries pop after `advanceTo`;
- same-bucket entries all pop, with order treated as unspecified;
- popped handles become stale;
- `popExpired` returns `null` after the expired list drains.

### Removal and stale handles

Required tests:

- `remove(live_handle)` removes an active bucket entry;
- `remove(live_handle)` removes an expired pending entry;
- the removed handle becomes stale;
- a second `remove` of the same handle returns `null` and does not mutate;
- after slot reuse, an old handle cannot remove or update the new entry.

### Deadline update

Required tests:

- updating to an earlier in-range deadline moves the entry to the correct
  bucket or expired list;
- updating to a later in-range deadline moves the entry to the correct bucket;
- updating to the same deadline succeeds and preserves the entry;
- updating to an already-due deadline makes the entry poppable;
- updating to `Deadline.never` returns `error.OutOfRange` without mutation;
- updating beyond horizon returns `error.OutOfRange` without mutation;
- updating a stale handle returns `false` and leaves the wheel unchanged;
- a successful update keeps the handle live.

### Next wake

Required tests:

- empty wheel returns `null`;
- expired pending entries return `cursor()`;
- future entries return their quantized due instant;
- `nextWake()` may return an instant later than an original deadline, but by
  less than `config.tick_ns`;
- removing or popping the earliest bucket changes `nextWake()` to the next
  bucket or `null`.

### Clearing

Required tests:

- `clearRetainingCapacity` empties the wheel;
- capacity, origin, and cursor are retained;
- handles live before clearing become stale;
- later insertions work within the retained cursor horizon.

### Model tests

Required randomized model tests compare the wheel against a simple reference
model for:

- insert;
- remove;
- update deadline;
- `advanceTo`;
- `nextWake`;
- `popExpired`;
- clear;
- stale-handle behavior;
- out-of-range deadlines.

The reference model must quantize deadlines to due ticks and treat same-bucket
order as unordered.

### Contract tests

Required tests:

- `Static` and `Bounded` require no allocator and perform no allocation;
- payload type `void` works;
- payload pointer values round-trip through insert/pop/remove;
- no root export `stdx.TimerWheel` exists;
- `assertValid` succeeds after public mutations;
- `assertValid` traps on deliberately corrupted internal state when
  `core.debug.checksEnabled(.build_mode)` is true.

## Usage examples

High-fanout coarse retransmission wheel:

```zig
const config = stdx.time.TimerWheel.Config{
    .tick_ns = 10 * std.time.ns_per_ms,
    .slot_count = 256,
};
const Wheel = stdx.time.TimerWheel.Static(*Retransmit, 8192, config);

var wheel = Wheel.init(clock.now());

_ = try wheel.insert(retransmit_deadline, retransmit);

const now = clock.now();
wheel.advanceTo(now);
while (wheel.popExpired()) |entry| {
    scheduleRetransmit(entry.item);
}
```

Interrupt-driven timer drain:

```zig
fn onTimerInterrupt(now: stdx.time.Instant) void {
    wheel.advanceTo(now);

    while (wheel.popExpired()) |entry| {
        ready_ring.pushBackAssumeCapacity(entry.item);
    }

    if (wheel.nextWake()) |next| {
        programTimer(next);
    } else {
        disarmTimer();
    }
}
```

Bounded caller-provided storage:

```zig
const config = stdx.time.TimerWheel.Config{
    .tick_ns = 1 * std.time.ns_per_ms,
    .slot_count = 128,
};
const Wheel = stdx.time.TimerWheel.Bounded(ConnectionId, config);

var slots: [1024]Wheel.Slot = undefined;
var buckets: [config.slot_count]Wheel.Bucket = undefined;
var wheel = Wheel.wrap(&slots, &buckets, clock.now());

const handle = try wheel.insert(deadline, connection_id);
_ = wheel.remove(handle);
```
