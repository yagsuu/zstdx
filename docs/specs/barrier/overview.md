# Barrier overview

Status: Approved.

`stdx.barrier` owns the shared ordering vocabulary used by synchronization,
concurrent containers, MMIO, DMA, and architecture-specific specs. This overview
approves terminology and documentation requirements only; it does not approve a
runtime barrier API.

## Owned scope

This spec owns:

- the `stdx.barrier` namespace as the home for future cross-target ordering
  helpers;
- shared vocabulary for atomic publication, acquisition, doorbells, fences, and
  waits;
- the rule that concurrent primitive specs must state allocation, waiting,
  progress, and memory-ordering contracts at each public operation;
- the distinction between data visibility and notification;
- required documentation and test expectations for future barrier and
  concurrent specs.

## Deferred scope and non-goals

This spec does not own:

- concrete compiler, CPU, IO, MMIO, DMA, or cache-maintenance barrier functions;
- target-specific instruction selection;
- volatile or MMIO register access wrappers;
- futex, wait-queue, scheduler, interrupt, or preemption policy;
- proving hardware ordering through ordinary unit tests;
- replacing Zig's atomic ordering names.

Future specs such as `docs/specs/barrier/dma.md` may approve concrete APIs.
Until then, specs that need ordering name Zig atomic orderings directly.

## Public namespace

The namespace is reserved as:

```zig
stdx.barrier
```

No public Zig declarations are approved by this overview.

Source ownership for this overview is documentation-only. A future API spec may
approve:

```text
src/barrier.zig
src/barrier/*.zig
test/barrier/*_test.zig
```

`stdx.barrier` stays namespaced and is not root-promoted.

## Ordering vocabulary

A **publisher** writes ordinary data and then performs a release operation that
makes the data observable through a synchronization object.

An **acquirer** performs an acquire operation on the synchronization object and,
when it observes the publisher's released state, may read the published ordinary
data.

A **published slot** is a container slot whose contents are visible to a
consumer because the producer completed the release publication step for that
slot.

A **free slot** is a container slot whose previous contents are no longer live
and whose metadata has been release-published as available for a producer.

A **reservation** is ownership of a future mutation point before publication. A
reserved slot is not a published slot. Consumers must not read reserved but
unpublished data.

A **doorbell** is notification that a consumer should recheck state. Doorbells
are not data-visibility proofs. The data structure still owns its acquire and
release ordering.

A **sticky signal** is a level-triggered doorbell state. Once set, it remains set
until an explicit clear.

An **edge signal** or **pulse** is a transient notification with no retained
state. Edge signals are not sufficient for the generic ring/signal protocol
because they can lose wakes when the edge races with waiter enrollment.

A **wait** is any operation that may block, sleep, park, yield, or spin while
waiting for state to change. Public APIs must not hide waits; specs must name
which operation waits and whether the waiting behavior is owned by a backend.

A **backend** is caller-supplied behavior used by a primitive for target- or
scheduler-specific work. Specs that approve a backend must define the required
functions, error set, allocation behavior, waiting behavior, and lost-wakeup
rules.

## Atomic ordering rules

Specs use Zig's ordering names at operation sites:

- `.monotonic` for atomicity without cross-location ordering;
- `.acquire` when later loads/stores must observe a release publication;
- `.release` when prior loads/stores must become visible to an acquire;
- `.acq_rel` when one operation both acquires prior state and publishes later
  state;
- `.seq_cst` only when the spec needs a single total order and justifies the
  cost.

Concurrent primitive specs must state which operation publishes data and which
operation acquires it. Comments in implementation must sit near the atomic
operation that enforces the contract.

## Data visibility versus notification

A signal or wake operation does not make ring payload bytes visible by itself.
The queue, ring, lock, or other data structure owns data visibility through its
own atomic publication protocol.

Correct pattern:

```zig
try ring.tryPushBack(item); // release-publishes the item
signal.set();              // doorbell; consumer must recheck the ring
```

Incorrect contract:

```zig
signal.set(); // does not prove any ring item is readable
```

Consumers must tolerate redundant and spurious notifications. A notification may
mean only "state might have changed".

## Waiting and lost wakeups

A wait-capable primitive must state how a waiter avoids this race:

1. observe the condition as false;
2. producer changes the condition and sends a wake;
3. waiter enrolls after the wake and sleeps forever.

Approved patterns include:

- backend enrollment followed by a mandatory condition recheck before parking;
- generation/token comparison that detects state changes between observation and
  enrollment;
- target primitives with documented atomic wait semantics.

Specs must not approve pulse-only wait protocols for reusable synchronization
primitives.

## Behavior contract

This overview approves no executable operations.

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| vocabulary only | none | none | none | none | documentation-only | defines terms only |

## Documentation requirements

Every concurrent or synchronization primitive spec must state:

- access contract: SPSC, MPSC, MPMC, externally synchronized, single waiter, or
  multi-waiter;
- allocation behavior;
- waiting, blocking, sleeping, yielding, and spinning behavior;
- progress behavior under contention;
- full-capacity or unavailable-resource behavior;
- pointer, reference, and storage invalidation;
- atomic orderings at publish/acquire/free points;
- no-mutation-on-error behavior;
- backend behavior if any operation delegates to a backend.

## Required tests for future APIs

Future barrier API specs must include target-gated tests that verify API shape,
compile availability, and documented fallback behavior. Ordinary unit tests must
not claim to prove CPU, device, or DMA ordering.

Concurrent data structure specs must include deterministic model tests where
practical, plus stress tests that exercise contention. Stress tests demonstrate
coverage; the written ordering proof remains normative.

## Examples

Doorbell protocol for a producer:

```zig
try ring.tryPushBack(item);
signal.set();
```

Doorbell protocol for a consumer:

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

The second `popFront` after `clear` is the required recheck. A producer that
published before `clear` is found by the recheck. A producer that publishes after
`clear` sets the signal for `wait`.

## Open questions

None.
