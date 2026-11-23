# `stdx.concurrent.qsbr`

`stdx.concurrent.qsbr.Domain` tracks participant quiescence across grace periods
for caller-managed reclamation of objects removed from shared structures.

## Variants and storage

In this contract, `Domain` operation names apply to both `Domain.Static(count)`
and `Domain.Bounded`.

| Variant | Construction and storage |
| --- | --- |
| `Domain.Static(count)` | `Domain.Static(count).init()` owns `count` inline slots. `count` must be in `1...2^32`, subject to the target's `usize` range; invalid capacities fail at compile time. The returned type exposes `bound = count`. |
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

## Participants and protected references

`Domain.capacity()` returns the fixed slot count. `Domain.participant(index)`
returns the token for a valid index; `Participant.index()` returns its `u32` value.
Callers assign slots and serialize ownership transfers. Each slot has one owner
at a time, including across interrupting contexts. Tokens used with another
domain require an intentionally assigned valid index there.

An online participant may hold references to protected objects. An offline
participant promises to hold none and does not delay grace periods. A quiescent
state is a point at which the participant has finished using protected references
acquired before that point.

| Operation | Requirements and effect |
| --- | --- |
| `Domain.online(participant)` | The caller owns the slot and must establish online state before acquiring protected references. Reports the generation observed by this call. Repeated calls replace the report and do not nest; an already-online participant must first reach a quiescent state before using this operation to advance its report. |
| `Domain.offline(participant)` | The caller owns the slot and holds no protected references. Marks the slot offline. Repeated calls are valid. The participant must call `Domain.online()` again before acquiring protected references. |
| `Domain.quiescent(participant)` | The caller owns an online slot and has finished using references acquired before the reported quiescent state. Reports the generation observed by this call and remains online. |

Participant arguments MUST identify valid slots.

## Grace periods and reclamation

`Domain.generation()` acquire-observes the global generation.

`Domain.beginGracePeriod()` advances the generation by one and returns a
`GracePeriod` for the new target. `GracePeriod.generation()` returns that target
as a `u64`. Concurrent calls return distinct, increasing targets. Generations
range from zero through `2^63 - 1`; the caller must prevent further advancement
at that maximum, including concurrent attempts. Generations do not wrap.
Advancement does not change participant state.

`Domain.isComplete(period)` returns true if each observed slot is offline or
reports a generation at least equal to the target. It acquire-loads slots and
can return false as soon as it observes a blocker. The observations are not an
atomic snapshot. A false result can become obsolete immediately.

Use tokens from the domain's current initialization. Polling leaves tokens and
state unchanged. Completion of a later target also satisfies earlier targets.
New participants report the generation observed on entry.

Remove an object from the protected structure before
`Domain.beginGracePeriod()`, and keep its storage valid until the required
grace period completes. The caller owns shared-structure publication, removal
ordering, payload synchronization, and the read-side visibility needed to prevent
new readers from acquiring removed objects. Readers must obey the participant
lifetime rules above. QSBR does not serialize payload mutation.

The caller tracks retired objects and frees or reuses them after completion
in an appropriate execution context.

## Ordering, concurrency, and progress

| Operation | Atomic ordering |
| --- | --- |
| `Domain.online()` | Acquire-loads the global generation, then release-stores the online report. |
| `Domain.offline()` | Release-stores offline state. |
| `Domain.quiescent()` | Monotonic-loads the slot state, acquire-loads the global generation, then release-stores the report. |
| `Domain.beginGracePeriod()` | Initially acquire-loads the generation. Advancement uses weak compare-exchange with acquire-release success ordering and acquire failure ordering. |
| `Domain.isComplete()` | Acquire-loads each examined slot. |

Advancement release-orders prior removal before participants that acquire the
advanced generation. Completion acquires observed release-published reports and
offline transitions. These orderings must be composed with the caller's
shared-structure synchronization and read-side visibility rules.

After publication, accessors, grace-period creation, and completion polling can
run concurrently with each other and with participant operations. Participant
operations on distinct slots can run concurrently. `Domain.capacity()`,
`Domain.participant()`, and token accessors perform no atomic operations.

Operations perform no allocation or waiting. Slot operations and accessors
take O(1) time; `Domain.isComplete()` scans at most capacity slots.
`Domain.beginGracePeriod()` retries on contention and spurious weak-CAS failure;
its retry count is unbounded.

A stalled online participant reporting below a target can prevent completion
indefinitely. Interrupt and NMI callers require suitable atomic support,
exclusive slot ownership, and an acceptable scan cost.

## References

- [QSBR domains](../../../src/concurrent/qsbr.zig)
