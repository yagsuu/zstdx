# Root exports

Status: Approved.

`src/stdx.zig` is the `stdx` public package facade. It exports approved domain namespaces and the approved root-promoted type families.

## What this spec is

This spec defines the exact public declarations in `src/stdx.zig`, root-promotion rules, and the tests that verify the facade surface.

## What this spec is not

This spec does not define implementation files, per-primitive method signatures, domain-facade internals, or source-tree layout beyond `src/stdx.zig`.

## Public namespace and source ownership

- Public import path: `stdx`.
- Package facade: `src/stdx.zig`.
- Required test coverage: `test/all.zig` and the tests for the exported domains.

The facade MUST remain thin. It MAY import, re-export, and alias approved public declarations. It MUST NOT implement domain behavior.

## Global invariants

- A domain namespace export MUST correspond to an existing domain facade file.
- The facade MUST NOT export an empty placeholder namespace.
- Root promotion MUST preserve the owning domain namespace as the canonical declaration home.
- The facade MUST NOT provide compatibility aliases or deprecated names.

## API

`src/stdx.zig` MUST begin with:

```zig
//! Public stdx facade. Spec: docs/specs/stdx.md.
```

The current public surface is:

```zig
pub const core = @import("core.zig");
pub const bits = @import("bits.zig");
pub const addr = @import("addr.zig");
pub const ranges = @import("ranges.zig");
pub const graph = @import("graph.zig");
pub const layout = @import("layout.zig");
pub const bytes = @import("bytes.zig");
pub const mem = @import("mem.zig");
pub const collections = @import("collections.zig");
pub const intrusive = @import("intrusive.zig");
pub const algo = @import("algo.zig");
pub const tags = @import("tags.zig");
pub const arch = @import("arch.zig");
pub const diag = @import("diag.zig");
pub const sync = @import("sync.zig");
pub const concurrent = @import("concurrent.zig");
pub const io = @import("io.zig");
pub const barrier = @import("barrier.zig");
pub const time = @import("time.zig");
pub const dma = @import("dma.zig");
pub const cpu = @import("cpu.zig");
pub const func = @import("func.zig");

pub const List = collections.List;
pub const Ring = collections.Ring;
```

`List` and `Ring` are root-promoted collection families. The `sync`, `concurrent`, `diag`, `graph`, `io`, `barrier`, `time`, `dma`, `cpu`, and `func` declarations are namespace exports only. `Signal`, `mpsc.Ring`, diagnostic types and helpers, `Forest`, `Buffer`, `Clock`, `PerCPU`, and `Callback` MUST remain under their owning namespaces.

### Root promotion

The facade MAY add a root export only when all of these conditions are true:

1. The owning domain spec is approved.
2. The domain facade exists.
3. The declaration is public and stable.
4. The family is commonly used enough to justify root access.
5. The name does not collide with another family or domain.
6. The export does not hide ownership, capacity, concurrency, or ordering semantics.

The facade MUST promote type families, not individual variants or stateless functions. For example, callers use `stdx.List.Static`, not `stdx.StaticList`, and `stdx.Heap.Binary`, not `stdx.BinaryHeap`.

### Names that remain namespaced

Stateless functions MUST remain under their domain namespaces. The facade MUST NOT export `stdx.alignUp`, `stdx.loadSlice`, or `stdx.binarySearch`; callers use `stdx.mem.alignUp`, `stdx.bytes.loadSlice`, and `stdx.algo.binarySearch`.

Strong address aliases MUST remain under `addr`. The facade MUST NOT export `stdx.PhysAddr` or `stdx.VirtAddr`; callers use `stdx.addr.PhysAddr` and `stdx.addr.VirtAddr`.

Policy- or backend-heavy domains MUST remain namespaced, including `stdx.arch.x86_64`, `stdx.barrier`, `stdx.io`, `stdx.concurrent`, and `stdx.sync`.

### Export removal and renaming

An export removal or rename MUST update all callers. The facade MUST NOT retain a compatibility alias.

## Implementation constraints

`src/stdx.zig` is the package facade. Domain facades own their public domain surfaces and MUST remain the implementation boundary for their domains.

## Testing

Tests MUST compile an import of `stdx` and verify the exact current namespace exports and the `List` and `Ring` root aliases. The test MUST fail if a required export is missing, resolves to the wrong declaration, or an excluded root alias is added. Domain tests verify the contracts of declarations reached through the facade; facade tests do not duplicate those contracts.

## Usage examples

The following imports are illustrative:

```zig
const stdx = @import("stdx");

const List = stdx.List;
const Ring = stdx.Ring;
const PhysAddr = stdx.addr.PhysAddr;

var tasks = List.Static(Task, 64).init();
var ready = Ring.Static(Task, 128).init();
const pa = PhysAddr.fromInt(0x1000);
```

```zig
const stdx = @import("stdx");

const bits = stdx.bits;
const mem = stdx.mem;
const addr = stdx.addr;

const aligned = mem.alignUp(size, 4096);
const is_pow2 = bits.isPowerOfTwo(4096);
const pa = addr.PhysAddr.fromInt(0x1000);
```

```zig
const stdx = @import("stdx");

const RunQueue = stdx.intrusive.Queue(Thread, "runq_node");
```
