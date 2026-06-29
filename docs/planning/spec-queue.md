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
- `docs/specs/collections/list-static.md`
- `docs/specs/collections/list-bounded.md`
- `docs/specs/collections/ring-static.md`
- `docs/specs/collections/ring-bounded.md`
- `docs/specs/intrusive/list.md`
- `docs/specs/intrusive/queue.md`
- `docs/specs/intrusive/stack.md`
- `docs/specs/bytes/access.md`

## Queue

Prioritized for implementation value across sibling consumers while respecting the
first-slice limits in `docs/specs/project/scope.md`.

### First implementation slice — allocation and fixed storage


### High-value follow-up — address/page and hardware-adjacent primitives

- `docs/specs/layout/assert-struct-layout.md`
- `docs/specs/barrier/overview.md`
- `docs/specs/barrier/compiler.md`
- `docs/specs/barrier/cpu-fence.md`
- `docs/specs/barrier/io-dma.md`
- `docs/specs/io/volatile-cell.md`
- `docs/specs/io/mmio-register.md`
- `docs/specs/sg/scatter-gather-list.md`
- `docs/specs/tags/tag-allocator.md`
- `docs/specs/rings/descriptor-ring.md`
- `docs/specs/time/deadline.md`
- `docs/specs/bits/bitflags.md`

### Allocation and collection follow-up

- `docs/specs/mem/pool-allocator.md`
- `docs/specs/mem/bitmap-allocator.md`
- `docs/specs/collections/deque-static.md`
- `docs/specs/collections/deque-bounded.md`
- `docs/specs/intrusive/free-list.md`
- `docs/specs/collections/hashmap.md` — include static catalog table
  construction decisions before adding a separate string-table primitive.
- `docs/specs/collections/hashset.md` — decide small-N uniqueness and any
  `LinearSet` split in this spec proposal.
- `docs/specs/collections/slot-map.md`
- `docs/specs/collections/sparse-set.md`
- `docs/specs/heaps/binary-heap.md`

### Algorithms follow-up

- `docs/specs/algo/sort.md` — comparator-builder shape is decided by this spec.

### Deferred pending distinct zstdx contract

- `docs/specs/mem/bump-allocator.md` — do not spec unless it has
  behavior or guarantees beyond `std.heap.ArenaAllocator`.

### Synchronization, concurrency, and diagnostics

- `docs/specs/sync/raw-spin-lock.md`
- `docs/specs/concurrent/spsc-ring.md`
- `docs/specs/diag/invariant.md`
- `docs/specs/diag/trace-ring.md`
- `docs/specs/diag/panic-log.md`

### Candidate scope additions from sibling review

These need scope approval before implementation.

- `docs/specs/bytes/inline-bytes.md` — byte storage first; add inline string
  semantics only if the bytes spec leaves a distinct contract.
- `docs/specs/bytes/ascii.md` — keep one ASCII spec unless size warrants a
  `docs/specs/bytes/ascii/` split such as `ascii/tag.md`.
- `docs/specs/bytes/uuid.md` — proposal must decide where EFI GUID primitives
  belong before adding EFI-specific API.
- `docs/specs/bytes/checksum8.md`
- `docs/specs/hash/crc32.md`
- `docs/specs/diag/diagnostic.md`
- `docs/specs/diag/path-error-list.md`

### Architecture-specific follow-up

- `docs/specs/arch/x86.md`
- `docs/specs/arch/aarch64.md`
- `docs/specs/arch/riscv.md`
