# zstdx

`zstdx` is a freestanding-first, domain-neutral Zig library of low-level
primitives. Its public contracts explicitly state allocation, waiting, capacity,
ownership, invalidation, concurrency, and ordering behavior.

| Field | Value |
| --- | --- |
| Package | `zstdx` |
| Import name | `stdx` |
| Minimum Zig | `0.16.0` |

## Import

The package build defines the `stdx` module from
[`src/stdx.zig`](src/stdx.zig).

```zig
const stdx = @import("stdx");
```

## Use

`zstdx` makes storage and execution behavior explicit in each primitive
contract.

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

### Strong page and frame types

```zig
const stdx = @import("stdx");

const Page4K = stdx.addr.Page(stdx.addr.PhysAddr, stdx.addr.pages._4kib);
const frame = try Page4K.Frame.fromAddressInt(0x1000);
```

## Guarantees

- **Freestanding first.** Primitives compile and work without an OS, heap,
  threading runtime, or `std.Io` implementation.
- **No implicit effects.** Public contracts state allocation, sleeping,
  spinning, blocking, volatile access, barriers, and target instructions.
- **Explicit storage.** `Static` uses inline compile-time fixed capacity;
  `Bounded` uses caller-provided fixed storage; intrusive structures embed
  their nodes in parent objects.
- **Domain-safe composition.** Strong types distinguish address, page, tag,
  and time domains. Generic parameters compose clocks, wait/wake mechanisms,
  and MMIO surfaces without hot-path vtables.

## Scope

| Use `zstdx` for | Do not use `zstdx` for |
| --- | --- |
| Generic, reusable low-level mechanisms: fixed-capacity and intrusive storage, strong address and page types, synchronization, concurrent structures, barriers, MMIO, and DMA primitives. | Domain policy and systems: kernels, firmware frameworks, drivers, filesystems, hardware enumeration, storage stacks, hypervisor control planes, and protocol implementations. |

[`docs/specs/project/scope.md`](docs/specs/project/scope.md) defines the
authoritative scope, non-goals, naming policy, and storage terminology.

## Validate

```sh
zig build test --summary all
```

This command runs the aggregated test suite and target-compile fixtures.

## API and documentation

| Resource | Purpose |
| --- | --- |
| Root exports: `stdx.List`, `stdx.Ring` | Common fixed-capacity collection families. |
| `stdx.addr`, `stdx.mem`, `stdx.collections`, `stdx.intrusive` | Address/page types and storage primitives. |
| `stdx.sync`, `stdx.concurrent`, `stdx.arch`, `stdx.time` | Synchronization, target-gated primitives, and time-based primitives. |
| [`src/stdx.zig`](src/stdx.zig) | Complete public facade. |
| [`docs/specs/`](docs/specs/) | Normative per-primitive specifications. |
| [`docs/specs/project/scope.md`](docs/specs/project/scope.md) | Scope, naming, behavior-documentation rules. |
| [`docs/guidelines/spec-writing.md`](docs/guidelines/spec-writing.md) | Specification structure and normative-language rules. |
