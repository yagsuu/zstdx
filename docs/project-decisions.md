# Spec status and approval rules

## Purpose

This repository separates approved requirements from draft proposals. The initial primitive-library plan is planning input only; it is not a formal implementation contract until individual specs under `docs/specs/` are drafted with the user and approved.

## Status labels

Use these labels in specs and planning documents:

- **Approved**: accepted project fact or decision.
- **Draft proposal**: candidate design for review; do not implement as fixed contract yet.
- **Open question**: unresolved information; implementation must not guess.
- **Deferred**: intentionally out of the current target.

## Approved facts so far

### Project

- The final package/import name is `zstdx`.
- `zstdx` is intended to be a high-performance Zig primitive library.
- `zstdx` is domain-neutral: kernels, hypervisors, firmware, drivers, runtimes, game engines, compilers, storage systems, and high-performance userspace code are valid consumers.
- `zstdx` owns reusable primitives: allocators, collections, intrusive structures, synchronization primitives, barriers, strong address/size/page types, layout helpers, byte helpers, rings, tags, scatter/gather helpers, diagnostics, and tests.
- `zstdx` does not own domain-specific systems such as PCI enumeration, NVMe controllers, ACPI parsers, UEFI protocol wrappers, filesystems, block layers, IOMMU backends, or hypervisor VM-control logic.
- Domain-specific systems belong in downstream packages such as `zpci`, `zacpi`, `zfw`, `znvme`, `zfat`, `ziommu`, `zhv`, and `zvirtio`.

### Design constraints

- Public APIs must not hide allocation.
- Public APIs must not hide blocking, sleeping, or spinning.
- Static, bounded, intrusive, and no-allocator variants are first-class where practical.
- Runtime behavior is part of every non-trivial primitive's contract.
- Ownership, pointer stability, index stability, iteration order, invalidation rules, and full-capacity behavior must be explicit.
- Atomic ordering, compiler barriers, CPU fences, MMIO barriers, DMA barriers, and architecture-specific ordering helpers must be explicit.
- Architecture-specific pieces must stay isolated behind documented module boundaries.
- Debug invariant checks and tests are part of the primitive contract.

### Approved API direction

- Root exports should promote flagship collection families after their owning specs approve the exact surface. Namespace homes remain canonical.
- `Bounded` is a first-class capacity category for caller-provided or runtime fixed storage that does not grow by allocation.
- `Small` containers are deferred until a dedicated spec resolves inline storage plus optional spill behavior.
- `PhysAddr` and `VirtAddr` are approved built-in aliases once `addr/address.md` approves the generic address tag model.
- Barriers and fences are deferred from the first implementation slice.
- Runtime metadata types are not approved without a concrete consumer; behavior contracts are specified in per-primitive docs instead.
- `SafetyMode` is approved; `GrowthPolicy`, `PoisonPolicy`, and `StatsPolicy` are deferred until concrete consumers need them.
- Core trait callbacks are approved as zero-allocation function type factories under `zstdx.core`, not runtime trait objects.
- `core.debug.checksEnabled` is approved as the only shared debug helper; `assertValid` remains a per-type method convention.
- Power-of-two helpers are owned by `bits`; memory alignment helpers are owned by `mem`.

### Docs flow

- A module without its owning approved spec does not land.
- Each spec is drafted with the user one by one before it is written under `docs/specs/`.
- Implementation work starts only after the required specs for that implementation slice are approved and written.

## Not approved yet

The following are not approved implementation contracts until a later spec marks them approved:

- exact per-primitive source files beyond the architecture tree approved in `docs/specs/architecture.md`;
- exact method signatures beyond the common vocabulary approved in `docs/specs/project/scope.md`;
- exact managed/unmanaged container naming beyond the approved `Static` and `Bounded` capacity categories;
- exact barrier, DMA, IO, and architecture fence semantics;
- exact allocator and collection algorithms;
- exact testing harness APIs;
- implementation eligibility for planned primitives beyond the first-slice candidates named in `docs/specs/project/scope.md`.

## Rule for API sketches

Code blocks in planning documents are illustrative unless the section is explicitly labeled **Approved API**.

Illustrative code may be used to discuss shape and usage, but implementation must not treat it as a stable ABI or source contract.

## Draft content placement rule

API, architecture, type, and usage proposals live in the spec for the subsystem that owns them.

Central overview documents may link to subsystem specs, but must not become the source of truth for API or type contracts.

## Rule for unresolved details

If a detail is needed for implementation but appears only as an open question, implementation must stop at the boundary and either:

1. update the spec with an approved decision; or
2. isolate a temporary experiment behind a clearly named unstable interface.

Temporary experimental interfaces must not be presented as final public API.
