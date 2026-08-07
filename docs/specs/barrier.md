# Barrier overview

Status: Approved.

`stdx.barrier` owns shared ordering vocabulary and documentation requirements for synchronization, concurrent containers, MMIO, DMA, and architecture-specific specifications. This specification defines no runtime barrier declarations.

## What this spec is

This spec defines the `stdx.barrier` namespace reservation, shared ordering terms, and the required ordering, waiting, and testing contracts of dependent specifications.

## What this spec is not

This spec does not define compiler, CPU, IO, MMIO, DMA, or cache-maintenance barrier functions; target-specific instruction selection; volatile or MMIO register wrappers; futex, wait-queue, scheduler, interrupt, or preemption policy; or a proof of hardware ordering by ordinary unit tests. It does not replace Zig atomic ordering names.

## Terminology

A **publisher** writes ordinary data and then performs a release operation that makes the data observable through a synchronization object.

An **acquirer** performs an acquire operation on the synchronization object. When the acquirer observes the publisher's released state, the acquirer may read the published ordinary data.

A **published slot** is a container slot whose contents are visible to a consumer because the producer completed the release publication step for that slot.

A **free slot** is a container slot whose previous contents are no longer live and whose metadata has been release-published as available for a producer.

A **reservation** is ownership of a future mutation point before publication. A reserved slot is not a published slot. Consumers MUST NOT read reserved, unpublished data.

A **doorbell** is notification that a consumer should recheck state. A doorbell is not a data-visibility proof. The data structure owns its acquire and release ordering.

A **sticky signal** is a level-triggered doorbell state. It remains set until an explicit clear.

An **edge signal** or **pulse** is a transient notification with no retained state. It can lose a wake when the edge races with waiter enrollment.

A **wait** is an operation that may block, sleep, park, yield, or spin while waiting for state to change.

A **backend** is caller-supplied behavior that a primitive uses for target- or scheduler-specific work.

## Public namespace and source ownership

This overview defines no public Zig declarations. A concrete barrier API requires a dedicated specification and MAY own `src/barrier.zig`, `src/barrier/*.zig`, and `test/barrier/*_test.zig`.

## Cross-spec relationships

Concurrent and synchronization primitive specifications depend on this specification for ordering vocabulary. A specification that needs ordering before a concrete barrier API exists MUST name Zig atomic orderings directly.

## Global invariants

- A signal or wake operation does not make payload bytes visible by itself.
- The queue, ring, lock, or other data structure MUST define its own atomic publication protocol.
- A public API MUST state whether it waits and whether a backend owns the waiting behavior.
- A specification that approves a backend MUST define its required functions, error set, allocation behavior, waiting behavior, and lost-wakeup rules.
- A reusable synchronization primitive MUST NOT use a pulse-only wait protocol.

## API

This specification defines no executable operations.

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| vocabulary only | none | none | none | none | documentation-only | defines terms only |

## Implementation constraints

### Atomic ordering

Specifications MUST use Zig ordering names at operation sites:

- `.monotonic` for atomicity without cross-location ordering;
- `.acquire` when later loads or stores must observe a release publication;
- `.release` when prior loads or stores must become visible to an acquire;
- `.acq_rel` when one operation both acquires prior state and publishes later state;
- `.seq_cst` only when the specification requires a single total order and justifies its cost.

A concurrent primitive specification MUST identify the operation that publishes data and the operation that acquires it. Implementation comments MUST be adjacent to the atomic operation that enforces the contract.

### Notification and visibility

Consumers MUST tolerate redundant and spurious notifications. A notification may mean only that state might have changed.

### Waiting and lost wakeups

A wait-capable primitive specification MUST define how a waiter avoids the race in which the waiter observes a false condition, a producer changes the condition and sends a wake, and the waiter enrolls after the wake and waits indefinitely.

An approved protocol MUST use at least one of these mechanisms:

- backend enrollment followed by a mandatory condition recheck before parking;
- generation or token comparison that detects state changes between observation and enrollment;
- a target primitive with documented atomic wait semantics.

## Testing

A concrete barrier API specification MUST require target-gated tests that verify API shape, compile availability, and documented fallback behavior. These tests prove the portable API contract and target selection; they MUST NOT claim to prove CPU, device, or DMA ordering.

A concurrent-data-structure specification MUST require deterministic model tests when practical and stress tests that exercise contention. Model tests verify permitted state transitions and outcomes. Stress tests provide coverage of contention paths; the written ordering proof remains normative.

## Usage examples

The following protocol is illustrative. The second `popFront` is the required recheck: it observes a producer publication before `clear`; a producer publication after `clear` sets the signal for `wait`.

```zig
try ring.tryPushBack(item); // release-publishes the item
signal.set(); // doorbell; consumer must recheck the ring
```

```zig
while (ring.popFront()) |item| {
    handle(item);
}
signal.clear();
if (ring.popFront()) |item| {
    handle(item);
    continue;
}
try signal.wait();
```
