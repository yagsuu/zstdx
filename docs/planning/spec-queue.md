# Spec queue

This document is planning material. Normative requirements live only under `docs/specs/` after user approval.

## Workflow

1. Pick the next entry from `Queue`.
2. Present a concise decision proposal to the user before writing:
   - decision points and recommended answers;
   - owned scope and non-goals;
   - public namespace/type shape;
   - semantic contracts;
   - planned primitive list when the spec is a category/overview;
   - open questions.
3. Wait for explicit approval.
4. Write the approved spec under `docs/specs/`.
5. Remove the approved entry from `Queue`.
6. If the approved spec is not implemented yet, keep a small pointer under
   `Approved, pending implementation`; remove that pointer when implementation
   lands.
7. Repeat.

Implementation work begins only after the required specs for that slice are approved and written.
Approved and implemented specs do not stay in this queue document; the spec file,
source module doc, and tests are the implementation record.

## Queue entry format

Every `Queue` entry starts with one title line:

```text
- `docs/specs/<path>.md` — One-line summary.
```

A proposal body is optional. When present, separate it from the title line with
one blank line and indent the body under the entry:

```text
- `docs/specs/<path>.md` — One-line summary.

  Proposal must decide:
  - decision point;
  - decision point.
```

Entries without a body stay as a single title line. Approved entries are removed
from `Queue` immediately after the approved spec lands.

## Proposal requirements

Proposals are decision packs, not full prose specs. Each proposal must be concise enough to review in one pass and concrete enough to approve.

Every proposal must include:

- decisions requested from the user;
- recommended answer for each decision;
- owned scope;
- deferred scope and non-goals;
- namespace and public type shape;
- operation semantics where signatures are not yet approved;
- allocation, waiting, capacity, invalidation, concurrency, and ordering contracts where relevant;
- planned primitive categories and primitive names for overview specs;
- required tests at category level;
- open questions.

Proposals must not include:

- implementation work;
- full final-spec prose;
- speculative future phases;
- rejected alternatives unless the user asks for comparison;
- hidden defaults that decide policy for downstream domains.

## Approved, pending implementation

- `docs/specs/arch/x86_64/paging.md` — Exact IA-32e paging-structure producers and read-only translation.

## Queue

Prioritized for implementation value across sibling consumers while respecting the
first-slice limits in `docs/specs/project/scope.md`.

A proposal stays near the top only when it adds a distinct `zstdx` contract beyond
Zig language features or `std` functionality. Distinct value means explicit
allocation, ownership, capacity, invalidation, ordering, no-mutation-on-error,
target, or cross-consumer behavior that callers do not already get from Zig or
`std`. Consolidation-only wrappers are deferred until more high-value primitives
exist.

### Head-of-queue — hv, firmware, and kernel consumers

These items are hoisted for consumer readiness. They are drafted top-down; a
wave's remaining items may be re-parallelized once earlier proposals in the
same wave are approved.

#### x86 domain extensions

- `docs/specs/arch/x86_64/memtype.md` — PAT/MTRR architectural memory-type layouts and pure memory-type resolution.

  Proposal must decide:
  - namespace `stdx.arch.x86_64.memtype` (recommended) instead of a narrower
    `mtrr` namespace, because PAT, MTRR, and paging cache bits share one
    architectural memory-type vocabulary;
  - owned scope: `memtype.Type` for architecturally valid memory-type encodings;
    `memtype.Pat` for the IA32_PAT eight-entry layout; `memtype.mtrr.Cap`,
    `DefaultType`, `VariableBase`, `VariableMask`, fixed-range register layouts,
    variable-range decoding, and MSR-address helpers for MTRR registers;
  - pure construction, raw round-trip, field extraction, and reserved-bit
    validation for every exposed layout. Layout declarations compile on every
    target and contain no inline assembly;
  - whether to include a pure resolver that combines caller-supplied PAT state,
    decoded MTRR ranges, default MTRR type, physical address, and paging cache
    bits. Recommended: include the resolver only if the spec can state exact
    precedence and error behavior without reading CPU state;
  - relationship to existing specs: uses `stdx.arch.x86_64.Msr` only as an MSR
    address value, composes with `cpuid` feature bits and `paging` cache
    attributes, and does not change the paging walker;
  - explicit non-goals: reading or writing MSRs, safe MTRR programming sequences,
    cache-disable/writeback choreography, SMP rendezvous, firmware memory-map
    ownership, device memory policy, page-table mutation, or choosing mappings
    for callers;
  - behavior contracts: every layout and helper is allocation-free, wait-free,
    O(1) except resolver scans over caller-supplied MTRR ranges, value-only for
    concurrency, and error-returning only for invalid encodings, unsupported
    fixed-range forms, reserved bits, or ambiguous resolver input;
  - required tests: bit-size and raw round-trip tests for PAT and every MTRR
    layout, MSR-address helper tests, reserved-bit rejection by physical-width
    boundary, fixed/variable range decoding, and resolver precedence cases if
    the resolver is included;
  - open questions: exact public name for the PAT/MTRR shared memory-type enum,
    whether PAT's uncached-minus encoding is a distinct public tag, whether
    fixed-range MTRRs are grouped by register or exposed as decoded ranges, and
    whether the first spec includes the resolver or leaves it to a later
    consumer-driven amendment.

- `docs/specs/arch/x86_64/lapic.md` — Local APIC architectural register layouts and xAPIC/x2APIC register identifiers.

  Proposal must decide:
  - namespace `stdx.arch.x86_64.lapic`, re-exported from `stdx.arch.x86_64` as
    lower-case `lapic`;
  - owned scope: IA32_APIC_BASE layout; xAPIC register offsets; x2APIC MSR
    number mapping; common local-APIC register value layouts such as version,
    task-priority, processor-priority, logical-destination, destination-format,
    spurious-interrupt-vector, local-vector-table, interrupt-command, timer
    initial/current count, timer divide, and error status;
  - pure construction, raw round-trip, field extraction, register-offset/MSR
    address helpers, and reserved-bit validation. Recommended: no volatile MMIO
    helpers and no direct MSR read/write wrappers in the first spec;
  - relationship to existing specs: uses `stdx.arch.x86_64.Msr` for x2APIC MSR
    addresses, composes with `stdx.io.Mmio.Window` for xAPIC access, composes
    with `cpuid` APIC/x2APIC feature bits, and does not own IDT, interrupt
    handlers, or vector allocation;
  - explicit non-goals: mapping the LAPIC page, discovering the LAPIC base,
    enabling or disabling LAPIC/x2APIC mode, sending IPIs as an operation, EOI
    policy, interrupt routing, AP startup policy, timer calibration,
    deadline-timer clock integration, spurious-vector policy, NMI/LINT policy,
    TPR scheduling policy, interrupt-remapping/IOMMU behavior, or IOAPIC state;
  - behavior contracts: every layout and helper is allocation-free, wait-free,
    O(1), value-only for concurrency, and error-returning only for invalid
    register identifiers, non-x2APIC register mappings, invalid vector fields,
    or reserved-bit violations;
  - required tests: bit-size and raw round-trip tests for every packed layout,
    xAPIC offset values, x2APIC MSR mapping values, APIC-base field extraction,
    LVT/ICR vector validation, timer mode/divide encoding, and reserved-bit
    rejection;
  - open questions: whether xAPIC and x2APIC register names are one shared enum
    with mapping helpers or separate namespaces, whether ICR is one `u64` value
    or split high/low xAPIC words, whether APIC ID helpers expose x2APIC 32-bit
    IDs directly, and whether any LAPIC access wrappers are justified after
    layout users exist.

#### Naming convention for wait-capable primitives

Every spec in this section that composes a caller-supplied wait/wake backend
MUST follow this convention:

1. Type-factory suffix names a **semantic** distinction between siblings, not
   backend parameterization. `Signal.Manual(Backend)` is correct because
   `Manual` means manual-reset (vs. a hypothetical `AutoReset` sibling).
   `Clock.Monotonic(Backend)` is correct because `Monotonic` names the clock
   kind. Backend parameterization is a `(Backend)` parameter, never a name
   suffix.
2. A primitive with no semantic sibling takes `Backend` directly:
   `Once(Backend)`, `Rendezvous(Backend)`, `Latch(Backend)`. No `.Manual` /
   `.Waitable` / `.Wait` noise on the type factory.
3. Spin-only callers get "no wait" via the shared `sync.spin.Backend`:
   `Once(sync.spin.Backend)`, `Rendezvous(sync.spin.Backend)`,
   `Latch(sync.spin.Backend)`. No per-primitive `.Spin` alias unless the
   owning spec justifies it.
4. Raw atomic-word substrates exposed for lock-free composition keep stable
   `.State`-suffixed names (`Signal.State`, `sync.once.State`).
5. The shared backend seam passes primitive identity to both sides:
   `wait(state, observed)` arms a wait and `wakeAll(state)` wakes waiters for
   that same primitive instance. Backends that ignore state may accept
   `*const anyopaque`, but specs must not omit the state argument from wake.

#### Wave 2 — hv-specific

- `docs/specs/concurrent/mpsc-atomic-ring.md` — Single-atomic-publication bounded MPSC ring for preemption-safe producer paths.

  Sibling to `docs/specs/concurrent/mpsc-ring.md` under the same `mpsc`
  namespace. Not a mode flag on `Ring`. Publishes an item in one atomic step
  (packed sequence tag + payload in a single CAS on a per-slot
  `std.atomic.Value(u64)`), so a producer preempted at any point leaves the ring
  in a legal state — no reserved-but-unpublished window. Proposal must decide:
  - name is `concurrent.mpsc.AtomicRing`, and it names the mechanism
    (single-atomic publication), not caller context. NMI safety is a
    consequence of the mechanism, not the name;
  - shape: `AtomicRing.Static(comptime T: type, comptime capacity_items: usize)`
    and `AtomicRing.Bounded(comptime T: type)`, matching `Ring`'s family shape;
  - each `Slot` is `cell: std.atomic.Value(u64)` packing sequence tag and
    payload; the tag reserves at least 32 bits so wrap-around does not alias
    within the ring's lifetime;
  - `T` must fit in `64 - tag_bits`; larger payloads use `Ring`;
  - `head` and `tail` are cache-line-padded via `stdx.mem.CachePad`, matching
    correction 15's discipline on `Ring`;
  - `tryPushBack` performs exactly one CAS on the target slot; `Full` when the
    slot's sequence tag says "not yet free"; `Contended` when the CAS loses the
    race;
  - `popFront` matches `Ring.popFront`'s execution-context freedom (single
    owner, no CAS participation), and remains safe from any execution context
    including NMI;
  - cross-reference from `docs/specs/concurrent/mpsc-ring.md` (correction 16's
    NMI-safe sibling pointer) is repointed at
    `docs/specs/concurrent/mpsc-atomic-ring.md`;
  - zero-allocation, bounded, no policy on wake or scheduler.

#### Additional non-waved head-of-queue additions

- `docs/specs/sync/seq-lock.md` — Read-mostly RMW-avoiding lock guarded by a monotonic sequence counter.

  Single-writer / many-reader; readers spin on the counter and never block
  writers. Proposal must decide:
  - shape `stdx.sync.SeqLock` with cache-line-padded
    `seq: stdx.mem.CachePad(std.atomic.Value(u64))`;
  - odd `seq` means "write in progress", even means "quiescent";
  - operations `beginWrite`/`endWrite` (writer, `fetchAdd(1, .acq_rel)` and
    `fetchAdd(1, .release)`), `beginRead`/`endRead` (reader retry loop), and
    `tryRead(max_retries, payload, comptime body, comptime T)` canned retry
    helper;
  - `ReadError = error{Contended}` is the entire error set; `endRead` returns
    `error.Contended` if `seq` changed since `beginRead` or if `beginRead`
    observed an odd counter;
  - payload storage is caller-owned (non-atomic ordinary storage); the seqlock
    guards access ordering only;
  - writers are externally serialized against other writers (use `RawSpinLock`,
    a mutex, or a ticket lock outside the seqlock);
  - explicit non-goals: writer-writer arbitration, payload storage,
    priority-inversion policy, futex parking, scheduler yielding;
  - reader is safe from NMI/interrupt context (bounded retries under `tryRead`);
    writer is not safe from NMI — a preempted writer between `beginWrite` and
    `endWrite` stalls readers indefinitely.
  Distinct from any `std` primitive; reader guarantees checked by unit, model,
  and stress tests.

- `docs/specs/sync/ticket-lock.md` — Fair FIFO spinlock family next to `RawSpinLock`.

  Proposal must decide:
  - shape `stdx.sync.TicketLock(Backend)` following the shared wait-capable
    backend seam (matches `Signal.Manual(Backend)`, `Once(Backend)`,
    `Rendezvous(Backend)`, `Latch(Backend)`);
  - cache-line-padded `next_ticket` and `now_serving`
    (`std.atomic.Value(u32)` each) via `stdx.mem.CachePad`;
  - `Ticket = u32`, `WaitError = Backend.WaitError`;
  - operations `acquire(self) WaitError!void`, `tryAcquire(self) bool`,
    `release(self) void`;
  - `acquire` draws a ticket via `next_ticket.fetchAdd(1, .acq_rel)` and loops
    calling `backend.wait(&self.now_serving, snapshot)` until
    `now_serving == ticket`;
  - `tryAcquire` succeeds iff `now_serving == next_ticket` at the CAS attempt;
    does not queue a ticket on failure;
  - `release` advances `now_serving` with a release fetch-add and calls
    `backend.wakeAll(&self.now_serving, new_value)`;
  - alias `stdx.sync.TicketLockSpin = TicketLock(sync.spin.Backend)` for
    spin-only callers;
  - explicit non-goals: reentrancy, timed acquire, condition-variable pairing,
    futex integration, or a `Waiter` list;
  - `acquire` is not safe from NMI/interrupt context (preempted holder stalls
    the queue); `release` is not safe from NMI; `tryAcquire` is safe from NMI
    but mixing NMI `tryAcquire` with thread `acquire` on the same lock still
    stalls the queue if the NMI is preempted mid-CAS-loop.
  No std equivalent for freestanding contexts.

- `docs/specs/mem/deferred-free-list.md` — Grace-period-safe deferred free paired with `concurrent/qsbr.md`.

  Distinct value: `std` has no primitive with this contract.

- `docs/specs/heaps/indexed-heap.md` — Indexed priority queue substrate with dense-key update, remove, and reprioritize.

  Promoted from allocation/collection follow-up. Family shape
  `Heap.Indexed.Static` and `Heap.Indexed.Bounded`. Proposal must decide:
  - key domain and invalid-key behavior;
  - priority relation via `core.traits.LessThan` unless the heap spec approves a
    narrower comparator shape;
  - exact operation names for insert, peek, pop, update, remove, and
    reprioritize;
  - no scheduler, priority-inversion, wake, or fairness policy.

### Task-system primitives — relationship to `std.Io`

Zig 0.16 owns the user-facing task, future, cancellation, sync, and I/O surface
through `std.Io` and its backends (`Io.Threaded`, `Io.Uring`, `Io.Kqueue`,
`Io.Dispatch`). `zstdx` does not ship a competing `Future`, `Executor`,
`JobSystem`, `Runtime`, `Mutex`, `RwLock`, `Semaphore`, `Condition`, `Event`,
`Timeout`, `Duration`, `Timestamp`, or fiber context primitive. It may ship
*mechanisms* that either:

1. compose inside a downstream `std.Io` backend without depending on `std.Io`
   themselves (an OS, hypervisor, or bare-metal runtime implementing its own
   `Io` vtable); or
2. serve freestanding consumers where `std.Io` is not available (kernel
   bootstrap, firmware, interrupt handlers, controller polling loops).

Every task-system spec below must declare which of those two lanes it serves.
Primitives already provided by `std.Io` are not eligible for a zstdx spec unless
a concrete freestanding or backend-implementation use demonstrates a gap.

No task-system mechanism entries remain in `Queue`.

### High-value follow-up — distinct primitive contracts

- `docs/specs/io/volatile-cell.md` — Single-value volatile publish/observe primitive only if it defines guarantees beyond bare volatile loads/stores.

- `docs/specs/rings/descriptor-ring.md` — Descriptor-ring substrate after tags, DMA, barrier, and IO contracts define lower-level behavior.

### Allocation and collection follow-up

- `docs/specs/collections/hashmap.md` — Static/bounded hash map variants with deterministic capacity and no-hidden-allocation contracts.

  Proposal must include static catalog table construction decisions before
  adding a separate string-table primitive. Must justify distinct value over
  `std.hash_map`: static/bounded no-allocator variants, deterministic capacity
  behavior, or no-hidden-allocation guarantees not covered by `std.HashMap`.

- `docs/specs/collections/hashset.md` — Hash-set family with static/bounded storage and a small-N uniqueness decision.

  Proposal must decide small-N uniqueness and any `LinearSet` split. Must
  justify distinct value over `std.hash_map`-backed sets: linear-scan
  `LinearSet` for tiny N, static/bounded storage, or contract guarantees not
  covered by `std`.

- `docs/specs/collections/slot-map.md` — Generation-checked handle map with explicit slot storage.

- `docs/specs/collections/sparse-set.md` — Dense/sparse integer-key set with caller-visible capacity contracts.

- `docs/specs/intrusive/free-list.md` — Caller-node-backed free-list primitive.

- `docs/specs/collections/deque/static.md` — Comptime fixed-capacity deque.

- `docs/specs/collections/deque/bounded.md` — Caller-storage bounded deque.

- `docs/specs/heaps/binary-heap.md` — Binary heap family with static and bounded storage variants.

  Family shape `Heap.Binary.Static` and `Heap.Binary.Bounded`, with dynamic
  variants later under `Heap.Binary.Managed` and `Heap.Binary.Unmanaged`.

- `docs/specs/collections/priority-buckets.md` — Static/bounded priority buckets for downstream schedulers without scheduling policy.

  Family shape `PriorityBuckets.Static` and `PriorityBuckets.Bounded`; mechanism
  for MLFQ-style downstream schedulers without owning scheduling policy.

- `docs/specs/heaps/d-ary-heap.md` — D-ary heap family for large-queue/cache behavior beyond binary heaps.

  Family shape `Heap.Dary.Static` and `Heap.Dary.Bounded`; add only when
  large-queue/cache behavior justifies a binary-heap alternative.

### Compiler/runtime data structures follow-up

- `docs/specs/graph/digraph.md` — Static/bounded dense directed graph for AST/SSA/CFG-style consumers.

  Family shape `Digraph.Static` and `Digraph.Bounded`; dense `NodeId`/`EdgeId`
  directed graph, with payloads stored in caller-owned side arrays or maps.

- `docs/specs/graph/traversal.md` — Caller-scratch graph traversal algorithms.

  DFS, BFS, preorder, postorder, reverse-postorder, topological traversal, and
  cycle detection over caller-provided scratch.

- `docs/specs/graph/dominators.md` — Immediate-dominator and dominator-tree algorithms for CFG/SSA consumers.

  No compiler-specific IR policy.

- `docs/specs/graph/union-find.md` — Static/bounded disjoint-set union with explicit storage and union policy contracts.

  Family shape `UnionFind.Static` and `UnionFind.Bounded`.

- `docs/specs/collections/interval-tree.md` — Static/bounded interval tree for range overlap and containment queries.

  Family shape `IntervalTree.Static` and `IntervalTree.Bounded`; queries cover
  memory maps, register windows, source spans, and liveness ranges.

- `docs/specs/intrusive/rb-tree.md` — Caller-node-backed ordered tree with pointer-stable external storage.

- `docs/specs/collections/btree.md` — Ordered B-tree map/set family.

  Family shape `BTree.Map` and `BTree.Set`; ordered map/set after simpler
  ordered structures settle.

- `docs/specs/collections/radix-tree.md` — Prefix/integer-key radix tree where prefix lookup is the contract.

- `docs/specs/collections/critbit-tree.md` — Byte-string prefix/ordered map or set for concrete prefix or lexicographic consumers.

### Synchronization, concurrency, and diagnostics

- `docs/specs/concurrent/work-stealing.md` + `docs/specs/concurrent/work-stealing/chase-lev.md` — Work-stealing deque family with Chase-Lev as the first algorithm.

  Family spec owns shared vocabulary (`Owner`, `Thief`, `PushError = error{Full}`,
  `StealError = error{ Empty, Contended }`). Proposal must decide:
  - namespace `stdx.concurrent.work_stealing` with `ChaseLev = chase_lev.Deque`
    (algorithm sub-module named `chase_lev` follows the `x86_64` two-token
    identifier precedent); future algorithms are siblings under the same family
    (`work_stealing.Abp`, `work_stealing.Cilk5`, etc.);
  - `ChaseLev.Bounded(T)` first; `ChaseLev.Static(T, N)` deferred until a
    consumer needs comptime-fixed capacity; dynamic resizing waits for a
    memory-reclamation policy (QSBR / hazard / epoch);
  - `Bounded(T)` fields: caller-provided `slots: []Slot`, plus cache-line-padded
    `bottom` and `top` `std.atomic.Value(usize)` via `stdx.mem.CachePad`;
  - operations: owner-side `push(T) PushError!void` and `pop() ?T`; thief-side
    `trySteal() StealError!T`. `pop` returns `?T` (single owner; empty is not
    an error). `trySteal` returns `error.Empty` when genuinely empty and
    `error.Contended` when the CAS lost a race with the owner or another thief;
  - single owner + many thieves is the concurrency contract; concurrent
    `push`/`pop` from two owner contexts is outside contract;
  - not NMI-safe on either side; intended for cooperative work-stealing
    schedulers.

- `docs/specs/concurrent/mpsc-queue.md` — Intrusive linked unbounded MPSC queue for no-allocation-in-queue producer paths.

  Vyukov-style linked unbounded MPSC where producers own their intrusive node.
  Complements the approved bounded `concurrent.mpsc.Ring` with an
  unbounded/no-alloc-in-queue variant. Distinct from `std.Io.Queue(T)`, which
  requires the `Io` vtable and blocks producers on full; usable inside `Io`
  backends, interrupt handlers, and freestanding schedulers.

- `docs/specs/concurrent/mpmc-ring.md` — Bounded MPMC ring with per-slot sequence numbers.

  Vyukov-style. Family shape `stdx.concurrent.mpmc.Ring` with
  `Static(T, capacity_items)` and `Bounded(T)`, symmetric to
  `stdx.concurrent.mpsc.Ring` when consumers are also multi. Proposal must
  decide:
  - namespace `stdx.concurrent.mpmc` (new sibling directory to `mpsc`);
  - `Static(T, N)` returned type mirrors `mpsc.Ring.Static` but exposes two
    symmetric operations `tryPushBack(item: T) PushError!void` and
    `tryPopFront() PopError!T`, with distinct error sets
    `PushError = error{ Full, Contended }` and
    `PopError = error{ Empty, Contended }`;
  - both `head` and `tail` are producer/consumer-shared; padding still keeps
    them on distinct cache lines via `stdx.mem.CachePad`;
  - every operation is a bounded one-attempt CAS; both sides use the shared-side
    reservation-and-publication algorithm;
  - `Bounded(T)` mirrors this with caller-provided `[]Slot`;
  - not safe from NMI or nested-producer/nested-consumer contexts on either
    side (reservation-to-publication window on both sides);
  - no `mpmc.AtomicRing` sibling yet — the multi-consumer +
    single-atomic-publication combination waits for a concrete consumer.
  Distinct from `std.Io.Queue(T)`: no vtable, no allocation, no suspend; usable
  in the same freestanding and backend-internal contexts as the MPSC ring.

- `docs/specs/diag/invariant.md` — Invariant-checking diagnostic primitive.

- `docs/specs/diag/trace-ring.md` — Fixed-storage diagnostic trace ring.

### Deferred pending distinct zstdx contract

- `docs/specs/mem/bump-allocator.md` — Bump allocator only if it has behavior beyond `std.heap.ArenaAllocator`.

- `docs/specs/layout/assert-struct-layout.md` — Struct-layout assertion workflow only if a concrete ABI/MMIO/descriptor consumer needs it.

  Deferred while it is only consolidation around `@sizeOf`, `@alignOf`, and
  `@offsetOf`.

- `docs/specs/barrier/compiler.md` — Compiler barrier only if the barrier overview approves a contract beyond exposing Zig/compiler fence syntax.

- `docs/specs/barrier/cpu-fence.md` — Cross-target CPU fence only if the barrier overview approves semantics beyond naming target fence instructions.

- `docs/specs/algo/sort.md` — Sort algorithms only if comparator, stability, bounded-memory, or model-test value differs from `std.sort`.

- `docs/specs/bits/bitflags.md` — Typed bitflags remain deferred while `std.bit_set.IntegerBitSet(N)` covers the required operations.

  Re-deferred after 2026-07 audit. Zig's `std.bit_set.IntegerBitSet(N)` already
  covers set/clear/toggle, contains, count, union/intersect/difference/xor,
  iteration, and raw-integer round-trip via `.mask`. Mixed single-bit +
  multi-bit hardware registers (RFLAGS/IOPL, CR4/PCID width, VMCS controls,
  IOMMU caps) must use `packed struct(uN)` regardless. Distinct value shrinks
  to typed-enum access + unknown-bit reporting; both are call-site sugar.
  Revisit only if `arch/x86_64/extensions.md` or `cpuid.md` surface a concrete
  unknown-bit / typed-mask friction the callsite pattern cannot answer; narrower
  framing at that point is `bits.EnumIndexSet(Enum)` owning unknown-bit
  reporting over `std.bit_set.IntegerBitSet` and nothing else.

- `docs/specs/io/register-field.md` — Register-field helpers remain deferred while `Mmio.Register(packed struct(uN))` covers named fields.

  Deferred after 2026-07 audit. `docs/specs/io/mmio.md` was amended to accept
  `T = packed struct(uN)` where `N ∈ { 8, 16, 32, 64 }`, so typed named-field
  access, reserved-bit preservation, and enum-typed bitfields are already
  available via `Register(packed struct(uN))`. Distinct value of a separate
  `Field(bit_offset, bit_width, FieldT)` wrapper shrinks to call-site sugar over
  `@bitCast(reg.load())`. Revisit only if a downstream consumer (LAPIC, HPET,
  VMCS shadow, IOMMU register bank) demonstrates a concrete friction the packed
  struct path cannot answer — e.g. field-set batching across multiple registers,
  or a Zig limitation on `packed struct` bit-layout that matters at the register
  level.

### Candidate scope additions from sibling review

These need scope approval before implementation and must justify distinct value
beyond `std` or Zig language facilities.

- `docs/specs/bytes/inline-bytes.md` — Byte storage first; add inline string semantics only if the bytes spec leaves a distinct contract.

- `docs/specs/bytes/ascii.md` — One ASCII spec unless size warrants a split such as `ascii/tag.md`.

- `docs/specs/bytes/uuid.md` — UUID bytes primitive after deciding where EFI GUID primitives belong.

- `docs/specs/bytes/checksum8.md` — Checksum8 primitive if it carries a reusable byte-level contract.

- `docs/specs/hash/crc32.md` — CRC32 primitive if it carries a reusable hashing/checksum contract.

- `docs/specs/diag/path-error-list.md` — Path-aware diagnostic error collection primitive.

### Architecture-specific follow-up

#### Other architectures

- `docs/specs/arch/aarch64.md` — AArch64 architecture primitive namespace.

- `docs/specs/arch/riscv.md` — RISC-V architecture primitive namespace.
