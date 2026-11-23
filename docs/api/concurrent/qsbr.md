# `stdx.concurrent.qsbr`

`stdx.concurrent.qsbr.Domain` tracks participant quiescence across grace periods
for caller-managed reclamation of objects removed from shared structures.

## Variants and storage

In this contract, `Domain` operation names apply to both `Domain.Static(count)`
and `Domain.Bounded`.

| Variant | Construction and storage |
| --- | --- |
| `Domain.Static(count)` | `Domain.Static(count).init()` owns `count` inline slots. `count` must be in `1...2^32`, subject to the target's `usize` range. Invalid capacities fail at compile time. |
| `Domain.Bounded` | `Domain.Bounded.wrap(slots)` borrows a nonempty slice of `Domain.Bounded.Slot`, with at most `2^32` elements. It overwrites every slot. |

Construction initializes generation zero with all slots offline in O(capacity).
Publish the initialized domain before concurrent use.

Keep borrowed slots alive, address-stable, correctly aligned for
`Domain.Bounded.Slot`, and exclusively assigned to the domain until all uses
finish. Do not overlap slot storage between live domains or access slot contents
outside the domain operations. Slots and the generation word use
[cache padding](../layout/cache.md).

Do not copy an initialized domain. Once a domain address is shared, do not move
the domain. Reinitialization requires exclusive access, no remaining protected
references, and abandonment of the previous domain's grace-period tokens.

## Safe use

Callers assign participant slots and serialize ownership transfers. Each slot
has one owner at a time, including across interrupting contexts. Participant
arguments MUST identify valid slots. Tokens used with another domain require
an intentionally assigned valid index there.

For each reader:

1. Establish online state with `Domain.online(participant)` before acquiring
   protected references.
2. Acquire references through the caller's shared-structure synchronization.
3. Finish using references acquired before the next quiescent state.
4. Report that state with `Domain.quiescent(participant)`, or call
   `Domain.offline(participant)` when no protected references remain.

For reclamation:

1. Remove the object from the protected structure.
2. Call `Domain.beginGracePeriod()` after removal.
3. Keep the object's storage valid until `Domain.isComplete(period)` returns true.
4. Free or reuse the retired object in an appropriate execution context.

The caller owns shared-structure publication, removal ordering, payload
synchronization, retired-object tracking, and the read-side visibility needed
to prevent new readers from acquiring removed objects. QSBR does not serialize
payload mutation. Generation acquisition alone does not provide that read-side
visibility.

## Participant operations

| Operation | Effect and requirements |
| --- | --- |
| `Domain.participant(index)` | Returns a token for a valid slot index. |
| `Domain.online(participant)` | Reports the observed generation. Calls do not nest. An already-online participant must reach a quiescent state before advancing its report this way. |
| `Domain.quiescent(participant)` | Reports the observed generation and remains online. Requires an online slot. |
| `Domain.offline(participant)` | Marks the slot offline so it no longer delays grace periods. Repeated calls are valid. Call `Domain.online()` before acquiring references again. |

## Grace-period operations

Use grace-period tokens from the domain's current initialization.
Generations range from zero through `2^63 - 1` without wrapping. The caller
MUST prevent advancement at that maximum, including concurrent attempts.

| Operation | Result and effect |
| --- | --- |
| `Domain.generation()` | Acquire-observes the current generation. |
| `Domain.beginGracePeriod()` | Advances the generation by one and returns its target as a `GracePeriod`. Concurrent calls return distinct, increasing targets. Participant state is unchanged. |
| `GracePeriod.generation()` | Returns the target as a `u64`. |
| `Domain.isComplete(period)` | Returns true when each observed slot is offline or reports at least the target generation. Leaves state and tokens unchanged. |

Completion polling is not an atomic snapshot and can return false on the first
blocker. A false result can become obsolete immediately. Completion of a later
target also satisfies earlier targets.

## Ordering, concurrency, and progress

`Domain.beginGracePeriod()` acquires preceding generation advancements and
release-publishes prior removal with its new generation (`.acq_rel`).
`Domain.online()` and `Domain.quiescent()` acquire the generation they report,
then release-publish the participant report. `Domain.offline()` release-publishes
completion of the participant's protected accesses.

`Domain.isComplete()` acquires each examined report or offline transition.
A true result orders protected accesses completed before those reports or
transitions before subsequent reclamation, subject to the caller's safe-use
requirements above.

After publication, queries, grace-period creation, and completion polling can
run concurrently with participant operations and each other. Participant
operations on distinct slots can run concurrently.

Operations perform no allocation or waiting. Participant operations and queries
take O(1) time, except `Domain.isComplete()`, which scans at most capacity slots.
`Domain.beginGracePeriod()` has unbounded retries on contention or spurious
weak-CAS failure.

A stalled online participant reporting below a target can prevent completion
indefinitely. Interrupt and NMI callers require suitable atomic support,
exclusive slot ownership, and an acceptable scan cost.

## References

- [QSBR domains](../../../src/concurrent/qsbr.zig)
