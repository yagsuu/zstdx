# zstdx

`zstdx` is a library of freestanding-first, domain-neutral primitives for systems code.

## Included primitives

- **Types and layout:** addresses, pages, frames, ranges, durations, bit
  operations, alignment, endian values, and byte access.
- **Storage and collections:** `Static` inline storage, `Bounded`
  caller-provided storage, allocator-backed arenas, slab allocators and caches,
  and intrusive containers.
- **Synchronization and concurrency:** atomic cells, spin locks, one-time
  initialization, latches, rendezvous, signals, and SPSC/MPSC rings.
- **Hardware-facing primitives:** barriers, MMIO, x86_64 instruction and
  register wrappers, DMA buffers, and scatter/gather lists.
- **Time:** monotonic clocks, deadlines, backoff, rate counters, deadline
  queues, and timer wheels.

## Requirements and platform support

| Item | Support |
| --- | --- |
| Zig | `0.16.0` or later |
| Package | `zstdx` |
| Public module | `stdx` |
| Dependencies | None |
| Runtime | No OS services, heap, or threading runtime unless a primitive contract requires one. |
| Architecture | Generic APIs are target-neutral. `stdx.arch` APIs are target-gated. |

## Quick start

Add `zstdx` to the consuming project's build configuration and import the
package module as `stdx`:

```zig
const zstdx = b.dependency("zstdx", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("stdx", zstdx.module("stdx"));
```

```zig
const stdx = @import("stdx");
```

## Common workflows

### Caller-provided fixed storage

`Static` owns inline storage. `Bounded` borrows caller-provided storage. Neither
variant allocates.

```zig
const stdx = @import("stdx");

var storage: [64]u32 = undefined;
var ready = stdx.Ring.Bounded(u32).wrap(&storage);
try ready.pushBack(42);
```

### Strong address types

Address aliases remain under `stdx.addr`; callers do not use raw integers after
conversion.

```zig
const stdx = @import("stdx");

const base = stdx.addr.PhysAddr.fromInt(0x1000);
const aligned = try base.alignUp(4096);
_ = aligned;
```

### Synchronize without scheduler policy

`RawSpinLock` provides mutual exclusion by spinning. It does not yield, sleep,
or allocate.

```zig
const stdx = @import("stdx");

var lock = stdx.sync.RawSpinLock.init();
lock.acquire();
defer lock.release();
```

## Public API

`src/stdx.zig` is the public facade. It re-exports these namespaces:

| Namespace | Purpose |
| --- | --- |
| `stdx.core` | Debug checks, options, traits, and shared range primitives |
| `stdx.bits`, `stdx.layout`, `stdx.bytes` | Bit operations, layout helpers, and byte access |
| `stdx.addr`, `stdx.ranges`, `stdx.graph` | Strong address types, range structures, and forests |
| `stdx.mem`, `stdx.collections`, `stdx.intrusive`, `stdx.algo` | Memory mechanisms, collections, intrusive structures, and algorithms |
| `stdx.sync`, `stdx.concurrent`, `stdx.barrier` | Synchronization, concurrent structures, and ordering primitives |
| `stdx.arch`, `stdx.io`, `stdx.dma`, `stdx.cpu` | Target wrappers, MMIO, DMA data structures, and per-CPU substrate |
| `stdx.time`, `stdx.tags`, `stdx.func`, `stdx.diag` | Time, tag allocation, callbacks, and diagnostics |

## Design

- **Caller-owned policy.** Platform discovery, scheduling, DMA mapping, and
  device protocol policy remain with the caller or a downstream package.
- **Explicit storage and allocation.** `Static` owns inline storage; `Bounded`
  borrows fixed storage; allocator-backed types state their allocator use.
- **Explicit effects.** Public contracts state applicable allocation, waiting,
  capacity, ownership, invalidation, errors, concurrency, and ordering effects.
- **Domain-neutral APIs.** The library provides mechanisms, not a kernel,
  firmware, driver, hypervisor, or protocol stack.
- **Target isolation.** Architecture-specific instructions remain under
  `stdx.arch` and do not leak into generic primitives.

## Build and test

Run the default suite:

```sh
zig build test
```

Check Zig source format:

```sh
zig fmt --check build.zig src test
```

The default suite runs host tests and compile fixtures for supported targets and
selected rejected API uses. It requires no external tools.

## Documentation

[Normative contracts](docs/specs/) define public behavior. Planning documents do
not define the public API.

- [`docs/specs/project/scope.md`](docs/specs/project/scope.md) — package scope,
  naming, and storage terminology
- [`docs/specs/project/architecture.md`](docs/specs/project/architecture.md) —
  facade, source ownership, layering, and test aggregation
- [`docs/specs/stdx.md`](docs/specs/stdx.md) — exact public facade exports
- [`docs/guidelines/testing.md`](docs/guidelines/testing.md) — test requirements
- [`docs/guidelines/spec-writing.md`](docs/guidelines/spec-writing.md) —
  specification requirements
