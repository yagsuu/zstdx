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

A participant is **online** when it can hold protected references and must be
observed before grace periods complete.

Keep borrowed slots alive, address-stable, correctly aligned for
`Domain.Bounded.Slot`, and exclusively assigned to the domain until all uses
finish. Do not overlap slot storage between live domains or access slot contents
outside the domain operations. Slots and the generation word use
[cache padding](../layout/cache.md).

Do not copy an initialized domain. Once a domain address is shared, do not move
the domain. Reinitialization requires exclusive access, no remaining protected
references, and abandonment of the previous domain's grace-period tokens.

## Participants and protected references

A **retired object** is an object that has been removed from a shared structure
but not yet reclaimed because a grace period is still pending.


An online participant may hold references to protected objects. An offline
participant promises to hold none and does not delay grace periods. A quiescent
state is a point at which the participant has finished using protected references
acquired before that point.

This spec depends on `docs/specs/mem/cache.md` for `stdx.mem.CachePad`.
Participant slots and the global generation word are individually padded to
avoid false sharing between independently contended atomic fields.

This spec composes with, but does not own:

## Grace periods and reclamation

QSBR does not publish payloads or serialize payload mutation.

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

```text
Domain
├── global_generation: u63
└── participants: [participant_capacity]ParticipantSlot

Remove an object from the protected structure before
`Domain.beginGracePeriod()`, and keep its storage valid until the required
grace period completes. The caller owns shared-structure publication, removal
ordering, payload synchronization, and the read-side visibility needed to prevent
new readers from acquiring removed objects. Readers must obey the participant
lifetime rules above. QSBR does not serialize payload mutation.

The required representation uses one padded atomic word for the global
generation and one padded atomic word per participant slot:

## Ordering, concurrency, and progress

pub const Slot = stdx.mem.CachePad(std.atomic.Value(Word));
```

Advancement release-orders prior removal before participants that acquire the
advanced generation. Completion acquires observed release-published reports and
offline transitions. These orderings must be composed with the caller's
shared-structure synchronization and read-side visibility rules.

After publication, accessors, grace-period creation, and completion polling can
run concurrently with each other and with participant operations. Participant
operations on distinct slots can run concurrently. `Domain.capacity()`,
`Domain.participant()`, and token accessors perform no atomic operations.

`global_generation` stores only generation bits and never stores
`offline_bit`. Implementations must not expose the encoded words as public API.
The encoding is an implementation contract so tests can verify slot isolation
and state transitions; it is not an ABI, wire, or packed-layout guarantee for
the enclosing domain types.

Generations use the low 63 bits. Calling `beginGracePeriod` when
`global_generation == generation_mask` is outside the contract. Checked builds
trap/assert on this violation. Implementations must not wrap the global
generation into `offline_bit`.

## Global invariants

- Participant capacity is fixed after construction.
- `Static(0)` is a compile-time error.
- `Static(N)` where `N > std.math.maxInt(u32) + 1` is a compile-time error.
- `Bounded.wrap` with an empty slot slice is a caller-contract violation and
  traps/asserts when `stdx.core.debug.checksEnabled()` is true.
- `Bounded.wrap` with `slots.len > std.math.maxInt(u32) + 1` is a
  caller-contract violation and traps/asserts when checks are enabled.
- Every participant token names one numeric slot index.
- A participant slot is caller-owned by at most one execution context at a
  time. Duplicate concurrent ownership of a slot is outside the contract.
- All participant slots are offline after construction.
- Offline participants do not block any grace period.
- Online participants block a grace period until they report a generation at or
  beyond the grace period's target, or go offline.
- `global_generation` is monotonic and never uses `offline_bit`.
- QSBR operations never allocate, free, wait, park, yield, call user code, or
  access hidden global state.
- After initialization, copying a domain is outside the primitive's contract.
- After any pointer to a domain is shared with another execution context,
  moving the domain is outside the primitive's contract.

    global_generation: stdx.mem.CachePad(std.atomic.Value(u64)),
    pub const Slot = stdx.mem.CachePad(std.atomic.Value(u64));
    global_generation: stdx.mem.CachePad(std.atomic.Value(u64)),
    pub const Slot = stdx.mem.CachePad(std.atomic.Value(u64));
- store the global generation in one `stdx.mem.CachePad(std.atomic.Value(u64))`;
- store each participant slot in one `stdx.mem.CachePad(std.atomic.Value(u64))`;