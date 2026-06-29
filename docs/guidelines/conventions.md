# Conventions

Implementation conventions for zstdx source and specs. Terse rules; deviations need a reason in review.

These conventions extend `docs/guidelines/zig.md`.

## Authority order

When rules conflict, follow this order:

1. approved specs under `docs/specs/`;
2. this conventions document;
3. baseline `docs/guidelines/zig.md`;
4. planning notes under `docs/planning/`, which are never authoritative for landed code.

## Spec ownership

Every public module is owned by one spec under `docs/specs/`.

- Source module headers cite the owning spec path.
- A module without an approved owning spec does not land.
- Planning documents do not define public API contracts.
- Specs define contracts; source implements them.

## Directory ownership

Source directory ownership is defined by `docs/specs/architecture.md`.

- `src/core/` — options, traits, debug policy, and shared range primitives.
- `src/bits/` — power-of-two helpers, flags, fields, bitsets, bitmaps.
- `src/addr/` — strong address, size, page, frame, and range types.
- `src/barrier/` — generic compiler, CPU, IO, and DMA ordering surfaces.
- `src/arch/` — architecture-specific CPU and fence helpers.
- `src/layout/` — endian, unaligned, packed-view, and layout assertion helpers.
- `src/bytes/` — byte cursors, builders, endian readers/writers.
- `src/mem/` — memory alignment, allocators, and memory-resource primitives.
- `src/collections/` — non-intrusive containers.
- `src/intrusive/` — intrusive containers.
- `src/sync/` — synchronization primitives.
- `src/concurrent/` — concurrent queues, rings, deques, and reclamation helpers.
- `src/io/` — volatile and MMIO access wrappers.
- `src/rings/`, `src/tags/`, `src/sg/` — generic descriptor rings, tag pools, and scatter/gather structures.
- `src/diag/` — invariant, trace, panic-safe log, stress, and benchmark helpers.

## File responsibility

Use the baseline ownership rules in `docs/guidelines/zig.md`. zstdx split decisions must follow the owning spec
and the owned mechanic, not file length.

Allowed zstdx split shapes:

- `collections/list.zig` plus `collections/static_list.zig` if the static variant has independent mechanics.
- `barrier.zig`, `barrier/compiler.zig`, `barrier/io_dma.zig` if the contracts differ.
- `arch/x86/fence.zig`, `arch/x86/cpu.zig`.

Disallowed zstdx split shapes:

- `manager.zig` unless the spec owns a type named `Manager`.

## Namespace facades

`src/zstdx.zig` is the public package facade. Domain facade files such as `src/bits.zig` may re-export stable
public surfaces for one domain.

Domain facades follow the baseline thin-facade rule in `docs/guidelines/zig.md`. They may:

- import implementation files;
- re-export approved public types, functions, constants, and submodules;
- provide short aliases to declarations owned by implementation files.

Domain facades must not provide wrapper modules around sibling packages.

Implementation modules import each other directly when the owning specs allow the dependency.

Root exports may promote flagship type families (`List`, `Ring`, `HashMap`, ...) after their owning specs approve
the exact surface. The subsystem namespace remains the canonical home.

## Imports and aliases

Use the baseline import and alias rules in `docs/guidelines/zig.md`.

zstdx sorts aliases by alias name unless a small semantic grouping is clearer.

## Comments

Use the baseline comment and module-header rules in `docs/guidelines/zig.md`.

zstdx source comments may cite approved `docs/specs/...` paths only. They must not cite `docs/planning/...`.

## Public API strictness

zstdx public APIs are explicit and domain-neutral. A public surface lands only under the namespace approved by its
owning spec.

Generic primitives must not encode downstream policy. Domain-specific systems belong in downstream packages.

## Naming discipline

zstdx names encode ownership and capacity.

- `Managed` stores an allocator handle and may allocate only where the method contract says so.
- `Unmanaged` requires the caller to pass an allocator to allocating operations.
- `Static` has comptime fixed capacity and never allocates.
- `Bounded` uses caller-provided storage or runtime fixed capacity and never allocates after initialization.
- `View` borrows and does not own.
- `Owned` owns memory or a resource.
- `Handle` is generation-checked when stale-use detection is part of the contract.
- `clearRetainingCapacity` preserves backing storage.
- `clearAndFree` releases backing storage.
- `approxLen` is permitted only when concurrency makes exact length expensive or impossible.

## API grammar

zstdx public names use the baseline Zig naming rules with these package terms:

- namespaces and modules are lower-case domain names: `bits`, `addr`, `mem`, `layout`, `bytes`, `intrusive`;
- type names and type factories are PascalCase: `List`, `BitSet`, `Address`, `BitFlags`;
- runtime functions and methods are lower camel case: `alignUp`, `append`, `pushBack`, `clearRetainingCapacity`;
- acronyms are words unless the owning spec approves an ABI name: `PhysAddr`, `VirtAddr`, `DmaAddr`,
  `MmioRegister`;
- `Static`, `Bounded`, `Managed`, and `Unmanaged` are nested under the family they specialize: `List.Static`, not
  `StaticList`;
- slice exposure uses `asSlice` / `asConstSlice` unless a spec deliberately exposes fields;
- list-like containers append;
- stack-like containers push/pop;
- queue, ring, and deque containers use directional names such as `pushBack` and `popFront`.

## Constructors

zstdx constructor vocabulary:

- `Type.init(...)` initializes without allocation unless the spec says otherwise.
- `Type.initCapacity(...)` may allocate or reserve capacity if the spec says so.
- `Type.from(input)` performs pure reinterpretation or conversion from one input.
- `Type.wrap(storage)` borrows caller-owned storage.
- `deinit` releases resources owned by the value.

## Runtime contracts

zstdx specs use the baseline public-contract checklist in `docs/guidelines/zig.md`.

Primitive specs must state the primitive-specific allocation, waiting, capacity, execution-bound, invalidation, and
ordering rules in their behavior contract tables.

## Barrier and architecture boundaries

zstdx owns generic barriers only when a spec names the compiler, CPU, IO, or DMA contract.

Architecture-specific instructions live under `src/arch/<arch>/` and must document feature requirements.

## Domain neutrality

`zstdx` does not implement domain systems. Generic mechanisms are allowed; policy protocols are not.

Allowed examples:

- typed MMIO register wrapper;
- descriptor ring;
- tag allocator;
- scatter/gather list;
- strong DMA address type.

Disallowed examples:

- PCI enumeration;
- NVMe queue setup;
- ACPI parser;
- UEFI protocol invocation;
- filesystem implementation;
- IOMMU backend;
- hypervisor VMCS/VMCB handling.

## Implementation order per module

Each module lands in this order:

1. owning spec exists and is approved;
2. public type skeletons and compile-time assertions;
3. unit tests for contracts and edge cases;
4. implementation;
5. model, stress, or integration tests where the spec requires them.

A module without its owning spec does not land.
