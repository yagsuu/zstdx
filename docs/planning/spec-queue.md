# Spec queue

This document is planning material. Normative requirements live only under `docs/specs/` after user approval.

## Workflow

1. Pick the next item from `Queue`.
2. Present a concise decision proposal to the user before writing:
   - decision points and recommended answers;
   - owned scope and non-goals;
   - public namespace/type shape;
   - semantic contracts;
   - planned primitive list when the spec is a category/overview;
   - open questions.
3. Wait for explicit approval.
4. Write the approved spec under `docs/specs/`.
5. Move the item from `Queue` to `Approved`.
6. Repeat.

Implementation work begins only after the required specs for that slice are approved and written.

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

## Approved

- `docs/specs/project/scope.md`
- `docs/specs/architecture.md`
- `docs/specs/root-exports.md`
- `docs/specs/core/options.md`
- `docs/specs/core/traits.md`
- `docs/specs/core/range.md`
- `docs/specs/core/debug.md`
- `docs/specs/bits/power-of-two.md`
- `docs/specs/mem/alignment.md`
- `docs/specs/bits/bitset-static.md`
- `docs/specs/addr/address.md`
- `docs/specs/addr/pages.md`
- `docs/specs/ranges/range-set.md`
- `docs/specs/ranges/range-map.md`
- `docs/specs/bytes/unaligned.md`
- `docs/specs/layout/endian.md`
- `docs/specs/bytes/cursor.md`
- `docs/specs/mem/arena-bounded.md`
- `docs/specs/mem/arena-static.md`
- `docs/specs/mem/pool.md`
- `docs/specs/mem/bitmap-allocator.md`
- `docs/specs/collections/list-static.md`
- `docs/specs/collections/list-bounded.md`
- `docs/specs/collections/ring-static.md`
- `docs/specs/collections/ring-bounded.md`
- `docs/specs/intrusive/list.md`
- `docs/specs/intrusive/queue.md`
- `docs/specs/intrusive/stack.md`
- `docs/specs/bytes/access.md`
- `docs/specs/algo/allocation.md`
- `docs/specs/arch/x86_64/base.md`
- `docs/specs/tags/tag-allocator.md`
- `docs/specs/diag/diagnostic.md`
- `docs/specs/graph/forest.md`
- `docs/specs/barrier/overview.md`
- `docs/specs/io/mmio.md`
- `docs/specs/barrier/dma.md`
- `docs/specs/concurrent/mpsc-ring.md`
- `docs/specs/sync/signal.md`
- `docs/specs/time/monotonic.md`
- `docs/specs/dma/buffer.md`
- `docs/specs/dma/scatter-gather.md`
- `docs/specs/mem/cache.md`
- `docs/specs/concurrent/spsc-ring.md`
- `docs/specs/sync/spin.md`
- `docs/specs/sync/once.md`
- `docs/specs/sync/atomic-cell.md`
- `docs/specs/time/deadline.md`
- `docs/specs/time/backoff.md`
- `docs/specs/arch/x86_64/extensions.md`
- `docs/specs/arch/x86_64/cpuid.md`
- `docs/specs/cpu/per-cpu.md`
- `docs/specs/sync/raw-spin-lock.md`

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

Wave 1 — CPU-facing baseline:

1. `docs/specs/sync/rendezvous.md` — reusable N-way rendezvous (cyclic
    barrier). `Static(N)` and `Bounded` variants. `arrive` blocks until N
    callers have arrived at the current generation; upon release, the
    generation counter advances and the primitive is reusable for the next
    round. Uses the same caller-composed `Backend` seam as
    `docs/specs/sync/signal.md` for the wait step. Distinct value: no `std`
    rendezvous primitive, no scheduler assumption, usable in freestanding SMP
    bring-up rounds and multi-worker fan-in contexts. Owns only the counter,
    arrival protocol, generation rollover, and wait composition; does not own
    SMP bring-up, INIT/SIPI, per-AP stack allocation, or scheduler parking.
2. `docs/specs/sync/latch.md` — one-shot countdown latch. `Static(N)` and
    `Bounded` variants. `arrive` decrements the remaining counter; `wait`
    blocks until the counter reaches zero; once released, the latch stays
    released and is not reusable. Uses the same caller-composed `Backend`
    seam. Distinct value from `sync/rendezvous.md`: latches model
    grace-period joins, one-time initialization joins, and multi-producer
    completion signals where reuse is not required. Owns only the counter,
    arrival protocol, and wait composition; does not own reset, scheduler
    parking, or per-arrival policy.

Wave 2 — device + memory primitives:

2. `docs/specs/io/register-field.md` — typed bitfield extract/insert over
    `io.Mmio.Register` for LAPIC, HPET, VMCS shadow, IOMMU register banks.
    Proposal must decide:
    - factory shape:
      `Mmio.Register(T).Field(comptime bit_offset: comptime_int, comptime bit_width: comptime_int, comptime FieldT: type)`
      returning a typed extract/insert view;
    - `read` performs a single volatile MMIO load of the underlying
      `Register(T)` and returns a `FieldT` shifted+masked value; `write`
      performs a single volatile MMIO store using a caller-supplied full
      `T` value that already carries the field, or a read-modify-write
      convenience that is explicitly documented as **not atomic**
      (caller-serialized per register);
    - `modify(mutator: fn (T) T) void` exists as the convenience RMW
      shape and is likewise not atomic; the spec must state this at each
      operation site;
    - composition with `layout.Le(T)` / `layout.Be(T)`;
    - compile-time bounds check `bit_offset + bit_width <= @sizeOf(T) * 8`;
    - compile-time rejection of field types whose bit width does not match
      `bit_width` (e.g. `FieldT = u3` requires `bit_width == 3`);
    - explicit non-goal: cross-CPU RMW atomicity. Consumers who need atomic
      bit-set/clear on shared registers (rare on x86_64 MMIO) hand-roll the
      correct instruction sequence outside this primitive.
    Distinct from `std.PackedIntArray`: MMIO-load/store-aware, composes with
    existing `io.Mmio.Register` load/store discipline.
3. `docs/specs/io/poll-until.md` — wait-for-bit / wait-for-value poll loop
    composed with `time.Deadline` and `time.Backoff`. Proposal must decide:
    - core signature:

      ```zig
      pub fn until(
          clock: anytype,
          deadline: Deadline,
          backoff: *time.Backoff,
          predicate: anytype, // fn () PredicateError!?T
      ) PollError!T;
      ```

    - error-union shape: `PollError = error{Timeout} || PredicateError`;
    - success returns the payload `T` produced by the predicate;
    - predicate errors propagate unchanged (not wrapped);
    - deadline expiry returns `error.Timeout` from `Deadline.expireBy`;
    - progress rule: exactly one predicate poll runs before the first
      deadline check, so a `Deadline.at(clock.now())` still gets one chance
      to observe a completed device state;
    - `backoff.pause(clock)` is called between polls, not before the first
      poll;
    - explicit non-goal: no built-in `error.Aborted` — cancellation is
      caller policy via a predicate that returns its own error variant.
    Distinct value: no freestanding equivalent in `std`.
4. `docs/specs/mem/buddy-allocator.md` — multi-order (4 KiB / 2 MiB / 1 GiB or
    caller-defined) buddy allocator over a caller-supplied backing region.
    Zero-hidden-allocation, deterministic, freestanding-safe. Proposal must
    decide:
    - API shape:

      ```zig
      pub fn Buddy(
          comptime BackingT: type,
          comptime order_count: usize,
      ) type;
      ```

      returning an allocator over a caller-supplied backing region of
      `BackingT` blocks (typically page-sized), with `order_count` distinct
      power-of-two orders;
    - allocation unit is `Order` = log2(2^k * base_block), not raw bytes;
    - `alloc(order)` returns `error.OutOfMemory` when no free block of that
      order exists and no larger block can be split to satisfy it;
    - `alloc(order)` returns a distinct `error.Fragmented` when a larger
      block exists but no coalesce would satisfy the request — that is, the
      caller could retry after freeing a peer;
    - coalescing runs eagerly on `free` — no deferred merge queue, no
      background sweep;
    - free-order invariant: caller must `free(ptr, order)` at the same
      `order` used at `alloc`. Violation is a programmer error asserted
      under `stdx.core.debug.checksEnabled(.build_mode)`;
    - reserved regions are supported via `reserve(range: Range) !void` at
      init only; post-init reserves are outside the primitive's contract;
    - explicit non-goals: NUMA locality, per-CPU caches, dynamic backing
      growth, coalesce policies other than eager, and defragmentation.
    Distinct from `std.heap`: byte-granular std allocators cannot serve
    page-tier allocation.
5. `docs/specs/diag/panic-log.md` — panic-safe ring log sink usable from
    panic and NMI contexts. Owned separately from `diag/trace-ring.md`
    because the panic contract is stricter (single-writer at any instant,
    IRQ/NMI-safe, never blocks). Proposal must decide:
    - shape `PanicLog.Static(capacity_bytes: usize)` returning a byte-ring
      backing plus a monotonic `seq` counter;
    - writer discipline: strictly single-writer at any instant. Writers
      acquire an atomic `writer_slot` seat with a bounded try-CAS. On
      contention `write` returns `error.WriterBusy` and drops the message —
      panic paths never block waiting for the seat;
    - message format: length-prefixed `[u32 len][u32 seq][bytes]`. `len`
      excludes the header; `seq` is the monotonic sequence at write time;
    - IRQ writers and NMI writers use the same seat CAS. The CAS itself is
      NMI-safe by construction: a single-word atomic with no reservation
      window and no reserved-but-unpublished state;
    - reader drain: `drain(reader_state: *DrainState, sink: *std.Io.Writer)
      !void`, single reader, does not block writers. Reader is exempt from
      the seat CAS; it walks the ring under a snapshot of `seq` and stops
      when it catches up;
    - drop counter: dropped writes (both `WriterBusy` and byte-overflow
      overwrites) increment a monotonic `dropped_seq` counter visible to
      the reader;
    - no allocation, no locks that can be held during panic, no formatting
      inside the sink;
    - explicit non-goals: multi-CPU flush ordering, log persistence,
      formatted logging — the ring stores raw bytes only; formatting and
      any structured layout are caller policy.

Wave 3 — hv-specific:

6. `docs/specs/arch/x86_64/vmx.md` — VMX ISA wrappers: `vmxon`/`vmxoff`/
    `vmlaunch`/`vmresume`/`vmread`/`vmwrite`/`vmclear`/`vmptrld`/`vmptrst`/
    `invept`/`invvpid` as inline-asm helpers. Same "just the ISA" boundary
    as base. No VMCS field catalog, no VMCS layout policy. Proposal must
    decide:
    - error typing: `Error = error{ VMfailInvalid, VMfailValid }` derived
      from `RFLAGS` after each VMX instruction (`CF = 1` →
      `VMfailInvalid`; `ZF = 1` → `VMfailValid`; neither → success). The
      wrapper does not decode `VMfailValid`; callers who need the error
      code call `vmread(0x4400)`;
    - physical-address argument shape:
      `PhysAddr = enum(u64) { _ }`;
    - VMCS/VMXON region types are 4 KiB `extern struct`s declared with
      `align(4096)` and a `pub const alignment: usize = 4096`;
    - INVEPT/INVVPID descriptors are 16-byte `extern struct`s declared
      with `align(16)` and a `pub const alignment: usize = 16`; kinds are
      `enum(u64)`;
    - `vmread`/`vmwrite` take a raw `u32` field encoding per Intel SDM
      natural-index encoding — no typed field catalog;
    - `vmlaunch`/`vmresume` return type `Error!noreturn`; on success control
      transfers to the guest and re-enters at the caller-installed host RIP
      outside this wrapper;
    - `vmxon`/`vmclear`/`vmptrld`/`vmptrst` take `*const PhysAddr` /
      `*PhysAddr` (m64 physical-pointer operand), not `PhysAddr` by value;
    - VMX instructions are CPL 0; `#GP` at CPL > 0 and `#UD` when VMX is
      unsupported are traps, not error-union failures;
    - required tests are compile-only in the default host suite (regions
      have the declared size/alignment, descriptors have the declared
      size/alignment, `vmlaunch`/`vmresume` are `Error!noreturn`, module
      compiles on x86_64, non-x86_64 build either omits or `@compileError`s).
7. `docs/specs/arch/x86_64/svm.md` — SVM ISA wrappers: `vmrun`/`vmload`/
    `vmsave`/`stgi`/`clgi`/`invlpga`/`skinit` as inline-asm helpers. Same
    "just the ISA" boundary as VMX. No VMCB field catalog, no VMCB layout
    policy. Proposal must decide:
    - error typing: SVM does not use the VMX `RFLAGS.CF/ZF` convention.
      Faults manifest as CPU exceptions (`#UD` when `EFER.SVME = 0` or
      SVM is unsupported; `#GP` on CR4/VMCB rule violations). Wrappers are
      infallible in the Zig signature — same convention as `hlt`/`wbinvd`;
    - physical-address argument shape: `PhysAddr = enum(u64) { _ }`, passed
      by value (SVM instructions take the physical address in `RAX`, not a
      memory-indirect operand);
    - VMCB is a 4 KiB `extern struct` declared with `align(4096)` and a
      `pub const alignment: usize = 4096`; the wrapper exposes size and
      alignment only, leaving the control-area / state-save-area layout as
      opaque byte arrays for downstream hypervisor projects to overlay;
    - `vmrun` and `skinit` return type `noreturn`;
    - `vmload`, `vmsave`, `stgi`, `clgi`, `invlpga` return type `void`;
    - `invlpga(virt_addr: u64, asid: u32)` — no ASID typing; ASID
      allocation is caller policy;
    - every SVM instruction uses inline asm with a memory clobber, matching
      the VMX and DebugRegister wrapper convention (`stgi`/`clgi` need the
      memory clobber to bracket sensitive host code correctly);
    - required tests are compile-only in the default host suite
      (`@sizeOf(Vmcb) == 4096` and `@alignOf(Vmcb) == 4096`, `vmrun`/
      `skinit` are `noreturn`, `vmload`/`vmsave`/`stgi`/`clgi`/`invlpga`
      are `void`, module compiles on x86_64, non-x86_64 build either omits
      or `@compileError`s).
8. `docs/specs/concurrent/mpsc-atomic-ring.md` — single-atomic-publication
    MPSC ring, sibling to `docs/specs/concurrent/mpsc-ring.md` under the
    same `mpsc` namespace. Not a mode flag on `Ring`. Publishes an item
    in one atomic step (packed sequence tag + payload in a single CAS on
    a per-slot `std.atomic.Value(u64)`), so a producer preempted at any
    point leaves the ring in a legal state — no reserved-but-unpublished
    window. Proposal must decide:
    - name is `concurrent.mpsc.AtomicRing`, and it names the mechanism
      (single-atomic publication), not caller context. NMI safety is a
      consequence of the mechanism, not the name;
    - shape: `AtomicRing.Static(comptime T: type, comptime capacity_items:
      usize)` and `AtomicRing.Bounded(comptime T: type)`, matching `Ring`'s
      family shape;
    - each `Slot` is `cell: std.atomic.Value(u64)` packing sequence tag
      and payload; the tag reserves at least 32 bits so wrap-around does
      not alias within the ring's lifetime;
    - `T` must fit in `64 - tag_bits`; larger payloads use `Ring`;
    - `head` and `tail` are cache-line-padded via `stdx.mem.CachePad`,
      matching correction 15's discipline on `Ring`;
    - `tryPushBack` performs exactly one CAS on the target slot; `Full`
      when the slot's sequence tag says "not yet free"; `Contended` when
      the CAS loses the race;
    - `popFront` matches `Ring.popFront`'s execution-context freedom
      (single owner, no CAS participation), and remains safe from any
      execution context including NMI;
    - cross-reference from `docs/specs/concurrent/mpsc-ring.md` (correction
      16's NMI-safe sibling pointer) is repointed at
      `docs/specs/concurrent/mpsc-atomic-ring.md`;
    - zero-allocation, bounded, no policy on wake or scheduler.
9. `docs/specs/concurrent/qsbr.md` — quiescent-state-based reclamation
    substrate. Answers the "rcu-lite" need for exit-handler tables and mapping
    updates. Simplest of the four reclamation candidates (`epoch`, `hazard`,
    `qsbr`, `rcu`) and enough for the stated bounded-quiescent-state use case.
    `hazard`, `epoch`, and `rcu` stay deferred until a second consumer needs a
    different reclamation model.

Additional non-waved head-of-queue additions (distinct hv/kernel value, no
strict ordering dependency):

- `docs/specs/sync/seq-lock.md` — read-mostly RMW-avoiding lock guarded by a
  monotonic sequence counter. Single-writer / many-reader; readers spin on
  the counter and never block writers. Proposal must decide:
  - shape `stdx.sync.SeqLock` with cache-line-padded
    `seq: stdx.mem.CachePad(std.atomic.Value(u64))`;
  - odd `seq` means "write in progress", even means "quiescent";
  - operations `beginWrite`/`endWrite` (writer, `fetchAdd(1, .acq_rel)` and
    `fetchAdd(1, .release)`), `beginRead`/`endRead` (reader retry loop),
    and `tryRead(max_retries, payload, comptime body, comptime T)` canned
    retry helper;
  - `ReadError = error{Contended}` is the entire error set; `endRead`
    returns `error.Contended` if `seq` changed since `beginRead` or if
    `beginRead` observed an odd counter;
  - payload storage is caller-owned (non-atomic ordinary storage); the
    seqlock guards access ordering only;
  - writers are externally serialized against other writers (use
    `RawSpinLock`, a mutex, or a ticket lock outside the seqlock);
  - explicit non-goals: writer-writer arbitration, payload storage,
    priority-inversion policy, futex parking, scheduler yielding;
  - reader is safe from NMI/interrupt context (bounded retries under
    `tryRead`); writer is not safe from NMI — a preempted writer between
    `beginWrite` and `endWrite` stalls readers indefinitely.
  Distinct from any `std` primitive; reader guarantees checked by unit,
  model, and stress tests.
- `docs/specs/sync/ticket-lock.md` — fair (FIFO) spinlock family next to
  `RawSpinLock`. Proposal must decide:
  - shape `stdx.sync.TicketLock(Backend)` following the shared wait-capable
    backend seam (matches `Signal.Manual(Backend)`, `Once(Backend)`,
    `Rendezvous(Backend)`, `Latch(Backend)`);
  - cache-line-padded `next_ticket` and `now_serving`
    (`std.atomic.Value(u32)` each) via `stdx.mem.CachePad`;
  - `Ticket = u32`, `WaitError = Backend.WaitError`;
  - operations `acquire(self) WaitError!void`,
    `tryAcquire(self) bool`, `release(self) void`;
  - `acquire` draws a ticket via `next_ticket.fetchAdd(1, .acq_rel)` and
    loops calling `backend.wait(&self.now_serving, snapshot)` until
    `now_serving == ticket`;
  - `tryAcquire` succeeds iff `now_serving == next_ticket` at the CAS
    attempt; does not queue a ticket on failure;
  - `release` advances `now_serving` with a release fetch-add and calls
    `backend.wakeAll(&self.now_serving, new_value)`;
  - alias `stdx.sync.TicketLockSpin = TicketLock(sync.spin.Backend)` for
    spin-only callers;
  - explicit non-goals: reentrancy, timed acquire, condition-variable
    pairing, futex integration, or a `Waiter` list;
  - `acquire` is not safe from NMI/interrupt context (preempted holder
    stalls the queue); `release` is not safe from NMI; `tryAcquire` is
    safe from NMI but mixing NMI `tryAcquire` with thread `acquire` on
    the same lock still stalls the queue if the NMI is preempted
    mid-CAS-loop.
  No std equivalent for freestanding contexts.
- `docs/specs/mem/deferred-free-list.md` — grace-period-safe deferred free,
  pairs with `concurrent/qsbr.md`. Distinct value: `std` has no primitive
  with this contract.

### Task-system primitives — relationship to `std.Io`

Zig 0.16 owns the user-facing task, future, cancellation, sync, and I/O
surface through `std.Io` and its backends (`Io.Threaded`, `Io.Uring`,
`Io.Kqueue`, `Io.Dispatch`). `zstdx` does not ship a competing `Future`,
`Executor`, `JobSystem`, `Runtime`, `Mutex`, `RwLock`, `Semaphore`,
`Condition`, `Event`, `Timeout`, `Duration`, `Timestamp`, or fiber
context primitive. It may ship *mechanisms* that either:

1. compose inside a downstream `std.Io` backend without depending on
   `std.Io` themselves (an OS, hypervisor, or bare-metal runtime
   implementing its own `Io` vtable); or
2. serve freestanding consumers where `std.Io` is not available (kernel
   bootstrap, firmware, interrupt handlers, controller polling loops).

Every task-system spec below must declare which of those two lanes it
serves. Primitives already provided by `std.Io` are not eligible for a
zstdx spec unless a concrete freestanding or backend-implementation use
demonstrates a gap.

### High-value follow-up — distinct primitive contracts

- `docs/specs/io/volatile-cell.md` — only if the proposal defines access and
  ordering guarantees beyond bare volatile loads and stores.
- `docs/specs/rings/descriptor-ring.md` — after tags, DMA, barrier, and IO
  contracts define the lower-level behavior.

### Callable primitives

- `docs/specs/func/callback.md` — `stdx.func.Callback(Signature)` as a
  `{context, invoke}` pair specialized on a comptime function signature,
  `stdx.func.Closure(Signature, inline_bytes)` with comptime-verified
  inline captured state, and `stdx.func.BoundMethod(T, method_name)` as a
  factory that lifts `*T`+method into a matching `Callback`. Zero
  allocation, caller-owned context lifetime. Distinct value over `std`:
  no general callback primitive exists there — every consumer hand-rolls
  the vtable trick. `std.Io` is a fat interface, not a lightweight
  signature-typed callback. Namespace is `stdx.func` because `fn` is a
  Zig keyword.

### Allocation and collection follow-up

- `docs/specs/collections/hashmap.md` — include static catalog table
  construction decisions before adding a separate string-table primitive.
  Must justify distinct value over `std.hash_map`: static/bounded
  no-allocator variants, deterministic capacity behavior, or
  no-hidden-allocation guarantees not covered by `std.HashMap`.
- `docs/specs/collections/hashset.md` — decide small-N uniqueness and any
  `LinearSet` split in this spec proposal. Must justify distinct value
  over `std.hash_map`-backed sets: linear-scan `LinearSet` for tiny N,
  static/bounded storage, or contract guarantees not covered by `std`.
- `docs/specs/collections/slot-map.md`
- `docs/specs/collections/sparse-set.md`
- `docs/specs/intrusive/free-list.md`
- `docs/specs/collections/deque-static.md`
- `docs/specs/collections/deque-bounded.md`
- `docs/specs/heaps/binary-heap.md` — family shape
  `Heap.Binary.Static` and `Heap.Binary.Bounded`, with dynamic variants later
  under `Heap.Binary.Managed` and `Heap.Binary.Unmanaged`.
- `docs/specs/heaps/indexed-heap.md` — family shape
  `Heap.Indexed.Static` and `Heap.Indexed.Bounded`; supports update, remove,
  and reprioritize by dense key.
- `docs/specs/collections/priority-buckets.md` — family shape
  `PriorityBuckets.Static` and `PriorityBuckets.Bounded`; mechanism for
  MLFQ-style downstream schedulers without owning scheduling policy.
- `docs/specs/heaps/d-ary-heap.md` — family shape `Heap.Dary.Static` and
  `Heap.Dary.Bounded`; add only when large-queue/cache behavior justifies a
  binary-heap alternative.

### Compiler/runtime data structures follow-up

- `docs/specs/graph/digraph.md` — family shape `Digraph.Static` and
  `Digraph.Bounded`; dense `NodeId`/`EdgeId` directed graph for AST/SSA/CFG-style
  consumers, with payloads stored in caller-owned side arrays or maps.
- `docs/specs/graph/traversal.md` — DFS, BFS, preorder, postorder,
  reverse-postorder, topological traversal, and cycle detection over
  caller-provided scratch.
- `docs/specs/graph/dominators.md` — immediate dominators and dominator tree for
  CFG/SSA consumers; no compiler-specific IR policy.
- `docs/specs/graph/union-find.md` — family shape `UnionFind.Static` and
  `UnionFind.Bounded`; disjoint-set union with explicit storage and union policy
  contracts.
- `docs/specs/collections/interval-tree.md` — family shape
  `IntervalTree.Static` and `IntervalTree.Bounded`; range overlap and containment
  queries for memory maps, register windows, source spans, and liveness ranges.
- `docs/specs/intrusive/rb-tree.md` — caller-node-backed ordered tree when
  pointer stability and external storage ownership matter.
- `docs/specs/collections/btree.md` — family shape `BTree.Map` and `BTree.Set`;
  ordered map/set after simpler ordered structures settle.
- `docs/specs/collections/radix-tree.md` — prefix/integer-key structure where
  prefix lookup is the contract.
- `docs/specs/collections/critbit-tree.md` — byte-string prefix/ordered map or
  set only with a concrete prefix or lexicographic consumer.

### Synchronization, concurrency, and diagnostics

`sync/raw-spin-lock.md`, `sync/rendezvous.md`, `sync/latch.md`,
`concurrent/per-cpu.md`, `concurrent/mpsc-atomic-ring.md`, and
`diag/panic-log.md` are promoted to the head-of-queue waves above.

- `docs/specs/concurrent/work-stealing.md` +
  `docs/specs/concurrent/work-stealing/chase-lev.md` — work-stealing deque
  family. Family spec owns shared vocabulary (`Owner`, `Thief`,
  `PushError = error{Full}`, `StealError = error{ Empty, Contended }`);
  the Chase-Lev spec is the first algorithm to land. Proposal must
  decide:
  - namespace `stdx.concurrent.work_stealing` with `ChaseLev = chase_lev.Deque`
    (algorithm sub-module named `chase_lev` follows the `x86_64` two-token
    identifier precedent); future algorithms are siblings under the same
    family (`work_stealing.Abp`, `work_stealing.Cilk5`, etc.);
  - `ChaseLev.Bounded(T)` first; `ChaseLev.Static(T, N)` deferred until a
    consumer needs comptime-fixed capacity; dynamic resizing waits for a
    memory-reclamation policy (QSBR / hazard / epoch);
  - `Bounded(T)` fields: caller-provided `slots: []Slot`, plus
    cache-line-padded `bottom` and `top` `std.atomic.Value(usize)` via
    `stdx.mem.CachePad`;
  - operations: owner-side `push(T) PushError!void` and `pop() ?T`; thief-
    side `trySteal() StealError!T`. `pop` returns `?T` (single owner; empty
    is not an error). `trySteal` returns `error.Empty` when genuinely
    empty and `error.Contended` when the CAS lost a race with the owner or
    another thief;
  - single owner + many thieves is the concurrency contract; concurrent
    `push`/`pop` from two owner contexts is outside contract;
  - not NMI-safe on either side; intended for cooperative work-stealing
    schedulers.
- `docs/specs/concurrent/mpsc-queue.md` — Vyukov-style linked unbounded
  MPSC where producers own their intrusive node. Complements the approved
  bounded `concurrent.mpsc.Ring` with an unbounded/no-alloc-in-queue
  variant. Distinct from `std.Io.Queue(T)`, which requires the `Io`
  vtable and blocks producers on full; usable inside `Io` backends,
  interrupt handlers, and freestanding schedulers.
- `docs/specs/concurrent/mpmc-ring.md` — bounded MPMC ring with per-slot
  sequence numbers (Vyukov). Family shape `stdx.concurrent.mpmc.Ring`
  with `Static(T, capacity_items)` and `Bounded(T)`, symmetric to
  `stdx.concurrent.mpsc.Ring` when consumers are also multi. Proposal
  must decide:
  - namespace `stdx.concurrent.mpmc` (new sibling directory to `mpsc`);
  - `Static(T, N)` returned type mirrors `mpsc.Ring.Static` but exposes
    two symmetric operations `tryPushBack(item: T) PushError!void` and
    `tryPopFront() PopError!T`, with distinct error sets
    `PushError = error{ Full, Contended }` and
    `PopError = error{ Empty, Contended }`;
  - both `head` and `tail` are producer/consumer-shared; padding still
    keeps them on distinct cache lines via `stdx.mem.CachePad`;
  - every operation is a bounded one-attempt CAS; both sides use the
    shared-side reservation-and-publication algorithm;
  - `Bounded(T)` mirrors this with caller-provided `[]Slot`;
  - not safe from NMI or nested-producer/nested-consumer contexts on
    either side (reservation-to-publication window on both sides);
  - no `mpmc.AtomicRing` sibling yet — the multi-consumer +
    single-atomic-publication combination waits for a concrete
    consumer.
  Distinct from `std.Io.Queue(T)`: no vtable, no allocation, no
  suspend; usable in the same freestanding and backend-internal
  contexts as the MPSC ring.
- `docs/specs/diag/invariant.md`
- `docs/specs/diag/trace-ring.md`

### Deferred pending distinct zstdx contract

- `docs/specs/mem/bump-allocator.md` — do not spec unless it has behavior or
  guarantees beyond `std.heap.ArenaAllocator`.
- `docs/specs/layout/assert-struct-layout.md` — defer while it is only
  consolidation around `@sizeOf`, `@alignOf`, and `@offsetOf`; revisit when a
  concrete ABI/MMIO/descriptor consumer needs a stronger assertion workflow.
- `docs/specs/barrier/compiler.md` — write only if the barrier overview approves
  a contract beyond exposing Zig/compiler fence syntax.
- `docs/specs/barrier/cpu-fence.md` — write only if the barrier overview
  approves cross-target semantics beyond naming target fence instructions.
- `docs/specs/algo/sort.md` — defer unless the proposal adds comparator,
  stability, bounded-memory, or test-model value beyond `std.sort`.
- `docs/specs/bits/bitflags.md` — re-deferred after 2026-07 audit. Zig's
  `std.bit_set.IntegerBitSet(N)` already covers set/clear/toggle, contains,
  count, union/intersect/difference/xor, iteration, and raw-integer
  round-trip via `.mask`. Mixed single-bit + multi-bit hardware registers
  (RFLAGS/IOPL, CR4/PCID width, VMCS controls, IOMMU caps) must use
  `packed struct(uN)` regardless. Distinct value shrinks to typed-enum
  access + unknown-bit reporting; both are call-site sugar. Revisit only
  if `arch/x86_64/extensions.md` or `cpuid.md` surface a concrete
  unknown-bit / typed-mask friction the callsite pattern cannot answer;
  narrower framing at that point is `bits.EnumIndexSet(Enum)` owning
  unknown-bit reporting over `std.bit_set.IntegerBitSet` and nothing else.

### Candidate scope additions from sibling review

These need scope approval before implementation and must justify distinct value
beyond `std` or Zig language facilities.

- `docs/specs/bytes/inline-bytes.md` — byte storage first; add inline string
  semantics only if the bytes spec leaves a distinct contract.
- `docs/specs/bytes/ascii.md` — keep one ASCII spec unless size warrants a
  `docs/specs/bytes/ascii/` split such as `ascii/tag.md`.
- `docs/specs/bytes/uuid.md` — proposal must decide where EFI GUID primitives
  belong before adding EFI-specific API.
- `docs/specs/bytes/checksum8.md`
- `docs/specs/hash/crc32.md`
- `docs/specs/diag/path-error-list.md`

### Architecture-specific follow-up

`arch/x86_64/extensions.md`, `arch/x86_64/cpuid.md`, `arch/x86_64/vmx.md`,
and `arch/x86_64/svm.md` are promoted to the head-of-queue waves above and
carry their full decision notes there.

Other architectures:

- `docs/specs/arch/aarch64.md`
- `docs/specs/arch/riscv.md`
