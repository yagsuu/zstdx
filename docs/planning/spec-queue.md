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
- `docs/specs/arch/x86_64.md`
- `docs/specs/tags/tag-allocator.md`
- `docs/specs/diag/diagnostic.md`
- `docs/specs/graph/forest.md`

## Queue

Prioritized for implementation value across sibling consumers while respecting the
first-slice limits in `docs/specs/project/scope.md`.

A proposal stays near the top only when it adds a distinct `zstdx` contract beyond
Zig language features or `std` functionality. Distinct value means explicit
allocation, ownership, capacity, invalidation, ordering, no-mutation-on-error,
target, or cross-consumer behavior that callers do not already get from Zig or
`std`. Consolidation-only wrappers are deferred until more high-value primitives
exist.

### High-value follow-up — distinct primitive contracts

- `docs/specs/sg/scatter-gather-list.md` — generic segment list or builder; no
  DMA mapping, IOMMU, cache-maintenance, or protocol descriptor policy.
- `docs/specs/barrier/overview.md` — ordering vocabulary required before IO,
  DMA, descriptor-ring, or concurrent primitives.
- `docs/specs/barrier/io-dma.md` — MMIO and DMA visibility contracts, not a
  thin wrapper around one target instruction.
- `docs/specs/io/volatile-cell.md` — only if the proposal defines access and
  ordering guarantees beyond bare volatile loads and stores.
- `docs/specs/io/mmio-register.md` — after volatile and barrier contracts; do
  not approve generic read-modify-write unless the register-kind contract makes
  side effects safe.
- `docs/specs/rings/descriptor-ring.md` — after tags, scatter/gather, barrier,
  and IO contracts define the lower-level behavior.
- `docs/specs/bits/bitflags.md` — only if the proposal adds enum-domain masks,
  unknown-bit handling, or invariant checks beyond raw integer or packed-struct
  bit operations.

### Allocation and collection follow-up

- `docs/specs/collections/hashmap.md` — include static catalog table
  construction decisions before adding a separate string-table primitive.
- `docs/specs/collections/hashset.md` — decide small-N uniqueness and any
  `LinearSet` split in this spec proposal.
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

- `docs/specs/sync/raw-spin-lock.md` — after barrier ordering vocabulary exists.
- `docs/specs/concurrent/spsc-ring.md` — after barrier ordering vocabulary
  exists.
- `docs/specs/concurrent/chase-lev-deque.md` — family shape
  `ChaseLevDeque.Bounded` first; dynamic resizing waits for memory reclamation
  policy.
- `docs/specs/diag/invariant.md`
- `docs/specs/diag/trace-ring.md`
- `docs/specs/diag/panic-log.md`

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
- `docs/specs/time/deadline.md` — defer unless a polling or concurrency
  primitive needs deadline semantics beyond caller-supplied time arithmetic.
- `docs/specs/algo/sort.md` — defer unless the proposal adds comparator,
  stability, bounded-memory, or test-model value beyond `std.sort`.

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

- `docs/specs/arch/aarch64.md`
- `docs/specs/arch/riscv.md`
