# Root exports

Status: Approved.

`src/zstdx.zig` is the public package facade. It exports domain namespaces and may promote approved flagship type families at root for ergonomic imports.

## Owned scope

This spec owns:

- exact public declarations in `src/zstdx.zig`;
- which domain facades are exported from root;
- which type families are root-promoted;
- rules for adding, removing, and renaming root exports;
- root import examples.

This spec does not own:

- implementation files;
- per-primitive method signatures;
- domain facade internals;
- source tree layout beyond `src/zstdx.zig`.

## Package facade

`src/zstdx.zig` begins with:

```zig
//! Public zstdx facade. Spec: docs/specs/root-exports.md.
```

## Domain namespace exports

The public facade exports domain namespaces.

Approved eventual root surface:

```zig
pub const core = @import("core.zig");
pub const bits = @import("bits.zig");
pub const addr = @import("addr.zig");
pub const layout = @import("layout.zig");
pub const bytes = @import("bytes.zig");
pub const mem = @import("mem.zig");
pub const collections = @import("collections.zig");
pub const intrusive = @import("intrusive.zig");
pub const ranges = @import("ranges.zig");
pub const heaps = @import("heaps.zig");
pub const barrier = @import("barrier.zig");
pub const arch = @import("arch.zig");
pub const sync = @import("sync.zig");
pub const concurrent = @import("concurrent.zig");
pub const io = @import("io.zig");
pub const rings = @import("rings.zig");
pub const tags = @import("tags.zig");
pub const sg = @import("sg.zig");
pub const time = @import("time.zig");
pub const algo = @import("algo.zig");
pub const diag = @import("diag.zig");
```

A domain namespace export lands only when the corresponding domain facade file exists. This spec does not permit empty facade files.

## Root-promoted type families

Root promotion is for commonly used type families, not individual variants or stateless functions.

Approved eventual root-promoted families:

```zig
pub const List = collections.List;
pub const Ring = collections.Ring;
pub const Deque = collections.Deque;
pub const Stack = collections.Stack;
pub const Queue = collections.Queue;

pub const HashMap = collections.HashMap;
pub const HashSet = collections.HashSet;
pub const SparseSet = collections.SparseSet;
pub const SlotMap = collections.SlotMap;
pub const HandleMap = collections.HandleMap;

pub const Heap = heaps.Heap;

pub const BTree = collections.BTree;
pub const IntervalTree = collections.IntervalTree;
pub const RadixTree = collections.RadixTree;
pub const CritBitTree = collections.CritBitTree;
```

Root promotion rules:

- promote families, not individual variants;
- use `zstdx.List.Static`, not `zstdx.StaticList`;
- use `zstdx.Heap.Binary`, not `zstdx.BinaryHeap`;
- do not promote a family until its owning domain facade and spec exist;
- do not promote names that collide with intrusive or domain namespaces.

## First-slice root exports

Only these root exports are eligible in the first implementation slice:

```zig
pub const core = @import("core.zig");
pub const bits = @import("bits.zig");
pub const addr = @import("addr.zig");
pub const ranges = @import("ranges.zig");
pub const layout = @import("layout.zig");
pub const bytes = @import("bytes.zig");
pub const mem = @import("mem.zig");
pub const collections = @import("collections.zig");
pub const intrusive = @import("intrusive.zig");

pub const List = collections.List;
pub const Ring = collections.Ring;
```

`List` and `Ring` are eligible because they are first-slice flagship families. `intrusive` types are not root-promoted initially; callers use `zstdx.intrusive.Queue`, `zstdx.intrusive.Stack`, etc.

## Exports that stay namespaced

### Stateless functions

Stateless functions stay under their domain namespaces:

```zig
zstdx.mem.alignUp
zstdx.bytes.loadUnaligned
zstdx.algo.binarySearch
```

The root facade must not flatten these as:

```zig
zstdx.alignUp
zstdx.loadUnaligned
zstdx.binarySearch
```

### Strong address aliases

Strong address aliases stay under `addr`:

```zig
zstdx.addr.PhysAddr
zstdx.addr.VirtAddr
```

The root facade must not flatten them as:

```zig
zstdx.PhysAddr
zstdx.VirtAddr
```

### Policy/backend-heavy domains

These domains stay namespaced:

```zig
zstdx.arch.x86
zstdx.barrier
zstdx.io
zstdx.concurrent
zstdx.sync
```

## Import examples

Preferred family imports:

```zig
const zstdx = @import("zstdx");

const List = zstdx.List;
const Ring = zstdx.Ring;
const PhysAddr = zstdx.addr.PhysAddr;

var tasks = List.Static(Task, 64).init();
var ready = Ring.Static(Task, 128).init();
const pa = PhysAddr.fromInt(0x1000);
```

Namespace-oriented imports:

```zig
const zstdx = @import("zstdx");

const bits = zstdx.bits;
const mem = zstdx.mem;
const addr = zstdx.addr;

const aligned = mem.alignUp(size, 4096);
const is_pow2 = bits.isPowerOfTwo(4096);
const pa = addr.PhysAddr.fromInt(0x1000);
```

Intrusive types remain namespaced:

```zig
const zstdx = @import("zstdx");

const RunQueue = zstdx.intrusive.Queue(Thread, "runq_node");
```

## Export change rules

A root export may be added only when all are true:

1. the owning domain spec is approved;
2. the domain facade exists;
3. the exported declaration is public and stable;
4. the name is commonly used enough to justify root access;
5. the root name does not collide with another family or domain;
6. the root export does not hide ownership, capacity, concurrency, or ordering semantics.

A root export may be removed or renamed only by updating all callers. Compatibility aliases are not allowed.

## Non-goals

Root exports do not provide:

- compatibility aliases;
- deprecated names;
- hidden wrappers around domain APIs;
- short aliases for stateless functions;
- shortcuts that bypass domain semantics;
- placeholder exports for future modules.
