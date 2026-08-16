# zstdx

`zstdx` is a Zig-native library of domain-neutral, low-level primitives with
explicit contracts for storage, allocation, ownership, waiting, invalidation,
and ordering.

## Overview

`zstdx` owns reusable primitives for core contracts, bit operations, addresses
and ranges, layout and byte access, explicit-allocation memory mechanisms,
fixed-storage and intrusive collections, synchronization, concurrent data
structures, barriers, architecture wrappers, MMIO, DMA data structures, time,
and diagnostics.

The public Zig module is `stdx`. The library does not provide a kernel, driver
framework, hardware discovery, scheduler policy, platform memory-map ownership,
DMA mapping policy, protocol implementations, or device drivers.

## Features

- Strong address, page, frame, range, and duration types.
- Checked bit, layout, alignment, and endian byte-access primitives.
- `Static` inline-storage and `Bounded` caller-storage collection variants.
- Explicit allocator-backed arenas, slab allocators, and slab caches.
- Intrusive lists, queues, and stacks with caller-owned nodes.
- Atomic cells, spin locks, one-time initialization, latches, rendezvous, and
  signals.
- SPSC and MPSC rings with explicit concurrency contracts.
- Generic barriers, MMIO wrappers, x86_64 instruction and register wrappers,
  DMA buffers, and scatter/gather lists.
- Monotonic clocks, deadlines, backoff, rate counters, deadline queues, and
  timer wheels.

## Requirements and platform support

| Item | Support |
| --- | --- |
| Zig | `0.16.0` or later |
| Package | `zstdx` |
| Public module | `stdx` |
| Dependencies | None |
| Runtime model | Freestanding-compatible; primitives do not require OS services, a heap, or a threading runtime unless their contracts state otherwise |
| Architecture support | Generic primitives are target-neutral; architecture-specific APIs are exposed under `stdx.arch` and target-gated by their contracts |
| Default test suite | Host tests plus compile fixtures; no external tools required |

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

Use an inline, fixed-capacity FIFO:

```zig
const std = @import("std");
const stdx = @import("stdx");

pub fn main() !void {
    var ready = stdx.Ring.Static(u32, 64).init();
    try ready.pushBack(42);

    const next = ready.popFront() orelse unreachable;
    std.debug.print("next: {d}\n", .{next});
}
```

## Common workflows

### Use caller-provided fixed storage

`Static` owns inline storage. `Bounded` borrows caller-provided storage. Neither
variant allocates.

```zig
const stdx = @import("stdx");

var storage: [64]u32 = undefined;
var ready = stdx.Ring.Bounded(u32).wrap(&storage);
try ready.pushBack(42);
```

### Use strong address types

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

`stdx.List` and `stdx.Ring` are root-promoted collection families. All other
public declarations remain under their owning namespaces.

## Design

- **No hidden policy.** Platform discovery, scheduling, DMA mapping, and device
  protocol policy remain with the caller or a downstream package.
- **Explicit storage and allocation.** `Static` owns inline storage; `Bounded`
  borrows fixed storage; allocator-backed types state their allocator use.
- **Explicit effects.** Public contracts define applicable allocation, waiting,
  capacity, ownership, invalidation, errors, concurrency, and ordering effects.
- **Domain-neutral APIs.** The library provides mechanisms, not a kernel,
  firmware, driver, hypervisor, or protocol stack.
- **Contract-driven implementation.** Each public module has an approved owning
  specification; planning documents do not define production behavior.
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

The default suite runs the host tests and compile fixtures. The fixtures verify
supported and rejected target-specific API uses. The suite requires no external
tools.

## Documentation

Normative contracts are under [`docs/specs/`](docs/specs/). Planning documents
do not define the public API.

- [`docs/specs/project/scope.md`](docs/specs/project/scope.md) — package scope,
  naming, and storage terminology
- [`docs/specs/project/architecture.md`](docs/specs/project/architecture.md) —
  facade, source ownership, layering, and test aggregation
- [`docs/specs/stdx.md`](docs/specs/stdx.md) — exact public facade exports
- [`docs/guidelines/testing.md`](docs/guidelines/testing.md) — test requirements
- [`docs/guidelines/spec-writing.md`](docs/guidelines/spec-writing.md) —
  specification requirements
