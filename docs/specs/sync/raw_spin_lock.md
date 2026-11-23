# `sync.RawSpinLock`

`stdx.sync.RawSpinLock` provides non-recursive mutual exclusion with busy waiting.

## Initialization and lifetime

`RawSpinLock.init()` creates an unlocked lock. An all-zero representation is also a valid unlocked lock at initialization.

Initialize before concurrent use. Keep the lock at a stable address while shared or held. Do not copy, reset, or destroy a live lock. Preserve the alignment required by its atomic `u32` storage.

## Acquisition and release

| Operation | Result and ordering |
| --- | --- |
| `RawSpinLock.acquire()` | Spins until the caller owns the lock. Successful acquisition has acquire ordering. |
| `RawSpinLock.tryAcquire()` | Makes one strong compare-and-exchange attempt. True grants ownership with acquire ordering; false leaves the lock unchanged. |
| `RawSpinLock.release()` | Release-stores the unlocked state. Only the acquiring thread may release the lock. |
| `RawSpinLock.isLocked()` | Returns a monotonic diagnostic snapshot. |

Acquisition compare-and-exchange uses acquire ordering on success and failure.
Only successful acquisition grants access to protected data. Writes before
release become visible to a subsequent successful acquisition.

Operations allocate no memory and do not sleep, yield, or change interrupt state. `RawSpinLock.acquire()` has no timeout, cancellation, fairness, or bounded-wait guarantee. Other operations perform a fixed number of atomic accesses.

## Execution context

The holder MUST NOT sleep while holding the lock or recursively acquire it. Callers manage scheduling and interrupt discipline so the holder can run to release.

An interrupt or NMI MUST NOT spin on a lock held by the context it interrupts. Callers must prevent that overlap or use `RawSpinLock.tryAcquire()` with a safe failure path.

## References

- [Raw spin lock](../../../src/sync/raw_spin_lock.zig)
