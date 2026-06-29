# Project scope

Status: Approved.

`zstdx` is a domain-neutral Zig primitive library. It owns reusable low-level mechanisms with explicit allocation, waiting, capacity, ownership, invalidation, and ordering contracts.

`zstdx` is not a kernel, firmware, driver framework, hardware enumerator, storage stack, filesystem, hypervisor substrate, or protocol implementation.

## Package identity

- The final public import name is `zstdx`.
- Public examples use `const zstdx = @import("zstdx");`.
- The repository may retain an old directory name temporarily, but specs and public API use `zstdx`.

## Owned scope

`zstdx` owns generic primitives useful to kernels, hypervisors, firmware, drivers, runtimes, game engines, compilers, storage systems, and high-performance userspace code.

Owned categories:

- core runtime contracts and shared options;
- bit, power-of-two, flag, field, and bitmap helpers;
- strong address, size, page, frame, and range types;
- endian, unaligned, byte-cursor, and layout helpers;
- memory alignment helpers and explicit-allocation memory primitives;
- static, bounded, dynamic, and intrusive collections;
- generic synchronization and concurrent data structures when their platform requirements are explicit;
- generic compiler/CPU/architecture ordering primitives after dedicated barrier specs are approved;
- generic volatile/MMIO wrappers after dedicated IO specs are approved;
- generic descriptor rings, tag allocators, and scatter/gather lists;
- primitive-level diagnostics, model-test helpers, stress helpers, and benchmarks.

A public primitive is in scope only if its behavior can be specified without domain policy.

## Non-goals

`zstdx` must not implement domain-specific systems.

Explicitly out of scope:

- PCI enumeration;
- PCI config-space access backends;
- PCI capability walkers;
- MSI/MSI-X configuration;
- NVMe admin queues;
- NVMe I/O queues;
- NVMe PRP/SGL builders;
- ACPI table parsers or builders;
- AML parser, interpreter, emitter, or DSL;
- UEFI protocol wrappers;
- UEFI service invocation;
- SMBIOS table parsers or builders;
- block-device abstractions;
- partition tables;
- filesystems;
- USB, virtio, NIC, or GPU drivers;
- IOMMU implementations;
- DMA mapping policy;
- hypervisor VMCS/VMCB handling;
- VM-exit dispatch systems;
- scheduler policy;
- OS physical memory map ownership.

Downstream packages may consume `zstdx` primitives to implement those systems. Examples: `zpci`, `znvme`, `zacpi`, `zfw`, `zvm`, `zfat`, `ziommu`, `zhv`, and `zvirtio`.

## Public namespace policy

The public package facade is `src/zstdx.zig`.

Subsystem namespaces are canonical:

```zig
const zstdx = @import("zstdx");

const bits = zstdx.bits;
const addr = zstdx.addr;
const mem = zstdx.mem;
const layout = zstdx.layout;
const bytes = zstdx.bytes;
const intrusive = zstdx.intrusive;
```

Root exports should promote flagship type families after their owning specs approve the exact surface:

```zig
const List = zstdx.List;
const Ring = zstdx.Ring;
const HashMap = zstdx.HashMap;
```

Root promotion does not replace the canonical subsystem home. Exact root exports are owned by `docs/specs/root-exports.md`.

## Naming policy

Public API names follow these rules:

- namespaces and modules are lower case: `bits`, `addr`, `mem`, `layout`, `bytes`, `intrusive`;
- type names and type factories are PascalCase: `List`, `BitSet`, `Address`, `BitFlags`;
- runtime functions and methods are lower camel case: `alignUp`, `append`, `pushBack`, `clearRetainingCapacity`;
- acronyms are treated as words unless an owning spec approves an ABI name: `PhysAddr`, `VirtAddr`, `DmaAddr`, `MmioRegister`;
- free functions are for stateless algorithms and type factories;
- constructors and operations live on the type they affect;
- capacity/ownership variants nest under their family: `List.Static`, not `StaticList`.

Approved capacity and ownership terms:

| Name | Contract |
| --- | --- |
| `Static` | comptime fixed capacity; never allocates |
| `Bounded` | caller-provided or runtime fixed storage; never grows by allocation |
| `Managed` | stores allocator handle; allocates only where the method contract says so |
| `Unmanaged` | caller passes allocator to allocating methods |
| `View` | borrowed non-owning access |
| `Owned` | owns memory or a resource |
| `Handle` | externally storable reference; generation-checked when specified |

`Small` is not approved as a general category. Inline storage with optional spill requires a dedicated spec before any public `Small` container lands.

## Common method vocabulary

Collection specs should use this method vocabulary unless the owning spec approves a narrower or more precise surface.

Common methods:

```zig
len()
capacity()
isEmpty()
isFull()
clearRetainingCapacity()
clearAndFree()
assertValid()
```

List-like containers:

```zig
append(item)
appendSlice(items)
insert(index, item)
pop()
orderedRemove(index)
swapRemove(index)
asSlice()
asConstSlice()
```

Stack-like containers:

```zig
push(item)
pop()
peek()
```

Queue, ring, and deque containers use directional names:

```zig
pushFront(item)
pushBack(item)
popFront()
popBack()
front()
back()
```

A queue or ring may expose only the subset that matches its semantics, usually `pushBack` and `popFront`.

## Behavior documentation policy

Every non-trivial public primitive spec must document:

- allocation behavior by operation;
- waiting behavior by operation: never, spins, or may sleep;
- capacity model by operation where relevant;
- execution bounds by operation;
- access/concurrency contract where relevant;
- progress guarantee where concurrent;
- pointer, index, handle, and iterator stability;
- deterministic iteration behavior;
- full-capacity behavior;
- invalidation rules;
- memory-ordering contract when atomics, barriers, MMIO, DMA, or concurrent access are involved;
- debug assertion behavior;
- panic-safety and interrupt-safety assumptions when relevant.

No public runtime metadata type is approved by this scope spec. A future machine-readable contract type requires a concrete consumer such as docs generation, test tooling, or downstream compile-time selection.

## Planned primitive categories

This section approves the category map and candidate primitive names. Exact APIs, algorithms, and implementation eligibility are owned by the per-primitive specs.

### Core

Planned primitives:

- `SafetyMode`
- deferred option categories only when concrete consumers exist
- `Order`
- `Compare(Context, T)`
- `LessThan(Context, T)`
- `Eql(Context, T)`
- `Hash(Context, T)`
- `Range(T)`
- `core.debug.checksEnabled`

### Bits

Planned primitives:

- `isPowerOfTwo`
- `nextPowerOfTwo`
- `BitFlags(Enum)`
- `BitField`
- `BitSet.Static(N)`
- `Bitmap`
- `BitmapAllocator`
- `AtomicFlags(T)`

### Addresses, sizes, and pages

Planned primitives:

- `Address(tag, Int)`
- `PhysAddr`
- `VirtAddr`
- `ByteSize`
- `PageSize`
- `PageCount`
- `PageFrame`
- `PageRange`

`PhysAddr` and `VirtAddr` are approved built-in aliases once `docs/specs/addr/address.md` approves the generic address tag model.

`DmaAddr` is not approved by this scope spec. It remains a candidate for the address spec because DMA address semantics may need platform/backend wording.

### Layout and bytes

Planned primitives:

- `layout.EndianInt(T, endian)`
- `layout.Le(T)`
- `layout.Be(T)`
- `layout.assertStructLayout`
- `bytes.loadUnaligned`
- `bytes.storeUnaligned`
- `bytes.load`
- `bytes.store`
- `bytes.loadSlice`
- `bytes.storeSlice`
- `bytes.loadTail`
- `bytes.Cursor`
- `bytes.Builder`
- `bytes.StaticBuilder(N)`
- `bytes.EndianReader`
- `bytes.EndianWriter`

Deferred until a dedicated safety spec:

- `layout.PackedView(T)`
- `bytes.BitReader`
- `bytes.BitWriter`
- `bytes.VarIntReader`
- `bytes.VarIntWriter`

### Memory

Planned primitives:

- `mem.alignUp`
- `mem.alignDown`
- `mem.isAligned`
- `mem.FixedBufferArena`
- `mem.BumpAllocator`
- `mem.PoolAllocator(T)`
- `mem.BitmapAllocator`
- `mem.DeferredFreeList`
- `mem.SlabAllocator(T)`
- `mem.SlabCache(T)`
- `mem.BuddyAllocator`

`mem.FrameAllocator` and `mem.VirtualRegionAllocator` are candidates only as generic mechanisms. OS physical-memory-map policy is out of scope.

### Static and bounded collections

Planned primitives:

- `List.Static(T, N)`
- `List.Bounded(T)`
- `Ring.Static(T, N)`
- `Ring.Bounded(T)`
- `Deque.Static(T, N)`
- `Deque.Bounded(T)`
- `Stack.Static(T, N)`
- `Stack.Bounded(T)`
- `Queue.Static(T, N)`
- `Queue.Bounded(T)`
- `HashMap.Static(K, V, N)`
- `HashSet.Static(K, N)`
- `SlotMap.Static(T, N)`
- `Heap.StaticBinary(T, N)`

### Dynamic collections

Planned primitives:

- `List.Managed(T)`
- `List.Unmanaged(T)`
- `Ring.Managed(T)`
- `Ring.Unmanaged(T)`
- `Deque.Managed(T)`
- `Deque.Unmanaged(T)`
- `HashMap.Managed(K, V)`
- `HashMap.Unmanaged(K, V)`
- `HashSet.Managed(K)`
- `HashSet.Unmanaged(K)`
- `SparseSet`
- `SlotMap`
- `HandleMap`
- `Heap.Binary(T)`
- `Heap.Dary(T, D)`
- `Heap.Indexed(K, V)`

### Intrusive structures

Planned primitives:

- `intrusive.List.SinglyLinked`
- `intrusive.List.DoublyLinked`
- `intrusive.Stack`
- `intrusive.Queue`
- `intrusive.Deque`
- `intrusive.FreeList`
- `intrusive.HashList`
- `intrusive.RbTree`
- `intrusive.Heap`
- `intrusive.IntervalTree`
- `intrusive.LruList`

Each intrusive membership requires a distinct embedded node.

### Ranges and ordered structures

Planned primitives:

- `ranges.RangeSet`
- `ranges.RangeMap`
- `IntervalTree`
- `BTree.Map`
- `BTree.Set`
- `RadixTree`
- `CritBitTree`

### Barriers and architecture

Planned categories:

- compiler barriers;
- CPU fences;
- atomic fence helpers;
- architecture-specific fence wrappers;
- MMIO ordering hooks;
- DMA visibility hooks.

Planned primitive names remain candidates until barrier specs approve them:

- `barrier.compiler`
- `barrier.fence`
- `barrier.loadLoad`
- `barrier.loadStore`
- `barrier.storeStore`
- `barrier.storeLoad`
- `barrier.full`
- `arch.x86.lfence`
- `arch.x86.sfence`
- `arch.x86.mfence`
- `arch.x86.pause`
- `arch.aarch64.dmb`
- `arch.aarch64.dsb`
- `arch.aarch64.isb`
- `arch.riscv.fence`

Barriers and fences are deferred from the first implementation slice. IO and DMA barriers require backend/platform contract specs before implementation.

### Synchronization and concurrency

Planned primitives:

- `sync.AtomicCell(T)`
- `sync.Once`
- `sync.RawSpinLock`
- `sync.SpinLock`
- `sync.TicketLock`
- `sync.SeqLock`
- `concurrent.SpscRing`
- `concurrent.MpscQueue`
- `concurrent.MpmcQueue`
- `concurrent.ChaseLevDeque`

Deferred until reclamation specs:

- `concurrent.EpochReclamation`
- `concurrent.HazardPointers`
- `concurrent.QSBR`
- `concurrent.RcuPtr`

Kernel wait queues, interrupt save/restore policy, scheduler blocking, thread parking, preemption control, and priority inheritance require explicit backend specs or downstream packages.

### IO/MMIO

Planned primitives:

- `io.VolatileCell`
- `io.MmioRegister`
- `io.MmioSlice`
- `io.MmioWindow`
- `io.RegisterField`
- `io.RegisterFlags`
- `io.PollUntil`
- `io.Doorbell`

`io.MmioRegister.modify` is not approved at scope level because generic read-modify-write is unsafe for many device registers. It requires an owning IO spec.

### Rings, tags, and scatter/gather

Planned primitives:

- `rings.DescriptorRing`
- `rings.PhaseRing`
- `rings.SubmissionRing`
- `rings.CompletionRing`
- `tags.TagAllocator`
- `tags.DynamicTagAllocator`
- `tags.CommandTracker`
- `sg.Segment`
- `sg.ScatterGatherList`
- `sg.DynamicScatterGatherList`
- `sg.Builder`

These structures do not perform DMA mapping, IOMMU mapping, cache-maintenance policy, device notification policy, or protocol-specific descriptor construction.

### Time and polling

Planned primitives:

- `time.Instant`
- `time.Duration`
- `time.Deadline`
- `time.Backoff`
- `time.RetryPolicy`

Time sources are caller/backend supplied unless a dedicated platform spec says otherwise.

### Algorithms

Planned primitives:

- `algo.sortUnstable`
- `algo.insertionSort`
- `algo.binarySearch`
- `algo.partition`
- `algo.dedupSorted`
- `algo.UnionFind`

Deferred:

- graph algorithms;
- Dijkstra/A*;
- dominators;
- transitive closure.

### Diagnostics

Planned primitives:

- `diag.InvariantChecker`
- `diag.ModelTest`
- `diag.FuzzHarness`
- `diag.MicroBench`
- `diag.ConcurrencyStressRunner`
- `diag.TraceRingBuffer`
- `diag.PanicSafeRingLog`
- `diag.AllocationStats`

Diagnostics must preserve no-hidden-allocation rules.

## First implementation slice

The first implementation slice is limited to primitives that are domain-neutral, host-testable, low-policy, and small enough to fully specify.

Approved first-slice candidates:

1. `core.SafetyMode`;
2. `core.Range`;
3. `core.debug.checksEnabled`;
4. `bits.isPowerOfTwo`, `bits.nextPowerOfTwo`;
5. `mem.alignUp`, `mem.alignDown`, `mem.isAligned`;
6. `bits.BitFlags`;
7. `bits.BitSet.Static`;
8. `addr.Address`;
9. `addr.PhysAddr` and `addr.VirtAddr`;
10. `layout.Le`, `layout.Be`;
11. `bytes.loadUnaligned`, `bytes.storeUnaligned`;
12. `bytes.Cursor`;
13. `mem.FixedBufferArena`;
14. `mem.BumpAllocator`;
15. `List.Static`;
16. `List.Bounded`;
17. `Ring.Static`;
18. `Ring.Bounded`;
19. `intrusive.List.SinglyLinked`;
20. `intrusive.List.DoublyLinked`;
21. `intrusive.Queue`;
22. `intrusive.Stack`.

Explicitly deferred from the first slice:

- barriers and fences;
- IO/MMIO wrappers;
- DMA barrier hooks;
- dynamic hash maps;
- dynamic rings/deques;
- B-trees;
- range maps;
- slab cache;
- buddy allocator;
- synchronization primitives;
- lock-free structures;
- work stealing;
- benchmarking harnesses.

Deferred does not mean rejected. It means no implementation before an approved owning spec exists.

## Specification gate

A public module must not land without an approved owning spec.

Minimum per-primitive spec contents:

- owned scope;
- deferred scope and non-goals;
- namespace and public type shape;
- public methods or operation semantics;
- ownership and lifetime rules;
- allocation behavior;
- waiting behavior;
- capacity behavior;
- invalidation rules;
- concurrency contract;
- ordering contract when relevant;
- error behavior;
- debug assertion behavior;
- examples;
- required tests;
- open questions, if any.

Implementation must follow approved specs, not planning documents. If implementation needs an unresolved decision, stop and update the owning spec before landing public API.
