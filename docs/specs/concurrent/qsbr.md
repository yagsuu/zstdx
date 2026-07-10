# Concurrent QSBR

Status: Approved.

`stdx.concurrent.qsbr.Domain` is a bounded quiescent-state-based reclamation
substrate. It tracks participant progress across grace periods so callers can
determine when objects removed from read-mostly shared structures are safe to
reclaim.

## What this spec is

This spec owns:

- `stdx.concurrent.qsbr`;
- `qsbr.GracePeriod`;
- `qsbr.Participant`;
- `qsbr.Domain.Static(N)`;
- `qsbr.Domain.Bounded`;
- participant online, offline, and quiescent reporting;
- grace-period creation and completion polling;
- fixed participant capacity and slot lifetime;
- required unit, model, stress, and layout tests.

QSBR owns reclamation lifetime observation only.

## What this spec is not

This spec is not:

- a hazard-pointer system;
- a generic epoch-based garbage collector;
- a full RCU read-side API;
- a reader critical-section guard API;
- a dynamic participant registry;
- a deferred-free list, retired-object queue, callback list, or destructor ABI;
- a table, map, pointer-publication, payload-consistency, or writer-serialization
  primitive;
- a scheduler, futex, wait queue, wake, yield, backoff, deadline, timeout,
  cancellation, or interrupt policy;
- a heap-allocating or dynamically growing reclamation domain;
- an ABI, wire, or packed-layout contract for the domain or slot types;

## Terminology

A **participant** is one caller-owned execution-context slot in a QSBR domain.
Participant assignment is caller-owned.

A participant is **online** when it can hold protected references and must be
observed before grace periods complete.

A participant is **offline** when it promises it holds no protected references
and does not block grace periods.

A **quiescent state** is a caller-known point where the participant holds no
references acquired from QSBR-protected shared structures before that point.

A **grace period** is a target generation. It completes after every online
participant reports a quiescent state at or beyond that generation, or goes
offline.

A **retired object** is an object that has been removed from a shared structure
but not yet reclaimed because a grace period is still pending.

A **reclaimed object** is a retired object whose required grace period has
completed and whose storage may be reused or freed by the caller.

## Public namespace and source ownership

The QSBR namespace lives under `stdx.concurrent`:

```zig
stdx.concurrent.qsbr
stdx.concurrent.qsbr.GracePeriod
stdx.concurrent.qsbr.Participant
stdx.concurrent.qsbr.Domain
stdx.concurrent.qsbr.Domain.Static
stdx.concurrent.qsbr.Domain.Bounded
```

Source ownership:

```text
src/concurrent.zig       -- domain facade
src/concurrent/qsbr.zig  -- QSBR implementation
test/concurrent/qsbr_test.zig
```

`src/concurrent.zig` re-exports:

```zig
pub const qsbr = @import("concurrent/qsbr.zig");
```

## Cross-spec relationships

This spec depends on `docs/specs/mem/cache.md` for `stdx.mem.CachePad`.
Participant slots and the global generation word are individually padded to
avoid false sharing between independently contended atomic fields.

This spec composes with, but does not own:

- retired-object storage and delayed freeing;
- pointer, table, mapping, seqlock, spinlock, or caller-owned synchronization
  that publishes or mutates protected structures;
- caller-owned backoff, wait, or scheduler mechanisms that poll `isComplete`.

QSBR does not publish payloads or serialize payload mutation.

## Data structures and representation

Conceptually, a QSBR domain contains one global generation and a fixed set of
participant slots:

```text
Domain
├── global_generation: u63
└── participants: [participant_capacity]ParticipantSlot

ParticipantSlot = offline | online(last_reported_generation: u63)
GracePeriod     = target_generation: u63
```

The required representation uses one padded atomic word for the global
generation and one padded atomic word per participant slot:

```zig
const Word = u64;
const offline_bit: Word = @as(Word, 1) << 63;
const generation_mask: Word = offline_bit - 1;

pub const Slot = stdx.mem.CachePad(std.atomic.Value(Word));
```

Participant slot encoding:

```text
word & offline_bit != 0  => offline
word & offline_bit == 0  => online, generation = word & generation_mask
```

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
  traps/asserts when `stdx.core.debug.checksEnabled(.build_mode)` is true.
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

## API

```zig
pub const GracePeriod = enum(u64) {
    _,

    pub fn generation(self: GracePeriod) u64;
};

pub const Participant = enum(u32) {
    _,

    pub fn index(self: Participant) u32;
};

pub const Domain = struct {
    pub fn Static(comptime capacity_participants: usize) type;

    pub const Bounded = struct { ... };
};
```

### `Domain.Static(capacity_participants)` returned type

```zig
pub const Self = struct {
    global_generation: stdx.mem.CachePad(std.atomic.Value(u64)),
    slots: [participant_capacity]Slot,

    pub const Slot = stdx.mem.CachePad(std.atomic.Value(u64));
    pub const participant_capacity = capacity_participants;

    pub fn init() Self;

    pub fn capacity(self: *const Self) usize;
    pub fn generation(self: *const Self) u64;

    pub fn participant(self: *const Self, index: usize) Participant;

    pub fn online(self: *Self, participant: Participant) void;
    pub fn offline(self: *Self, participant: Participant) void;
    pub fn quiescent(self: *Self, participant: Participant) void;

    pub fn beginGracePeriod(self: *Self) GracePeriod;
    pub fn isComplete(self: *const Self, grace_period: GracePeriod) bool;
};
```

### `Domain.Bounded` type

```zig
pub const Bounded = struct {
    global_generation: stdx.mem.CachePad(std.atomic.Value(u64)),
    slots: []Slot,

    pub const Slot = stdx.mem.CachePad(std.atomic.Value(u64));

    pub fn wrap(slots: []Slot) Bounded;

    pub fn capacity(self: *const Bounded) usize;
    pub fn generation(self: *const Bounded) u64;

    pub fn participant(self: *const Bounded, index: usize) Participant;

    pub fn online(self: *Bounded, participant: Participant) void;
    pub fn offline(self: *Bounded, participant: Participant) void;
    pub fn quiescent(self: *Bounded, participant: Participant) void;

    pub fn beginGracePeriod(self: *Bounded) GracePeriod;
    pub fn isComplete(self: *const Bounded, grace_period: GracePeriod) bool;
};
```

### Token accessors

```zig
pub fn generation(self: GracePeriod) u64;
pub fn index(self: Participant) u32;
```

`GracePeriod.generation` returns the token's target generation.
`Participant.index` returns the token's slot index.

Both accessors are O(1), wait-free, non-allocating, and perform no atomic
operation.

### `Static.init`

#### Contract

Returns a QSBR domain with `global_generation = 0` and every participant slot
offline.

`Static(0)` is a compile-time error. `Static(capacity_participants)` where the
capacity cannot be represented by `Participant` is a compile-time error.

#### State transitions

Creates a new domain in the initialized state. No participant is online.

#### Errors and fault behavior

Returns no error. Invalid static capacities fail at compile time.

#### Locking and waiting

Never locks and never waits.

#### Allocation behavior

Never allocates and never frees. Slot storage is inline in the returned value.

#### Memory ordering

Initialization performs ordinary construction stores. `init` must happen-before
any concurrent operation by caller-owned publication outside QSBR.

#### Invalidation and lifetime

After initialization, copying the domain is outside the contract. After any
pointer to the domain is shared with another execution context, moving it is
outside the contract.

#### Complexity/progress

O(`participant_capacity`) to initialize participant slots. Bounded and
wait-free with respect to other execution contexts because no concurrent use is
allowed during initialization.

### `Bounded.wrap`

#### Contract

Borrows caller-provided participant slots and returns a QSBR domain with
`global_generation = 0` and every participant slot offline.

`slots.len` is the participant capacity. The slice must be non-empty and must be
representable by `Participant`.

#### State transitions

Every supplied slot is overwritten with the offline state. Existing slot state
is discarded.

#### Errors and fault behavior

Returns no error. Passing an empty slice or a slice whose length cannot be
represented by `Participant` is a caller-contract violation and traps/asserts
when checks are enabled.

#### Locking and waiting

Never locks and never waits.

#### Allocation behavior

Never allocates and never frees. The returned domain borrows `slots`.

#### Memory ordering

Initialization performs ordinary construction stores. `wrap` must happen-before
any concurrent operation by caller-owned publication outside QSBR.

#### Invalidation and lifetime

The borrowed slot slice must remain alive, at the same address, and exclusively
owned by this domain for the domain lifetime and for every concurrent operation.
Reusing the slot slice for another domain before all operations on this domain
finish is outside the contract.

After initialization, copying the domain is outside the contract. After any
pointer to the domain is shared with another execution context, moving it is
outside the contract.

#### Complexity/progress

O(`slots.len`) to initialize participant slots. Bounded and wait-free with
respect to other execution contexts because no concurrent use is allowed during
initialization.

### Accessors

```zig
pub fn capacity(self: *const Self) usize;
pub fn generation(self: *const Self) u64;
pub fn participant(self: *const Self, index: usize) Participant;
```

#### Contract

`capacity` returns the fixed participant capacity.

`generation` returns the current global generation.

`participant` returns a typed participant-slot token for `index`. The token
carries only the numeric index; it does not reserve, register, lock, or claim
the slot.

#### Errors and fault behavior

These functions return no error. `participant(index)` with `index >= capacity()`
or `index > std.math.maxInt(u32)` is a caller-contract violation and
traps/asserts when checks are enabled.

#### Locking and waiting

Never lock and never wait.

#### Allocation behavior

Never allocate and never free.

#### NMI/interrupt safety

Safe from NMI and interrupt context.

#### Memory ordering

`capacity` and `participant` perform no atomic operation.

`generation` acquire-loads the global generation and masks out no bits because
the global word never stores `offline_bit`.

#### Concurrency effects

Safe to call concurrently with any QSBR operation. `participant` does not
serialize slot ownership; callers own the one-execution-context-per-slot rule.

#### Invalidation and lifetime

A `Participant` remains meaningful only for domains whose capacity includes its
index. It carries no domain identity. Passing a participant token to the wrong
domain is outside the contract unless the caller intentionally uses the same
numeric slot mapping for that domain.

#### Complexity/progress

O(1), wait-free.

### `online`

#### Contract

Marks `participant` online at the current global generation.

Preconditions:

- `participant.index() < capacity()`;
- the caller owns the participant slot;
- no other execution context is concurrently using the same slot;
- the participant does not rely on QSBR protection before `online` returns.

Postconditions:

- the participant is online;
- the participant reports the generation observed by `online`;
- grace periods at or below that reported generation do not wait on this
  participant solely because it came online after they began.

#### State transitions

```text
offline or online(old_generation) -> online(current_global_generation)
```

Calling `online` for an already-online participant owned by the caller updates
that participant's reported generation to the current global generation. It
does not create a nested online state.

#### Errors and fault behavior

Returns no error. An out-of-capacity participant or duplicate concurrent slot
ownership is a caller-contract violation. Duplicate ownership is not required
to be detected.

#### Locking and waiting

Never locks and never waits.

#### Allocation behavior

Never allocates and never frees.

#### NMI/interrupt safety

Safe from NMI and interrupt context when that context owns the participant slot
and can perform atomic loads and stores. It is unsafe to share one participant
slot between interrupted and interrupting contexts.

#### Memory ordering

`online` acquire-loads the global generation, then release-stores the encoded
online participant state. The release store publishes the participant's online
state to `isComplete` acquire scans.

#### Concurrency effects

May run concurrently with operations on other participant slots and with
`beginGracePeriod` and `isComplete`. It must not run concurrently with any other
operation on the same participant slot unless the caller externally serializes
that slot.

#### Complexity/progress

O(1), wait-free.

### `offline`

#### Contract

Marks `participant` offline.

Preconditions:

- `participant.index() < capacity()`;
- the caller owns the participant slot;
- the participant has reached a quiescent state and holds no protected
  references.

Postconditions:

- the participant is offline;
- the participant no longer blocks any current or future grace period until it
  is marked online again.

#### State transitions

```text
online(reported_generation) -> offline
offline -> offline
```

`offline` is idempotent for a caller-owned slot.

#### Errors and fault behavior

Returns no error. Calling `offline` while the participant still holds protected
references is a caller-contract violation and can lead to use-after-free by the
caller. QSBR is not required to detect this violation.

#### Locking and waiting

Never locks and never waits.

#### Allocation behavior

Never allocates and never frees.

#### NMI/interrupt safety

Safe from NMI and interrupt context when that context owns the participant slot
and has reached a quiescent state. It is unsafe to share one participant slot
between interrupted and interrupting contexts.

#### Memory ordering

`offline` release-stores the encoded offline state. `isComplete` acquire-loads
participant slots, so a completed grace period observes the participant's
release-published offline transition.

#### Concurrency effects

May run concurrently with operations on other participant slots and with
`beginGracePeriod` and `isComplete`. It must not run concurrently with any other
operation on the same participant slot unless the caller externally serializes
that slot.

#### Complexity/progress

O(1), wait-free.

### `quiescent`

#### Contract

Reports that `participant` has passed through a quiescent state at the current
global generation.

Preconditions:

- `participant.index() < capacity()`;
- the caller owns the participant slot;
- the participant is online;
- the participant currently holds no protected references acquired before the
  quiescent state being reported.

Postconditions:

- the participant remains online;
- the participant reports the current global generation;
- grace periods at or below that reported generation no longer wait on this
  participant.

#### State transitions

```text
online(old_generation) -> online(current_global_generation)
```

Calling `quiescent` for an offline participant is a caller-contract violation.
Checked builds trap/assert after detecting the offline state. Unchecked builds
do not guarantee behavior after this violation.

#### Errors and fault behavior

Returns no error. Reporting quiescence while still holding protected references
is a caller-contract violation and can lead to use-after-free by the caller.
QSBR is not required to detect this violation.

#### Locking and waiting

Never locks and never waits.

#### Allocation behavior

Never allocates and never frees.

#### NMI/interrupt safety

Safe from NMI and interrupt context when that context owns the participant slot
and can prove the quiescent-state precondition. It is unsafe to share one
participant slot between interrupted and interrupting contexts.

#### Memory ordering

`quiescent` acquire-loads the global generation, then release-stores the
encoded online participant state. `isComplete` acquire-loads participant slots,
so grace-period completion observes the participant's release-published
quiescent report.

#### Concurrency effects

May run concurrently with operations on other participant slots and with
`beginGracePeriod` and `isComplete`. It must not run concurrently with any other
operation on the same participant slot unless the caller externally serializes
that slot.

#### Complexity/progress

O(1), wait-free.

### `beginGracePeriod`

#### Contract

Advances the global generation and returns a `GracePeriod` token for the new
target generation.

Preconditions:

- the domain is initialized;
- advancing the generation will not set `offline_bit` or wrap the usable
  generation space.

Postconditions:

- `global_generation` is increased by one;
- the returned token names the new generation;
- a retired object removed before this call may be reclaimed after
  `isComplete` returns true for the returned token, assuming the caller's
  publication and mutation contracts are correct.

#### State transitions

```text
global_generation = G -> global_generation = G + 1
```

Participant slots are not modified.

#### Errors and fault behavior

Returns no error. Generation exhaustion is a caller/environment-contract
violation. Checked builds trap/assert before exhaustion can publish a generation
that encodes as offline.

#### Locking and waiting

Never locks and never waits.

#### Allocation behavior

Never allocates and never frees.

#### NMI/interrupt safety

Safe from NMI and interrupt context as a non-blocking atomic operation. Actual
reclamation after completion is caller-owned and may have stricter context
rules.

#### Memory ordering

`beginGracePeriod` performs an acquire-release atomic increment of the global
generation. The release side orders the caller's prior removal from the
protected structure before participants that acquire-load the new generation in
`quiescent` or `online`. The acquire side participates in ordering with other
grace-period begin operations.

QSBR does not publish payload data. Callers own the atomic ordering used to
remove objects from protected structures before calling `beginGracePeriod`.

#### Concurrency effects

May be called concurrently by multiple writers. Concurrent calls produce
distinct monotonically increasing grace-period tokens. Completing a later grace
period implies completion of every earlier grace period whose generation is less
than or equal to the later token.

`beginGracePeriod` does not serialize writers against each other for payload or
table mutation.

#### Invalidation and lifetime

Returned `GracePeriod` tokens remain valid for polling as long as the domain
itself remains alive and the generation space has not been exhausted.

#### Complexity/progress

O(1). Lock-free with respect to other `beginGracePeriod` callers according to
the target's atomic `fetchAdd` progress. Never scans participant slots.

### `isComplete`

#### Contract

Returns whether the supplied grace period has completed.

A grace period is complete when every participant slot satisfies at least one
of these conditions:

- the slot is offline;
- the slot is online and its reported generation is greater than or equal to
  `grace_period.generation()`.

#### State transitions

Does not mutate QSBR state.

#### Errors and fault behavior

Returns no error. Passing a `GracePeriod` from another domain is outside the
contract unless the caller intentionally compares against the same generation
space and accepts the result. `GracePeriod` carries no domain identity.

#### Locking and waiting

Never locks and never waits. It performs one bounded scan of the participant
slot array.

#### Allocation behavior

Never allocates and never frees.

#### NMI/interrupt safety

Safe from NMI and interrupt context when an O(`capacity`) bounded scan is
acceptable in that context. It does not block, but large participant capacities
may make the scan inappropriate for latency-sensitive handlers.

#### Memory ordering

`isComplete` acquire-loads every participant slot it examines. When it returns
true, it has observed release-published `offline` or `quiescent` transitions
from every slot that could block the grace period.

This establishes the QSBR lifetime edge: every online participant observed by
the scan has passed through a quiescent state at or beyond the target
generation. It does not establish payload consistency beyond the caller's own
publication and synchronization rules.

#### Concurrency effects

May run concurrently with `online`, `offline`, `quiescent`, and
`beginGracePeriod`. The result is a snapshot-style predicate over the loaded
slot states. A false result may become true immediately after the scan. A true
result for a grace period remains true with respect to participants that were
online before or during that grace period; later `online` calls do not make the
already-completed grace period incomplete.

#### Invalidation and lifetime

Does not invalidate any token or participant. The domain and, for `Bounded`, its
borrowed slot slice must remain alive throughout the scan.

#### Complexity/progress

O(`capacity`) loads. Bounded, wait-free with respect to participant progress,
and non-blocking. It can return false forever if an online participant never
reports quiescence and never goes offline.

## Implementation constraints

Implementation must:

- store the global generation in one `stdx.mem.CachePad(std.atomic.Value(u64))`;
- store each participant slot in one `stdx.mem.CachePad(std.atomic.Value(u64))`;
- use the high bit of participant slots as the offline marker and keep global
  generations below that bit;
- initialize all participant slots offline;
- perform no heap allocation;
- call no user callbacks;
- perform no scheduler, futex, wait, wake, yield, deadline, timeout, or
  cancellation operation;
- expose no public access to encoded slot words;
- avoid hidden global registries or process-wide QSBR state.

## Testing

### Required positive tests

- `Static(N).init` sets capacity to `N`, generation to zero, and every
  participant offline.
- `Bounded.wrap` sets capacity to `slots.len`, generation to zero, and every
  supplied slot offline.
- With every participant offline, a new grace period completes immediately.
- An online participant blocks a grace period until it reports `quiescent`.
- `offline` causes a participant to stop blocking current and future grace
  periods.
- `online` after a grace period starts reports the current generation and does
  not block that already-started grace period solely because it came online
  later.
- Multiple online participants must all report quiescence or go offline before
  completion.
- Completing a later grace period also completes earlier grace periods.
- `Participant.index` and `GracePeriod.generation` return their stored values.

### Required negative tests

- `Static(0)` fails at compile time.
- `Static(N)` where `N` cannot be represented by `Participant` fails at compile
  time.
- `participant(index)` traps/asserts when checks are enabled and
  `index >= capacity()`.
- `Bounded.wrap` with an empty slot slice traps/asserts when checks are enabled.
- `Bounded.wrap` with a slice length not representable by `Participant`
  traps/asserts when checks are enabled.

Misuse cases that require caller-owned execution-context proof, such as
reporting `quiescent` while still holding a protected reference or duplicate
concurrent slot ownership, are documented contract violations and are not
required to be detected by tests.

### Edge cases

- Capacity one.
- All participants offline.
- One online participant and all other participants offline.
- Repeated `offline` on an already-offline caller-owned participant.
- Repeated `online` on an already-online caller-owned participant updates its
  reported generation without creating nested state.
- Overlapping grace periods where a participant reports only the first target
  generation, leaving the second incomplete.
- Overlapping grace periods where a participant reports the latest target
  generation, completing both.

### Error and fault behavior

- Runtime caller-contract violations listed above are exercised only in test
  modes where `stdx.core.debug.checksEnabled(.build_mode)` enables the relevant
  trap/assert behavior.
- Tests must not require release builds to detect duplicate participant
  ownership or quiescent-state lies.

### Concurrency, model, and stress tests

- Model two or more participants and one writer beginning grace periods while
  participants transition online, quiescent, and offline.
- Stress concurrent `quiescent` calls on distinct participant slots while a
  writer repeatedly begins and polls grace periods.
- Stress concurrent `beginGracePeriod` callers and verify returned generations
  are unique and monotonic.
- Verify `isComplete` remains non-blocking under a participant that stays online
  and never reports quiescence.

### Memory-ordering tests

- Model that a participant quiescent report after observing a grace-period
  generation is sufficient for `isComplete` to observe progress through acquire
  loads.
- Model that a participant quiescent report racing before `beginGracePeriod`
  does not complete the new grace period unless a later report observes the new
  generation.
- Confirm QSBR tests do not assert payload publication guarantees that belong
  to caller-owned pointer/table synchronization.

### Layout and representation tests

- `Static(N).Slot` and `Bounded.Slot` are `stdx.mem.CachePad(std.atomic.Value(u64))`.
- Slot alignment equals `std.atomic.cache_line` through the `CachePad` contract.
- Adjacent static slots occupy distinct cache-line-padded elements.
- The global generation field is cache-line padded separately from participant
  slots.
- Encoded offline slots set the high bit; encoded online slots clear it and
  contain the reported generation in the low bits.

