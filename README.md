# zstdx

## Overview

`zstdx` provides domain-neutral primitives for freestanding systems code.

## Features

- **Types and layout:** addresses, pages, frames, ranges, durations, bit
  operations, alignment, endian values, and byte access.
- **Storage and collections:** inline `Static` storage, caller-provided
  `Bounded` storage, allocator-backed arenas, slab allocators, caches, and
  intrusive containers.
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
| Runtime | No OS services, heap, or threading runtime required. |
| Architecture | Generic APIs are target-neutral. `stdx.arch` APIs are target-gated. |

## Quick start

Add `zstdx` to your build configuration, then import its module as `stdx`:

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

### Caller-provided FIFO storage

`stdx.collections.Ring.Bounded` is a FIFO around caller provided storage.
Concurrent SPSC and MPSC queues are under `stdx.concurrent`.

```zig
const stdx = @import("stdx");

var storage: [64]u32 = undefined;
var queue = stdx.collections.Ring.Bounded(u32).wrap(&storage);
try queue.pushBack(42);
```

### Strong address types

```zig
const stdx = @import("stdx");

const base = stdx.addr.PhysAddr.fromInt(0x1000);
const aligned = try base.alignUp(4096);
_ = aligned;
```

### Spin locks

`RawSpinLock` provides mutual exclusion by spinning. It does not yield, sleep,
or allocate.

```zig
const stdx = @import("stdx");

var lock = stdx.sync.RawSpinLock.init();
lock.acquire();
defer lock.release();
```

## Public API

The public facade is `src/stdx.zig`. It re-exports these namespaces:

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

- **Caller-owned policy.** The caller or a downstream package owns platform
  discovery, scheduling, DMA mapping, and device-protocol policy.
- **Explicit storage and allocation.** `Static` owns inline storage; `Bounded`
  borrows fixed storage; allocator-backed types identify their allocator use.
- **Explicit effects.** Public contracts state applicable allocation, waiting,
  capacity, ownership, invalidation, error, concurrency, and ordering effects.
- **Domain-neutral APIs.** The library provides mechanisms rather than a
  kernel, firmware, driver, hypervisor, or protocol stack.

## Build and test

Run the default suite:

```sh
zig build test
```

Check Zig source format:

```sh
zig fmt --check build.zig src test
```

The default suite runs host tests, supported-target compile fixtures, and
fixtures that reject selected invalid API uses. It requires no external tools.

## Documentation

See [`docs/specs/`](docs/specs/) for public API contracts and
[`docs/guidelines/`](docs/guidelines/) for project conventions.
