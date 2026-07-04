# Sync raw spin lock

Status: Approved.

`stdx.sync.RawSpinLock` is the minimum viable mutual-exclusion primitive:
one atomic word, an `acquire()` that spins until it wins, a `release()`
that publishes the exit. No fairness, no queueing, no interrupt policy,
no scheduler awareness, no backoff. It is the raw form; fair and
backoff-aware variants live in sibling specs (`sync.TicketLock`,
`sync.SpinLock`).

`RawSpinLock` is a spinlock, not a mutex. It never yields, never sleeps,
never allocates. Every caller pays for contention in wasted cycles on
the requesting CPU.

## Owned scope

This spec owns:

- `sync.RawSpinLock`, the atomic-word spinlock;
- `sync.RawSpinLock.State`, the two-value state enum;
- `acquire`, `tryAcquire`, and `release` semantics;
- test-and-test-and-set spin strategy on the acquire path;
- ordering contract: acquire on the winning CAS, release on the
  publish store;
- `isHeld` predicate and `assertHeld` debug check under
  `stdx.core.debug.checksEnabled`;
- interaction rules for recursive acquire, interrupt context, and
  sleeping-while-held (all caller responsibility);
- required tests.

## Deferred scope and non-goals

This spec does not own:

- fairness — `sync.TicketLock` addresses that (queued);
- queueing spinlocks (MCS, CLH, K42) — separate specs when consumers
  surface concrete need;
- backoff — `sync.SpinLock` layers `time.Backoff` on top (queued);
- interrupt save/restore — the caller wraps
  `arch.x86_64.Interrupts.disable`/`enable` on x86_64 or the
  equivalent on other targets; `sync → arch` dependency is not
  approved and this spec does not introduce it;
- timeout or deadline composition — callers compose `time.Deadline`
  with `tryAcquire` themselves;
- condition variables, waiter notification, or wait-queue integration;
- reader/writer variants;
- reentrant / recursive locking — recursive acquire is a caller
  contract violation;
- `Guard` / RAII wrapper — Zig idiom is `defer lock.release();`;
- poisoning or tainted state on holder panic;
- lock-holder identity tracking beyond the debug assertion.

## Public namespace

`RawSpinLock` lives under `stdx.sync`:

```zig
stdx.sync.RawSpinLock
stdx.sync.RawSpinLock.State
```

It is not root-promoted:

```zig
stdx.RawSpinLock // not exported
```

Source ownership:

```text
src/sync.zig
src/sync/raw_spin_lock.zig
test/sync/raw_spin_lock_test.zig
```

`src/sync.zig` re-exports:

```zig
pub const raw_spin_lock = @import("sync/raw_spin_lock.zig");

pub const RawSpinLock = raw_spin_lock.RawSpinLock;
```

`src/sync.zig` is a thin facade. It contains no logic beyond re-exporting
and aliasing.

## Approved API

```zig
pub const RawSpinLock = struct {
    state: stdx.sync.AtomicCell(u32),

    pub const State = enum(u32) {
        unlocked = 0,
        locked = 1,
    };

    pub fn init() RawSpinLock;

    pub fn acquire(self: *RawSpinLock) void;
    pub fn tryAcquire(self: *RawSpinLock) bool;
    pub fn release(self: *RawSpinLock) void;

    pub fn isHeld(self: *const RawSpinLock) bool;
    pub fn assertHeld(self: *const RawSpinLock) void;
};
```

There is no `Guard` type, no `withLock` helper, no `acquireIrqSave`, no
`acquireTimeout`, no `tryAcquireN`, and no reader/writer surface. `State`
values are `unlocked = 0` and `locked = 1`; adding a third state value
is a spec break.

## Semantics

### Initialization

`init()` returns a `RawSpinLock` whose state is `unlocked`. The
underlying `AtomicCell(u32)` is initialized to `0`
(`@intFromEnum(State.unlocked)`).

`RawSpinLock` values are safe to `@memset` to zero at bulk-init time
(kernel `bss` clear, arena scrub) — the zero representation is a valid
unlocked lock.

### Acquire

`acquire()` runs the test-and-test-and-set fast path:

```zig
pub fn acquire(self: *RawSpinLock) void {
    while (true) {
        if (self.state.cmpxchgWeakAcquire(
            @intFromEnum(State.unlocked),
            @intFromEnum(State.locked),
        ) == null) return;

        while (self.state.loadMonotonic() != @intFromEnum(State.unlocked)) {
            std.atomic.spinLoopHint();
        }
    }
}
```

Required behavior:

- returns only when the caller holds the lock;
- the winning CAS is acquire-ordered, so all writes released by the
  previous holder are visible on return;
- contended waiters spin on monotonic loads until they observe
  `unlocked`, then retry the CAS;
- never allocates, never yields, never blocks;
- does not touch interrupt state.

### tryAcquire

`tryAcquire()` returns `true` when it wins the CAS on the first try and
`false` otherwise:

```zig
pub fn tryAcquire(self: *RawSpinLock) bool {
    return self.state.cmpxchgStrongAcquire(
        @intFromEnum(State.unlocked),
        @intFromEnum(State.locked),
    ) == null;
}
```

Required behavior:

- returns `true` iff the caller now holds the lock;
- uses strong CAS so a `false` return unambiguously means contention,
  not spurious failure;
- when the CAS succeeds, the ordering is acquire; when it fails, the
  state word is unchanged and no synchronize-with edge is established;
- never spins;
- contention is not an error in the no-mutation-on-error sense — the
  caller anticipated the possibility, so the return type is `bool`.

### Release

`release()` publishes the unlocked state:

```zig
pub fn release(self: *RawSpinLock) void {
    if (stdx.core.debug.checksEnabled(.build_mode)) self.assertHeld();
    self.state.storeRelease(@intFromEnum(State.unlocked));
}
```

Required behavior:

- writes preceding `release()` on the same thread are visible to the
  next `acquire()`/`tryAcquire()` winner under acquire semantics;
- the store is release-ordered;
- under `stdx.core.debug.checksEnabled(.build_mode)`, `release()`
  calls `assertHeld()` before storing; a stray release traps;
- never allocates, never yields, never touches interrupt state;
- calling `release()` without a prior successful `acquire`/`tryAcquire`
  is a caller contract violation. In release builds the state word is
  overwritten with `unlocked` unconditionally; whichever context
  believed it still held the lock now shares the state with any new
  acquirer.

### `isHeld`

`isHeld()` performs a monotonic load and returns whether the state word
equals `locked`:

```zig
pub fn isHeld(self: *const RawSpinLock) bool {
    return self.state.loadMonotonic() == @intFromEnum(State.locked);
}
```

`isHeld` is a snapshot. The observed value may be stale by the time the
caller reads it. Consumers use `isHeld` for diagnostics, invariant
checks, and best-effort logging — not for correctness-critical control
flow.

### `assertHeld`

`assertHeld()` traps if the state word is not `locked` when called.
Runs unconditionally when called. Consumers gate the call under
`stdx.core.debug.checksEnabled(.build_mode)` per `core/debug.md`
convention. `release()` calls it internally under the same gate.

## Ordering contract

`RawSpinLock` provides the classic critical-section ordering:

- the last successful `acquire`/`tryAcquire` synchronizes-with the
  previous `release()` on the same lock;
- writes performed by the previous holder before `release()` are
  visible to the new holder after `acquire()`/`tryAcquire()` returns;
- writes performed by the current holder while the lock is held are
  not visible to any other observer until the holder calls `release()`;
- concurrent `isHeld()` observers see values consistent with monotonic
  ordering on the state word; no synchronize-with edge on `isHeld`.

## Interaction rules

**Recursive acquire is a caller contract violation.** A caller that
invokes `acquire()` while already holding the lock deadlocks in the
spin loop; `assertHeld()` cannot detect the case because the lock does
not track holder identity. Recursive-locking policy is caller-owned;
consumers who need it wrap `RawSpinLock` in a holder-tracking layer.

**Sleeping while holding the lock is a caller contract violation.**
The primitive does not detect it. The caller invites the deadlock.

**Interrupt-context safety is caller-owned.** If code that could be
preempted by an interrupt takes lock `L`, and the interrupt handler
also acquires `L`, the outer path deadlocks. Callers either disable
interrupts around `acquire()` (using
`stdx.arch.x86_64.Interrupts.disable` on x86_64, or the equivalent on
other targets) or ensure interrupt handlers cannot reach `L`. This
spec does not import `arch`; the composition is caller code.

**Release without prior acquire is a caller contract violation** caught
by `assertHeld` under `checksEnabled(.build_mode)` and undefined in
release builds.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `init` | never | never | O(1) | value type | none | infallible |
| `acquire` | never | spins on state word | O(∞) under contention | many callers | acquire on winning CAS | infallible |
| `tryAcquire` | never | never | O(1) | many callers | acquire on success | infallible |
| `release` | never | never | O(1) | single holder | release | asserts under `checksEnabled` |
| `isHeld` | never | never | O(1) | reader | monotonic | infallible |
| `assertHeld` | never | never | O(1) | reader | monotonic | asserts on unheld |

`RawSpinLock` is safe from any execution context including NMI when
paired with the caller's own interrupt discipline. The primitive
performs no allocation, no lock (beyond itself), no syscall, no target
probing.

## std.Io lane

`RawSpinLock` serves lane 2 exclusively: freestanding consumers where
`std.Io` is unavailable. A `std.Io`-integrated lock yields to the
scheduler under contention — that is a different primitive, not this
one.

Not a substitute for `std.Thread.Mutex` in hosted userspace. Hosted
callers who want lock semantics use `std.Thread.Mutex`.

## Examples

Guarded shared counter, freestanding:

```zig
const stdx = @import("stdx");

var lock: stdx.sync.RawSpinLock = .init();
var counter: u64 = 0;

fn record(delta: u64) void {
    lock.acquire();
    defer lock.release();
    counter += delta;
}
```

Non-blocking probe:

```zig
if (lock.tryAcquire()) {
    defer lock.release();
    process();
} else {
    log.debug("busy; skipping", .{});
}
```

Interrupt-safe hv path (x86_64):

```zig
const x86 = stdx.arch.x86_64;

fn withInterruptsOff(lock: *stdx.sync.RawSpinLock, comptime work: fn () void) void {
    x86.Interrupts.disable();
    defer x86.Interrupts.enable();
    lock.acquire();
    defer lock.release();
    work();
}
```

Debug assertion in a diagnostic snapshot:

```zig
fn snapshot(lock: *const stdx.sync.RawSpinLock) Snapshot {
    if (stdx.core.debug.checksEnabled(.build_mode)) {
        lock.assertHeld();
    }
    return .{ .counter = counter };
}
```

## Required tests

Tests live in `test/sync/raw_spin_lock_test.zig`.

Required tests:

- Compile-only: `@sizeOf(RawSpinLock) == @sizeOf(stdx.sync.AtomicCell(u32))`;
  alignment matches;
- Compile-only: `RawSpinLock.State` has exactly `.unlocked` and `.locked`
  tags with backing values `0` and `1`;
- Compile-only: bulk-zero (`@memset` to `0`) of a `RawSpinLock` is a
  valid unlocked lock, checked by round-trip through `isHeld`;
- Runtime: `init()` returns a lock with `isHeld() == false`;
- Runtime: after `acquire()`, `isHeld() == true`; after `release()`,
  `isHeld() == false`;
- Runtime: `tryAcquire()` on unlocked lock returns `true` and takes
  the lock; on locked lock returns `false` and does not modify state;
- Runtime: `release()` traps under `stdx.core.debug.checksEnabled(.build_mode)`
  when called without prior acquire;
- Runtime: `assertHeld()` traps under `stdx.core.debug.checksEnabled(.build_mode)`
  on an unheld lock;
- Model (N-thread stress): N threads each `acquire`, increment a
  shared counter, `release`, in a loop of K iterations. Final counter
  equals `N * K`;
- Model: contended path — one thread holds the lock while `N-1`
  threads spin in `acquire`; after the holder releases, exactly one
  waiter wins and the remainder continue spinning until each has
  acquired and released in turn;
- Ordering (publish-through-lock): thread A writes a paired
  `AtomicCell(u64)` payload with `storeRelease`, then `release()`s the
  lock; thread B `acquire()`s and reads the payload with
  `loadAcquire`; the value written by A is observed by B;
- Non-x86 build compiles the module.

The default host test suite runs the stress test with a modest N and K
to avoid wall-clock flakiness. Contention-fairness is not asserted;
this is a raw spinlock and fairness is explicitly out of scope.

## Open questions

None.
