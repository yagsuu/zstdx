# Project scope

Status: Approved.

`zstdx` is a domain-neutral Zig primitive library. It provides reusable
low-level mechanisms with explicit allocation, waiting, capacity, ownership,
invalidation, and ordering contracts.

## Purpose and boundary

This specification defines package identity, project scope, public naming
policy, and minimum primitive-contract content. System policy and protocol
implementations remain with downstream packages; per-primitive specifications
define exact APIs, algorithms, and implementation eligibility.

## Public namespace and source ownership

- The package name is `zstdx`.
- The public import name is `stdx`. Public examples use `const stdx = @import("stdx");`.
- `src/stdx.zig` is the public package facade.
- Subsystem namespaces are canonical. Exact root exports are owned by `docs/specs/stdx.md`.

```zig
const stdx = @import("stdx");

const bits = stdx.bits;
const addr = stdx.addr;
const mem = stdx.mem;
const layout = stdx.layout;
const bytes = stdx.bytes;
const intrusive = stdx.intrusive;
```

## Global invariants

- A public primitive MUST be in scope only when its behavior can be specified without domain policy.
- A public module MUST NOT land without an approved owning specification.
- Implementation MUST follow approved specifications, not planning documents.
- If implementation requires an unresolved decision, implementation work MUST stop until the owning specification is updated.
- A public primitive specification MUST define allocation, waiting, capacity, ownership, invalidation, ordering, error, and debug-assertion behavior when each property applies.

## Naming policy

Public API names MUST follow these rules:

- Namespaces and modules use lower case: `bits`, `addr`, `mem`, `layout`, `bytes`, and `intrusive`.
- Type names and type factories use PascalCase: `List`, `BitSet`, `Address`, and `BitFlags`.
- Runtime functions and methods use lower camel case: `alignUp`, `append`, `pushBack`, and `clearRetainingCapacity`.
- Acronyms are words unless an owning specification approves an ABI name: `PhysAddr`, `VirtAddr`, `DMAAddr`, and `MMIO`.
- Free functions are limited to stateless algorithms and type factories.
- Constructors and operations belong to the type they affect.
- Capacity and ownership variants nest under their family: `List.Static`, not `StaticList`.

| Name | Contract |
| --- | --- |
| `Static` | comptime fixed capacity; never allocates |
| `Bounded` | caller-provided or runtime fixed storage; never grows by allocation |
| `Managed` | stores an allocator handle; allocates only where the method contract says so |
| `Unmanaged` | caller passes an allocator to allocating methods |
| `View` | borrowed non-owning access |
| `Owned` | owns memory or a resource |
| `Handle` | externally storable reference; generation-checked when specified |

`Small` is not an approved general category. Inline storage with optional spill requires a dedicated specification before a public `Small` container may land.

## Common method vocabulary

Collection specifications SHOULD use this vocabulary unless the owning specification approves a narrower or more precise surface:

```zig
len()
capacity()
isEmpty()
isFull()
clearRetainingCapacity()
clearAndFree()
assertValid()
```

List-like containers MUST use `append(item)`, `appendSlice(items)`, `insert(index, item)`, `pop()`, `orderedRemove(index)`, `swapRemove(index)`, `asSlice()`, and `asConstSlice()` for operations with the corresponding behavior.

Stack-like containers MUST use `push(item)`, `pop()`, and `peek()` for operations with the corresponding behavior.

Queue, ring, and deque containers MUST use directional names: `pushFront(item)`, `pushBack(item)`, `popFront()`, `popBack()`, `front()`, and `back()`. A queue or ring MAY expose only the subset matching its semantics.

## Scope boundaries

`zstdx` owns generic primitives for core runtime contracts, bits, addresses and ranges, layout and bytes, explicit-allocation memory mechanisms, static, bounded, dynamic, and intrusive collections, synchronization, concurrent structures, architecture-neutral CPU substrate, generic IO/MMIO mechanisms, descriptor rings, tags, DMA data structures, time and polling, algorithms, and primitive-level diagnostics.

The library does not own PCI enumeration, PCI config-space backends, PCI capability walkers, MSI/MSI-X configuration, NVMe queues or PRP/SGL builders, ACPI or AML processing, UEFI services, SMBIOS processing, block-device abstractions, partition tables, filesystems, USB, virtio, NIC, or GPU drivers, IOMMU implementations, DMA mapping policy, VMCS/VMCB handling, VM-exit dispatch, scheduler policy, or OS physical-memory-map ownership. Downstream packages MAY use `zstdx` primitives for those systems.

The following boundaries apply to all primitive specifications:

- `stdx.addr.DMAAddr` is the device-visible descriptor address. Physical-address identity mapping, IOMMU IOVA allocation, and bounce buffering are caller policy.
- DMA types pair caller-owned host memory with the caller-supplied device-visible address. They MUST NOT allocate host memory, map IOMMU pages, manage bounce buffers, perform cache maintenance, emit barriers, or emit protocol descriptors.
- `stdx.cpu` owns arch-neutral per-CPU substrate. It MUST NOT perform CPU discovery, read the current CPU, or enforce affinity. Every CPU-index argument is caller-supplied.
- `stdx.arch.<arch>` owns per-architecture ISA wrappers. `stdx.arch.x86` is not an approved namespace.
- Generic barrier, IO/MMIO, and architecture primitives require dedicated owning specifications before they land.
- Generic `io.MmioRegister.modify` is not approved without an owning IO specification because read-modify-write is unsafe for many device registers.
- Kernel wait queues, interrupt save/restore policy, scheduler blocking, thread parking, preemption control, and priority inheritance require explicit backend specifications or downstream packages.
- Concurrent reclamation mechanisms require dedicated reclamation specifications.
- Time sources are caller- or backend-supplied unless a dedicated platform specification states otherwise.
- Diagnostics MUST preserve no-hidden-allocation rules.

## Implementation constraints

Sequential byte access MUST use `std.Io.Reader` or `std.Io.Writer`. Fixed-window value conversion MUST use `std.mem`.

Each intrusive membership MUST use a distinct embedded node.

## Testing

Each primitive specification MUST state the tests that prove its observable contract. Required coverage includes the applicable construction and capacity boundaries, positive behavior, errors and no-mutation-on-error, state transitions, ordering, invalidation and lifetime, concurrency and progress, memory ordering, and representation. The test method MUST match the risk: deterministic unit or model tests prove defined outcomes and transitions; stress tests exercise contention paths but do not replace an ordering proof; layout tests verify normative representation.

## Minimum primitive specification content

Each public primitive specification MUST include:

- owned scope and excluded scope;
- namespace and public type shape;
- public operation semantics;
- ownership and lifetime rules;
- allocation, waiting, capacity, invalidation, concurrency, ordering, error, and debug-assertion behavior when applicable;
- required tests.

Usage examples are optional and illustrative unless explicitly normative.
