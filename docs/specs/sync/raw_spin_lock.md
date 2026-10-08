# Sync raw spin lock

Status: Approved.

`stdx.sync.RawSpinLock` is a single-word spinlock. Acquisition spins without yielding or fairness guarantees. The caller owns interrupt discipline.

## API

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

`State` has `unlocked = 0` and `locked = 1`.

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
    if (stdx.core.debug.checksEnabled()) self.assertHeld();
    self.state.storeRelease(@intFromEnum(State.unlocked));
}
```

Required behavior:

- writes preceding `release()` on the same thread are visible to the
  next `acquire()`/`tryAcquire()` winner under acquire semantics;
- the store is release-ordered;
- when `stdx.core.debug.checksEnabled()` is true, `release()` calls `assertHeld()` before storing and traps if the lock is unlocked;
- the caller MUST release only a lock it successfully acquired. The lock does not track holder identity.

### `isHeld`

`isHeld()` performs a monotonic load and returns whether the state word
equals `locked`:

```zig
pub fn isHeld(self: *const RawSpinLock) bool {
    return self.state.loadMonotonic() == @intFromEnum(State.locked);
}
```

`isHeld` is a snapshot. The observed value can be stale when the caller reads
it. Consumers use `isHeld` for diagnostics, invariant checks, and logging that
does not affect correctness-critical control flow.

### `assertHeld`

When `stdx.core.debug.checksEnabled()` is true, `assertHeld()` MUST assert that the state word is locked. It is a diagnostic check, not proof that the calling context owns the lock.

## Ordering contract

`RawSpinLock` provides the classic critical-section ordering:

- the last successful `acquire`/`tryAcquire` synchronizes-with the
  previous `release()` on the same lock;
- writes performed by the previous holder before `release()` are
  visible to the new holder after `acquire()`/`tryAcquire()` returns;
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
`stdx.arch.x86_64.interrupts.disable` on x86_64, or the equivalent on
other targets) or ensure interrupt handlers cannot reach `L`. This
spec does not import `arch`; the composition is caller code.

Releasing from a context that did not acquire the lock is outside the caller contract. The diagnostic check detects an unlocked word, not wrong-context ownership.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `init` | never | never | O(1) | value type | none | infallible |
| `acquire` | never | spins on state word | O(∞) under contention | many callers | acquire on winning CAS | infallible |
| `tryAcquire` | never | never | O(1) | many callers | acquire on success | infallible |
| `release` | never | never | O(1) | single holder | release | asserts under `checksEnabled` |
| `isHeld` | never | never | O(1) | reader | monotonic | infallible |
| `assertHeld` | never | never | O(1) | reader | monotonic | asserts on unheld |

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
    if (stdx.core.debug.checksEnabled()) {
        lock.assertHeld();
    }
    return .{ .counter = counter };
}
```

## Testing

Tests MUST:

- Verify the single-word representation and unlocked all-zero state.
- Check successful/failed acquisition, release, and held-state observation; failed `tryAcquire` MUST preserve state.
- Isolate enabled assertion failures on releasing/checking an unlocked lock.
- Publish a payload before release and verify visibility to a subsequent acquiring holder.
- Run concurrent guarded increments and verify the exact count.
- Hold the lock while contenders attempt acquisition, then release it and verify completion without assuming fairness.
- Compile for a non-x86 target.
