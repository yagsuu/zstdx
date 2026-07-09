# zstdx

`zstdx` is a domain-neutral Zig primitive library for low-level systems code.
It provides freestanding-first primitives with explicit contracts for storage,
external allocation, waiting, capacity, ownership, invalidation, errors,
concurrency, and ordering.

| Field | Value |
| --- | --- |
| Package | `zstdx` |
| Import name | `stdx` |
| Public facade | `src/stdx.zig` |
| Minimum Zig | `0.16.0` |
| Normative specs | `docs/specs/` |

## Status

`zstdx` is early-stage and spec-driven. Public modules land only after their
owning specs are approved. README examples and summaries are non-normative;
owning specs define API contracts.

## Build

```sh
zig build test --summary all
```

The host-side test suite is aggregated by `test/all.zig`.

## Import

```zig
const stdx = @import("stdx");
```

Common root-promoted families:

```zig
const List = stdx.List;
const Ring = stdx.Ring;
```

Domain-specific and policy-heavy APIs stay namespaced:

```zig
const mem = stdx.mem;
const addr = stdx.addr;
const x86 = stdx.arch.x86_64;
```

## Scope

`zstdx` owns reusable primitives whose behavior can be specified without
application, protocol, platform, or device policy.

In scope:

- freestanding-first low-level mechanisms;
- static, bounded, intrusive, and caller-owned storage patterns;
- explicit allocation, waiting, capacity, ownership, invalidation, and ordering
  contracts;
- strong address, page, tag, time, and descriptor-facing value types;
- generic synchronization and concurrent structures with explicit platform
  requirements;
- target-gated architecture, barrier, MMIO, and DMA primitives.

Out of scope:

- kernels, firmware frameworks, driver stacks, filesystems, and hypervisor
  control planes;
- PCI enumeration, ACPI/AML, UEFI protocol wrappers, NVMe controllers, IOMMU
  policy, block layers, scheduler policy, and VM-exit dispatch;
- replacements for `std` primitives when `std` already owns the exact contract.

See [`docs/specs/project/scope.md`](docs/specs/project/scope.md).

## Design principles

### Freestanding first

Primitives compile and work without an OS, heap, threading runtime, or `std.Io`
implementation.

### No hidden allocation or waiting

If an operation allocates, sleeps, spins, blocks, performs volatile access,
emits a barrier, or executes a target instruction, the public contract says so.

### Caller-owned storage

Fixed-capacity storage is explicit: inline for `Static`, caller-provided for
`Bounded`, and embedded in parent objects for intrusive structures.

### Compile-time composition

Backends such as clocks, wait/wake mechanisms, and MMIO surfaces compose through
generic type parameters instead of hot-path vtables.

### Contracts are API surface

Allocation, waiting, concurrency, ordering, invalidation, errors, and
mutation-on-error are part of each primitive contract.

### Domain identity through types

Physical, virtual, DMA, page, tag, and time domains use strong types instead of
bare integers where accidental mixing would be a bug.

## Examples

### Fixed-capacity FIFO

```zig
const stdx = @import("stdx");

var ready = stdx.Ring.Static(u32, 64).init();
try ready.pushBack(42);

const next = ready.popFront();
```

### Caller-owned memory

```zig
const stdx = @import("stdx");

var backing: [4096]u8 = undefined;
var arena = stdx.mem.Arena.Bounded.wrap(&backing);

const bytes = try arena.allocSlice(u8, 128);
```

### Strong page/frame algebra

```zig
const stdx = @import("stdx");

const Page4K = stdx.addr.Page(stdx.addr.PhysAddr, stdx.addr.pages._4kib);
const frame = try Page4K.Frame.fromAddressInt(0x1000);
```

### Target-gated primitive

```zig
const stdx = @import("stdx");

const x86 = stdx.arch.x86_64;
if (x86.supported) {
    x86.cpu.pause();
}
```

## Public surface

| Namespace | Purpose | Key families |
| --- | --- | --- |
| `stdx.core` | Shared contracts and callback traits | `SafetyMode`, `Range(T)` |
| `stdx.bits` | Bit and word helpers | `BitSet`, `word` |
| `stdx.addr` | Strong address and page algebra | `Address`, `PhysAddr`, `VirtAddr`, `DmaAddr`, `Page` |
| `stdx.layout` | Endian field types | `EndianInt`, `Le`, `Be` |
| `stdx.bytes` | Byte-slice access | unaligned access, checked offset access, `Cursor` |
| `stdx.mem` | Fixed-storage memory primitives | `Arena`, `Pool`, `PoolCache`, bitmap/buddy/frame allocators, cache padding |
| `stdx.collections` | Non-intrusive fixed-capacity containers | `List`, `Ring` |
| `stdx.intrusive` | Embedded-node collections | `List`, `Queue`, `Stack` |
| `stdx.ranges` | Interval sets and maps | `RangeSet`, `RangeMap` |
| `stdx.graph` | Topology primitives | `Forest` |
| `stdx.algo` | Stateless algorithms | allocation placement, buddy arithmetic |
| `stdx.tags` | Strong identifiers | `Tag`, `TagAllocator` |
| `stdx.arch` | Target-gated architecture primitives | `x86_64` |
| `stdx.diag` | Primitive diagnostics | `Diagnostics`, `PanicLog` |
| `stdx.sync` | Synchronization primitives | `Signal`, `AtomicCell`, `RawSpinLock`, `Once`, `Rendezvous` |
| `stdx.concurrent` | Concurrent rings | `mpsc.Ring`, `spsc.Ring` |
| `stdx.cpu` | CPU-local storage | `PerCpu` |
| `stdx.time` | Time values and helpers | `Instant`, `Duration`, `Clock`, `Deadline`, `Backoff`, `RateCounter` |
| `stdx.barrier` | Compiler, MMIO, and DMA fences | `compiler`, `mmio`, `dma` |
| `stdx.io` | MMIO and polling helpers | `Mmio`, `poll` |
| `stdx.dma` | DMA-visible value types | `Buffer`, `ScatterGather` |
| `stdx.func` | Function wrappers | `Callback`, `Closure` |

Root-promoted families:

| Root export | Canonical home |
| --- | --- |
| `stdx.List` | `stdx.collections.List` |
| `stdx.Ring` | `stdx.collections.Ring` |

Root promotion rules live in
[`docs/specs/root-exports.md`](docs/specs/root-exports.md).

## Contract vocabulary

Primitive specs use these fields:

| Field | Meaning |
| --- | --- |
| Storage | Where primitive state or backing storage lives. |
| External allocation | Whether operations call an allocator, heap, syscall, runtime API, or backing-resource provider. |
| Waiting | Whether operations block, sleep, spin, wait on I/O, or synchronize. |
| Concurrency | Access contract and synchronization requirements. |
| Performance | Hot-path and maintenance-path complexity. |
| Errors | Public error set, `null` behavior, and programmer-error preconditions. |
| Mutation on error | Whether fallible operations leave logical state unchanged. |
| Invalidation | Which pointers, slices, indexes, handles, ranges, or memberships become invalid. |
| Ordering | FIFO, LIFO, sorted, insertion order, target-instruction order, or none. |
| Why not std.*? | Closest `std` or Zig feature and the axis where `zstdx` differs. |

See the behavior documentation policy in
[`docs/specs/project/scope.md`](docs/specs/project/scope.md).

## Documentation

| Document | Purpose |
| --- | --- |
| [`docs/specs/project/scope.md`](docs/specs/project/scope.md) | Project scope, naming policy, behavior-documentation rules. |
| [`docs/specs/root-exports.md`](docs/specs/root-exports.md) | Root facade and root promotion rules. |
| [`docs/specs/`](docs/specs/) | Normative per-primitive specs. |
| [`docs/project-decisions.md`](docs/project-decisions.md) | Approved project facts and status labels. |

A public module lands only with an approved owning spec.
