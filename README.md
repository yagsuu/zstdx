# zstdx

Low-level Zig primitives for fixed storage, caller-owned memory, strong address
and page types, synchronization, and target-specific operations.

| Field | Value |
| --- | --- |
| Package | `zstdx` |
| Import name | `stdx` |
| Minimum Zig | `0.16.0` |

## Add to a project

These examples use a `zstdx` checkout beside the consuming project.

1. Add the dependency to the consuming project's `build.zig.zon`:

   ```zig
   .dependencies = .{
       .zstdx = .{ .path = "../zstdx" },
   },
   ```

2. Add `stdx` to the module that imports it. For an executable named `exe`:

   ```zig
   const zstdx = b.dependency("zstdx", .{
       .target = target,
       .optimize = optimize,
   });
   exe.root_module.addImport("stdx", zstdx.module("stdx"));
   ```

## Quickstart

With the build setup above, `src/main.zig` can use a fixed-capacity FIFO:

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

## Choose a primitive

| Need | Entry point |
| --- | --- |
| Inline or caller-provided fixed-capacity FIFO storage | `stdx.Ring.Static`, `stdx.Ring.Bounded` |
| Caller-owned bump allocation | `stdx.mem.Arena.Bounded` |
| Strong address, page, and frame types | `stdx.addr` |
| Synchronization and concurrent structures | `stdx.sync`, `stdx.concurrent` |
| Architecture-specific operations, MMIO, DMA, and barriers | `stdx.arch`, `stdx.io`, `stdx.dma`, `stdx.barrier` |

`Static` owns inline compile-time fixed storage. `Bounded` uses fixed storage
provided by the caller. Neither allocates.

## API categories

| Category | Entry points |
| --- | --- |
| Foundations | `stdx.core`, `stdx.bits`, `stdx.ranges`, `stdx.graph`, `stdx.layout`, `stdx.bytes`, `stdx.func` |
| Memory and data structures | `stdx.mem`, `stdx.collections`, `stdx.intrusive`, `stdx.algo`, `stdx.tags`, `stdx.List`, `stdx.Ring` |
| Synchronization and time | `stdx.sync`, `stdx.concurrent`, `stdx.barrier`, `stdx.time` |
| Hardware and I/O | `stdx.addr`, `stdx.arch`, `stdx.io`, `stdx.dma`, `stdx.cpu` |
| Diagnostics | `stdx.diag` |

## Guarantees

- **Freestanding support.** Primitives compile and work without an OS, heap,
  threading runtime, or `std.Io` implementation.
- **Explicit effects.** Public contracts state allocation, sleeping, spinning,
  blocking, volatile access, barriers, and target instructions.
- **Strong types.** Types distinguish address, page, tag, and time domains.

## Scope

Use `zstdx` for reusable low-level mechanisms. It does not provide domain
policy or systems such as kernels, firmware frameworks, drivers, filesystems,
or protocol implementations.

See [`docs/specs/project/scope.md`](docs/specs/project/scope.md) for the
complete scope, non-goals, and naming policy.

## Test this checkout

Run this command from the repository root:

```sh
zig build test --summary all
```

It runs the aggregated test suite and target-compile fixtures.

## Reference

| Resource | Purpose |
| --- | --- |
| [`src/stdx.zig`](src/stdx.zig) | Complete public facade. |
| [`docs/specs/`](docs/specs/) | Per-primitive contracts. |
| [`docs/specs/project/scope.md`](docs/specs/project/scope.md) | Scope, naming, and storage terminology. |
