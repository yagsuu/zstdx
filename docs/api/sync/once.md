# `sync.Once`

`stdx.sync.Once(Backend)` coordinates one successful initialization among concurrent callers.

## Initialization and lifetime

`Once.init(backend)` creates an incomplete initializer and stores the backend by value. Initialize before concurrent use. Do not copy an initialized `Once` or move it after sharing its address. Keep the instance and backend resources alive until all calls and backend accesses finish.

The callback and its typed context are supplied to each call. Neither is stored. Concurrent callers may supply different callbacks. Only the caller that claims initialization executes its callback.

## `Once.call()` and `Once.callChecked()`

| Operation | Callback result | Initialization failure |
| --- | --- | --- |
| `Once.call(Context, work, context)` | `void` | The callback must return normally. |
| `Once.callChecked(Context, WorkError, work, context)` | `WorkError!void` | Restore claimability, wake waiters, and return the callback error unchanged. |

At most one callback runs at a time. After one callback succeeds, initialization remains complete. Later calls return without executing their callbacks. Both operations may share one instance.

`Once.callChecked()` permits later attempts after failure. Rollback does not undo callback writes or establish successful initialization. Callers must make failed attempts safe to retry. Checked callers retry claiming after another callback fails. A `Once.call()` caller that already lost its claim waits for successful initialization. It does not claim again after rollback.

A backend wait error returns unchanged without executing that waiting caller's callback or changing the active claim. Cancellation of a waiter does not cancel initialization. A caller can retry after a wait error.

Successful callback completion release-publishes the done state before `Backend.wakeAll()` runs. Successful waiting callers acquire-observe completion before returning. The initializer's writes are then visible. A caller can observe completion before the winning caller finishes waking waiters.

`Once.isDone()` acquire-observes completion and the successful callback's writes.

## Backend and progress

`Backend` follows the [wait/wake contract](spin.md#shared-waitwake-backend-contract)
with `sync.once.State` and `sync.once.Token`.

Calls recheck state after spurious successful waits. Waiting and wake completion follow backend policy. The primitive adds no allocation. Callback and backend costs remain caller-controlled. There is no fairness or bounded-wait guarantee.

Use a callback and backend safe for the execution context. An interrupt or NMI MUST NOT wait for an initializer whose progress it interrupts. The callback MUST NOT panic or recursively enter the same `Once`, including through other initializers. With debug checks enabled on multithreaded targets, direct same-thread recursion asserts.

## Backend observations

`State.init()` creates an idle state. `State.observe()` returns an acquire snapshot. `Token.isDone()` tests whether that snapshot is complete. `State.isDone()` and `State.changedSince(token)` also acquire-load the state.

`State.changedSince()` compares the complete snapshot, so claims, publication, and rollback invalidate earlier tokens. Every transition advances a wrapping 30-bit generation. A token can compare equal again after a multiple of `2^30` transitions. Backends must keep token lifetimes within that bound.

Claims, publication, and rollback use release ordering. An acquire observation of rollback can observe failed-callback writes, but does not indicate initialization success. State queries may run concurrently with calls. Callers must not modify the state directly.

## References

- [One-time initialization](../../../src/sync/once.zig)
