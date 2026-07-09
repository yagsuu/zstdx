# zstdx

Domain-neutral Zig primitive library with explicit contracts for storage,
external allocation, waiting, capacity, ownership, invalidation, errors,
concurrency, and ordering.

| Field | Value |
| --- | --- |
| Package | `zstdx` |
| Import name | `stdx` |
| Public facade | `src/stdx.zig` |
| Minimum Zig | `0.16.0` |
| Normative specs | `docs/specs/` |

## Scope

`zstdx` provides reusable low-level primitives whose behavior can be specified
without application, protocol, platform, or device policy. It does not provide
complete domain systems; those should be built separately on top of the
primitives here.

Public APIs document external allocation, waiting, concurrency, ordering,
capacity, invalidation, and errors. They do not hide calls to allocators,
blocking APIs, syscalls, atomics, barriers, volatile access, or target-specific
instructions.

## Build

```sh
zig build test
```

The host-side test suite is aggregated by `test/all.zig`.

## Design axis vs `std` and Zig builtins

Every primitive in `zstdx` earns its place by differing from `std` or the Zig
language on at least one of the following axes. When a `std` type covers a
primitive's contract exactly, `zstdx` does not ship a competitor.

- **Freestanding-first.** Every primitive compiles and works without an OS,
  allocator, threading runtime, or `std.Io` implementation. `std` collections
  are `Allocator`-first and assume a hosted environment; `zstdx` collections
  are storage-first and take inline or caller-owned backing storage.
- **No hidden allocation.** No primitive here calls into an allocator, heap,
  or syscall on your behalf. `std.ArrayList`, `std.HashMap`, and friends
  allocate under normal use; `zstdx` collections do not.
- **No vtables in the hot path.** Backends (wait/wake, clock, MMIO) are
  compile-time composed through generic type parameters, not `*Vtable`
  pointers. `std.Io` composes at runtime; `zstdx` composes at compile time.
- **Explicit contracts, not conventions.** Every operation documents its
  allocation, waiting, concurrency, ordering, invalidation, error, and
  mutation-on-error behavior. Zig's language does not force any of these to
  be documented; `zstdx` treats them as part of the API surface.
- **Explicit erroring on preconditions.** Bounds, alignment, capacity, and
  domain-mixing violations are `error.X` returns wherever the caller can
  reasonably act on them, and comptime `@compileError`s wherever they should
  be caught before shipping. `std` frequently returns `void` or panics on
  the same shapes.
- **Domain identity through types, not tags.** Strong types (`PhysAddr`,
  `VirtAddr`, `Instant`, `Duration`, `Tag(Domain, Int)`, `Address(Tag, Int)`)
  prevent accidental mixing across domains. Zig's language has no built-in
  newtype; `zstdx` uses `enum(Int) { _ }` newtypes uniformly.
- **Volatile and target-instruction wrappers with contract text.**
  Instruction-emitting wrappers document ordering, privilege, target gating,
  and clobber contracts. Zig exposes `asm volatile` but not this contract;
  `zstdx` fills the gap without reinventing the ISA.

Each per-primitive table below carries a `Why not std.*?` column that names
the specific `std` or language feature the primitive replaces, and the
concrete axis on which it differs.

## Contract vocabulary

| Field | Meaning |
| --- | --- |
| Storage | Where primitive state or backing storage lives: none, value fields, inline storage, caller-owned storage, embedded nodes, or private arena. |
| External allocation | Whether operations call an external allocator, heap, syscall, runtime API, or other backing-resource provider. Returning memory/resources from inline or caller-owned storage does not count. |
| Waiting | Whether operations block, sleep, spin, wait on I/O, or synchronize. |
| Concurrency | Access contract: pure/value-only, single-owner mutable value, caller-owned storage, external synchronization, or target-gated instruction use. |
| Performance | Hot-path complexity plus slower maintenance, scan, clear, or validation paths. |
| Errors | Public error set, `null` behavior, and programmer-error preconditions. |
| Mutation on error | Whether fallible operations leave logical state unchanged. |
| Invalidation | Which pointers, slices, indexes, handles, ranges, or intrusive memberships become invalid. |
| Ordering | FIFO, LIFO, sorted, insertion order, target instruction order, or none. |
| Why not std.*? | The closest `std.*` type or Zig-language feature and the specific axis on which this primitive differs. |

## Public surface

| Namespace | Families |
| --- | --- |
| `stdx.core` | `SafetyMode`, debug checks, callback traits, `Range(T)` |
| `stdx.bits` | Power-of-two helpers, `BitSet`, `word` arithmetic |
| `stdx.addr` | `Address`, `PhysAddr`, `VirtAddr`, `DmaAddr`, `Page`, page constants |
| `stdx.layout` | `EndianInt`, `Le`, `Be` |
| `stdx.bytes` | Unaligned access, checked offset access, `Cursor` |
| `stdx.mem` | Alignment helpers, `Arena`, `Pool`, `PoolCache`, `BitmapAllocator`, `BuddyAllocator`, `FrameAllocator`, `CachePad`, `CacheAlign` |
| `stdx.collections` | `List`, `Ring` |
| `stdx.intrusive` | Intrusive `List`, `Queue`, `Stack` |
| `stdx.ranges` | `RangeSet`, `RangeMap` |
| `stdx.graph` | `Forest` |
| `stdx.algo` | Allocation placement algorithms, buddy arithmetic |
| `stdx.tags` | `Tag`, `TagAllocator` |
| `stdx.arch` | Target-gated instruction primitives, typed CPUID decoders |
| `stdx.diag` | Scoped diagnostics, `PanicLog` |
| `stdx.sync` | `Signal`, `AtomicCell`, `RawSpinLock`, `Once`, `Rendezvous`, `spin.Backend` |
| `stdx.concurrent` | `mpsc.Ring`, `spsc.Ring` |
| `stdx.cpu` | `PerCpu` |
| `stdx.time` | `Instant`, `Duration`, `Clock.Monotonic`, `Deadline`, `Backoff`, `RateCounter` |
| `stdx.barrier` | `compiler`, `mmio` fences, `dma` fences |
| `stdx.io` | `Mmio.Register`, `Mmio.Window`, `Mmio.Window32`, `Mmio.Window64`, `poll.until` |
| `stdx.dma` | `Buffer`, `ScatterGather.Segment`/`List`/`Builder` |
| `stdx.func` | `Callback`, `Closure` |

| Root export | Canonical home | Notes |
| --- | --- | --- |
| `stdx.List` | `stdx.collections.List` | Root-promoted family: `Static`, `Bounded`. |
| `stdx.Ring` | `stdx.collections.Ring` | Root-promoted family: `Static`, `Bounded`. |

Stateless functions and domain-specific strong types stay namespaced. Examples:
`stdx.mem.alignUp`, `stdx.bytes.loadUnaligned`, `stdx.addr.PhysAddr`.

## Implemented primitive families

### Core

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Safety options | `SafetyMode` | Value enum | Never | `build_mode`, `checked`, `unchecked`; controls optional zstdx checks only. | `std.builtin.Mode` reports optimize mode; `SafetyMode` chooses whether zstdx primitives run their own extra checks *independent* of optimize mode. |
| Debug checks | `debug.checksEnabled(mode)` | None | Never | Comptime predicate; explicit `assertValid` calls always check. | Zig's `std.debug.assert` cannot be selectively enabled per module; `checksEnabled` gates optional invariants without a global switch. |
| Callback traits | `Order = std.math.Order`, `Compare`, `LessThan`, `Eql`, `Hash` | Function type factories | Never | `*const T` operands avoid required copies; laws are caller contracts. | `std.math.Order` is reused for ordering vocabulary; `std.sort`/`std.HashMap` still require ad-hoc callback or context shapes, while these factories give one pointer-operand shape reused across collections. |
| Ranges | `Range(T)` | Value struct | Never | Unsigned half-open `[start, end)` range; checked construction/arithmetic; O(1); no mutation outside returned values. | Zig has no `Range` type; `std` treats slices as ranges implicitly. `Range(T)` gives a strongly-typed half-open interval independent of any slice. |

### Bits

| Family | APIs / variants | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Power-of-two helpers | `isPowerOfTwo`, `nextPowerOfTwo` | None | Never | Pure O(1) unsigned helpers; `isPowerOfTwo(0) == false`; `nextPowerOfTwo(0) == 1`; overflow is explicit. | `std.math.isPowerOfTwo` exists but does not fix `0`'s answer; `std.math.ceilPowerOfTwo*` families are split across signed/unsigned/assert variants. `stdx.bits` gives one contract per name. |
| `BitSet` | `BitSet.Static(N)` | Inline `u64` words | Never | Fixed index set over `0..N`; index ops O(1); scans/algebra O(word_count); mutator bounds errors leave state unchanged; mutators return the prior bit. | `std.bit_set.StaticBitSet` panics on out-of-bounds and its mutators return `void`; `BitSet.Static` returns `error.OutOfBounds` and the prior bit value so callers can branch on the transition. |
| `bits.word` | `word.count`, `word.lastMask`, `word.indexOf`, `word.maskOf`, `word.isSet`, `word.set`, `word.clear` | Caller-owned `[]Word` | Never | Unchecked bit/word arithmetic factored out of every bitmap consumer (`BitSet.Static`, `BitmapAllocator`, `BuddyAllocator`, `TagAllocator`); `Word` is any unsigned integer type; bounds are caller-enforced with an optional `checksEnabled(.build_mode)` assert. | `std` has no shared word-of-bits arithmetic surface — each bitmap consumer reinvents `ceilDiv`, `lastMask`, `indexOf`, and `maskOf` locally. `bits.word` is one comptime-generic implementation used across bitmap consumers. |

### Addresses and pages

| Family | APIs / variants | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| `Address` | `Address(Tag, Int)`, `PhysAddr`, `VirtAddr`, `DmaAddr` | Value enum | Never | Strong typed unsigned address values; checked arithmetic and alignment; tag identity prevents accidental domain mixing. | Zig has no newtype and `std` uses bare `usize`/`u64` for addresses; nothing prevents mixing physical, virtual, and DMA addresses. `Address(Tag, Int)` makes each domain a distinct type. |
| Page constants | `_4kib`, `_16kib`, `_64kib`, `_2mib`, `_1gib` | None | Never | Exact byte counts only; no platform support or policy implied. | `std.heap.pageSize()` and `std.heap.page_size_{min,max}` describe host/target allocation pages; page-tier constants for firmware, MMU, and DMA sizing have no home in `std`. |
| `Page` | `Page(Addr, page_size)` | Value types under returned namespace | Never | `Size`, `Count`, `Frame`, `FrameRange`; checked byte/page conversion, frame arithmetic, containment, overlap, span, and split. | Zig has no page/frame algebra; `std.mem.alignForward` on `usize` loses the domain distinction. `Page(Addr, ...)` gives frame arithmetic parameterized on the address type. |

### Layout

| Family | APIs / variants | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| `EndianInt` | `EndianInt(T, endian)`, `Le(T)`, `Be(T)` | Value `extern struct` with byte array | Never | Alignment 1; size from bit width; unsigned byte-aligned integer lanes; target-endian independent conversion. | `std.mem.readInt`/`writeInt` work on byte slices, not typed fields. `Le(u32)`/`Be(u32)` are composable field types that carry endian in the type and compose losslessly inside `extern struct` overlays. |

### Bytes

| Family | APIs / variants | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Unaligned access | `loadUnaligned`, `storeUnaligned` | Caller byte window | Never | Byte-copy fixed-window typed access; no bounds check, endian conversion, validation, volatile access, or pointer reinterpretation. | `@as(*align(1) T, @ptrCast(...))` requires the caller to keep alignment attributes correct on every path. `loadUnaligned`/`storeUnaligned` centralize the byte-copy discipline behind one call. |
| Checked offset access | `load`, `store`, `loadSlice`, `storeSlice`, `loadTail` | Caller byte slice | Never | Bounds-checked random access; `error.EndOfStream` for overrun or offset overflow; failed stores do not partially write. | `std.mem.readInt`/`writeInt` on subslices assumes bounds; `bytes.load`/`bytes.store` return `error.EndOfStream` and refuse partial writes. |
| `Cursor` | `Cursor` | Borrowed `[]const u8` plus index | Never | Forward read cursor; checked peek/read/skip; typed reads compose unaligned access; value-copy checkpointing. | `std.io.FixedBufferStream`/`std.Io.Reader` bundle allocation and vtable dispatch; `Cursor` is a bare index over a borrowed slice. |

### Memory

#### `mem.Arena`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `Arena.Static(N)` | Inline `[N]u8` | `init()` | Comptime `N` bytes |
| `Arena.Bounded` | Caller-owned `[]u8` | `wrap(buffer)` | `buffer.len` bytes |

| Contract | Value |
| --- | --- |
| External allocation | Never. Arena operations only consume inline or caller-owned bytes. The allocator view is backed by the same fixed storage. |
| Waiting | Never. |
| Concurrency | Single-owner mutable value; shared mutable access requires external synchronization. |
| Performance | Bump allocation, mark, restore, reset, and position helpers are O(1). |
| Errors | `error.OutOfMemory`, `error.InvalidAlignment`, `error.Overflow`; invalid marks are programmer errors. |
| Mutation on error | Allocation errors leave `index` unchanged. |
| Invalidation | `restore` invalidates allocations after the mark; `reset` invalidates all allocations. |
| Ordering | Monotonic bump order until restore/reset. |
| Why not std.*? | `std.heap.ArenaAllocator` requires a backing `Allocator` and grows dynamically. `Arena.Static/Bounded` refuse to grow, have no allocator dependency, and expose `mark`/`restore`/`reset` positions directly. |

#### `mem.Pool`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `Pool.Static(T, N)` | Inline `[N]Slot` | `init()` | Comptime `N` slots |
| `Pool.Bounded(T)` | Caller-owned `[]Slot` | `wrap(buffer)` | `buffer.len` slots |

| Contract | Value |
| --- | --- |
| External allocation | Never. Slots come from inline or caller-owned storage. |
| Waiting | Never. |
| Concurrency | Single-owner mutable value; shared mutable access requires external synchronization. |
| Performance | `acquire` and `release` are O(1); clear and validation are O(N). |
| Errors | `acquire` returns `error.OutOfMemory`; `release` misuse is a programmer error. |
| Mutation on error | Failed `acquire` leaves the pool unchanged. |
| Invalidation | `release(item)` invalidates that pointer; `clearRetainingCapacity()` invalidates all live pointers. |
| Debug fill | `checksEnabled(.build_mode)` overwrites the payload window with `0xCD` on `acquire` and `0xFD` on `release`; ReleaseFast/ReleaseSmall skip both writes. |
| Ordering | Released slots are reused LIFO. |
| Why not std.*? | `std.heap.MemoryPool` is an allocator wrapper that grows. `Pool.Static/Bounded` is fixed-capacity, freestanding, and returns `error.OutOfMemory` deterministically at the caller-declared limit. |

#### `mem.PoolCache`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `PoolCache(T, RegionSource)` | Caller-supplied `RegionSource` handing fixed-size aligned regions; each region hosts an intrusive `RegionHeader` plus a contiguous `[slots_per_region]Slot` array of the inner `Pool.Bounded(T)` | `init(source)` | `region_count * slots_per_region`, grown by explicit `refill` |

| Contract | Value |
| --- | --- |
| External allocation | Never on `acquire` / `release` / `drain`. `refill` calls `RegionSource.acquire` exactly once and propagates its error unchanged. |
| Waiting | Never inside the cache; `RegionSource.acquire` is out of scope for the cache contract. |
| Concurrency | Single-owner mutable value; shared mutable access requires external synchronization. Slots inherit the inner `Pool.Bounded(T)`'s single-owner discipline. |
| Performance | `acquire` / `release` are O(1) amortized (empty/partial/full three-list membership avoids full-list scans); `contains` is O(region_count); `drain` walks only the empty list; `refill` is O(1) plus one `RegionSource.acquire` call. |
| Errors | `acquire` returns `error.OutOfMemory` when every region is full; `refill` returns `RefillError`, the union of `RegionSource.Error` and `error{OutOfMemory}` (collapses when the source's set already contains `OutOfMemory`); zero-sized `T`, a `RegionSource` missing required declarations, or a region layout that cannot fit `RegionHeader + Slot` are compile errors. |
| Mutation on error | Failed `acquire` and failed `refill` leave the cache unchanged; the source pointer is never retained on error. |
| Invalidation | `release(item)` invalidates that pointer; `drain` invalidates every pointer that used to live in a fully-empty region (already released by contract). |
| Ordering | LIFO slot reuse inside each region; deterministic empty/partial/full list order. |
| Why not std.*? | `std` has no multi-region typed object cache. `PoolCache` is the `kmem_cache_alloc`-shaped substrate: many `Pool.Bounded(T)` instances behind one class, growing only on explicit `refill`, with the region source (page allocator, boot heap, IOMMU-mapped region, `FrameAllocator.FrameSource`) chosen by the caller. |

#### `mem.BitmapAllocator`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `BitmapAllocator.Static(units)` | Inline bitmap words | `init()` | Comptime unit count |
| `BitmapAllocator.Bounded` | Caller-owned `[]u64` words | `wrap(words, unit_capacity)` | Runtime unit count |

| Contract | Value |
| --- | --- |
| External allocation | Never. Allocation state is stored in inline or caller-owned bitmap words. |
| Waiting | Never. |
| Concurrency | Single-owner mutable value; shared mutable access requires external synchronization. |
| Performance | `allocOne` scans words; `allocRange` scans units; reserve/free-one are O(1); reserve/free-range are O(range length). |
| Errors | `error.OutOfMemory`, `error.OutOfBounds`, `error.AlreadyAllocated`, `error.NotAllocated`. |
| Mutation on error | Reserve/free range validate before mutating; errors leave state unchanged. |
| Invalidation | Mutates allocation state for selected units only. |
| Ordering | Lowest-index first-fit allocation. |
| Why not std.*? | `std` has no fixed-capacity bitmap allocator. It is the substrate for page-tier and tag-tier allocation where an `Allocator`-based scheme cannot serve the size class. |

#### `mem.BuddyAllocator`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `BuddyAllocator.Static(unit_capacity, order_count)` | Inline bitmap words | `init()` | Comptime unit capacity |
| `BuddyAllocator.Bounded` | Caller-owned `[]u64` words | `wrap(words, unit_capacity, order_count)` | Runtime unit capacity |

| Contract | Value |
| --- | --- |
| External allocation | Never. Backing bitmap words are inline or caller-owned. |
| Waiting | Never. |
| Concurrency | Single-owner mutable value; shared mutable access requires external synchronization. |
| Performance | `alloc(order)` scans the per-order bitmap for the lowest free block and, on miss, splits down from the smallest higher order; `free` performs eager buddy coalescing; `reserve(range)` splits down per unit; queries are O(order_count · word_count). |
| Errors | `error.OutOfMemory`, `error.OutOfBounds`, `error.InvalidOrder`, `error.InvalidRequest`, `error.AlreadyAllocated`, `error.NotAllocated`, `error.Overflow`. |
| Mutation on error | Every fallible operation validates before mutating; errors leave state unchanged. |
| Invalidation | Mutates allocation state for units in the affected block only. |
| Ordering | Lowest-index first-fit split-and-place. |
| Why not std.*? | `std` has no power-of-two buddy allocator over abstract units. `BuddyAllocator` composes with `stdx.algo.allocation.Buddy` for split/buddy arithmetic and returns `stdx.algo.allocation.Buddy.Block` values callers translate to their own domain (page frames, DMA regions, descriptor groups). |

#### `mem.FrameAllocator`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `FrameAllocator.Static(Backend, Page, base_frame)` | Inline `Backend` (typically `BuddyAllocator.Static`); comptime `base_frame` anchor | `init()` | Comptime `Backend.capacity()` frames |
| `FrameAllocator.Bounded(Backend, Page)` | Runtime `Backend` value; runtime `base: Page.Frame` | `wrap(backend, base)` | `backend.capacity()` frames |

| Contract | Value |
| --- | --- |
| External allocation | Never. Delegates to the inline / caller-owned `Backend`; the frame allocator adds no storage of its own. |
| Waiting | Never. |
| Concurrency | Single-owner mutable value; shared mutable access requires external synchronization. |
| Performance | `alloc` / `free` / `reserve` cost matches `Backend`; unit-to-frame conversion is O(1) checked arithmetic; `largestFreeOrder` walks the backend per call. |
| Errors | `error.OutOfMemory`, `error.OutOfBounds`, `error.InvalidRequest`, `error.InvalidOrder`, `error.AlreadyAllocated`, `error.NotAllocated`, `error.Overflow`. `Backend.Error` MUST be a subset of the frame-allocator error set — a broader backend fails to instantiate. |
| Mutation on error | Every fallible operation validates before delegating to the backend; error paths leave both wrappers and backend state unchanged. |
| Invalidation | Mutates only the affected `FrameRange`; other outstanding ranges are unaffected. |
| Ordering | Inherits the backend's placement (`BuddyAllocator` gives lowest-index first-fit); `FrameRange` values carry the caller's `Page` domain identity. |
| Why not std.*? | `std` has no page-typed frame allocator over an abstract unit-index backend. `FrameAllocator` lifts a `usize`-unit allocator into `Page.Frame` / `Page.FrameRange` vocabulary, owns the base-frame anchor and `reserve` translation once, and exposes `frameSource(order)` — a `RegionSource` view — that composes directly with `mem.PoolCache`. |

#### `mem.CachePad` and `mem.CacheAlign`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Cache-line padding | `CachePad(T)`, `CacheAlign(T)` | Value structs with `align(std.atomic.cache_line)` payload; `CachePad` adds trailing `_pad` bytes rounded to a whole cache line | Never | `CachePad` guarantees adjacent instances occupy disjoint cache lines (false-sharing isolation); `CacheAlign` only guarantees a cache-line-aligned start; `void`, zero-sized, or over-aligned `T` are compile errors. | Zig has no cache-line padding helper. `CachePad`/`CacheAlign` centralize the alignment + trailing-pad discipline as one-argument type factories so downstream primitives (`PerCpu`, `mpsc.Ring`, `spsc.Ring`, `PanicLog`) do not hand-write the pair. |

#### Memory alignment helpers

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Alignment helpers | `alignUp`, `alignDown`, `isAligned`, `alignUpDelta`, `alignDownDelta` | None | Never | Pure O(1) unsigned helpers; invalid alignment is explicit where fallible; rounding overflow is explicit. | `std.mem.alignForward`/`alignBackward` panic on non-power-of-two alignment; `mem.alignUp*` returns `error.InvalidAlignment` and `error.Overflow` instead. |

### Collections

#### `collections.List`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `List.Static(T, N)` | Inline `[N]T` | `init()` | Comptime `N` items |
| `List.Bounded(T)` | Caller-owned `[]T` | `wrap(buffer)` | `buffer.len` items |

| Contract | Value |
| --- | --- |
| External allocation | Never. Storage is inline or caller-owned. |
| Waiting | Never. |
| Concurrency | Single-owner mutable value; shared mutable access requires external synchronization. |
| Performance | `append`, `pop`, `swapRemove`, `at`, and capacity helpers are O(1); `appendSlice`, `insert`, and `orderedRemove` are O(n). |
| Errors | `error.Full`, `error.OutOfBounds`; `pop()` returns `null` when empty; assume-capacity misuse is a programmer error. |
| Mutation on error | All error returns leave the list unchanged. |
| Invalidation | `insert` and `orderedRemove` invalidate at/after index; `swapRemove` invalidates removed index and old last; clear invalidates all initialized-element pointers/slices. |
| Ordering | Append and insert preserve order; `orderedRemove` preserves order; `swapRemove` does not. |
| Why not std.*? | `std.ArrayList.initBuffer` can borrow caller storage, but the type still exposes allocator-taking growth APIs and assert-heavy operations. `List.Static/Bounded` exposes only fixed-capacity operations: `error.Full` at capacity, inline or caller-owned storage, no allocator dependency, and explicit invalidation/no-mutation contracts. |

#### `collections.Ring`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `Ring.Static(T, N)` | Inline `[N]T` | `init()` | Comptime `N` items |
| `Ring.Bounded(T)` | Caller-owned `[]T` | `wrap(buffer)` | `buffer.len` items |

| Contract | Value |
| --- | --- |
| External allocation | Never. Storage is inline or caller-owned. |
| Waiting | Never. |
| Concurrency | Single-owner mutable value; shared mutable access requires external synchronization. |
| Performance | Push, pop, front, back, clear, and capacity helpers are O(1). |
| Errors | `pushBack` returns `error.Full`; `popFront`, `front`, and `back` use `null` for empty; assume-capacity misuse is a programmer error. |
| Mutation on error | `error.Full` leaves the ring unchanged. |
| Invalidation | Push invalidates back pointer; pop invalidates old front pointer; overwrite-oldest on full invalidates old front and old back; clear invalidates front/back pointers. |
| Ordering | FIFO. `pushBackOverwriteOldest` appends newest and evicts oldest when full. |
| Why not std.*? | `std.Deque.initBuffer` can provide a bounded double-ended queue, but it exposes a broader deque/growth surface and has no overwrite-oldest FIFO contract. `Ring.Static/Bounded` is a narrow fixed-capacity FIFO ring with explicit `Full` behavior and `pushBackOverwriteOldest`. |

### Intrusive collections

#### `intrusive.List`

| Variant / type | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `SinglyLinkedNode` | Embedded in caller object | Field initializer | Caller object count |
| `DoublyLinkedNode` | Embedded in caller object | Field initializer | Caller object count |
| `SinglyLinked(T, field)` | Endpoint pointers in list, links in caller nodes | `init()` | No fixed capacity |
| `DoublyLinked(T, field)` | Endpoint pointers in list, links in caller nodes | `init()` | No fixed capacity |

| Contract | Value |
| --- | --- |
| External allocation | Never. Parent objects and nodes are caller-owned. |
| Waiting | Never. |
| Concurrency | Single-owner mutable list; shared mutable access requires external synchronization. |
| Performance | Endpoint insertion/removal is O(1) except singly-linked `tryRemove`, which scans. Clear and validation walk linked nodes. |
| Errors | No public error set; empty pops return `null`; double insert, wrong field, wrong list, and corrupted links are programmer errors. |
| Mutation on error | Not applicable for public errors; programmer-error misuse may assert. |
| Invalidation | Insert/remove/clear change intrusive membership and neighbor links; parent object addresses are not moved. |
| Ordering | Singly and doubly linked lists preserve explicit link order. |
| Why not std.*? | `std.SinglyLinkedList`/`std.DoublyLinkedList` already provide intrusive node storage. `intrusive.List` reuses that storage shape and adds typed `field` binding, parent-pointer recovery, endpoint contracts, and multi-membership discipline for caller-declared structs. |

#### `intrusive.Queue`

| Family | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `Queue(T, field)` | Queue endpoints plus caller-owned `SinglyLinkedNode` fields | `init()` | No fixed capacity |

| Contract | Value |
| --- | --- |
| External allocation | Never. Parent objects and nodes are caller-owned. |
| Waiting | Never. |
| Concurrency | Single-owner mutable queue; shared mutable access requires external synchronization. |
| Performance | Endpoint access, `pushBack`, and `popFront` are O(1); clear and validation walk queued nodes. |
| Errors | No public error set; empty endpoint access and empty pop return `null`; double insert and corrupted links are programmer errors. |
| Mutation on error | Not applicable for public errors. |
| Invalidation | `popFront` and `clear` detach memberships; parent object addresses are not moved. |
| Ordering | FIFO. |
| Why not std.*? | `std.SinglyLinkedList` can be used to build a queue manually, but callers must manage node-to-parent recovery and endpoints themselves. `intrusive.Queue` binds a caller-owned node field to a typed FIFO API without allocation or payload moves. |

#### `intrusive.Stack`

| Family | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `Stack(T, field)` | Top pointer plus caller-owned `SinglyLinkedNode` fields | `init()` | No fixed capacity |

| Contract | Value |
| --- | --- |
| External allocation | Never. Parent objects and nodes are caller-owned. |
| Waiting | Never. |
| Concurrency | Single-owner mutable stack; shared mutable access requires external synchronization. |
| Performance | `peek`, `push`, and `pop` are O(1); clear and validation walk stacked nodes. |
| Errors | No public error set; empty peek/pop returns `null`; double insert and corrupted links are programmer errors. |
| Mutation on error | Not applicable for public errors. |
| Invalidation | `pop` and `clear` detach memberships; parent object addresses are not moved. |
| Ordering | LIFO. |
| Why not std.*? | `std.SinglyLinkedList` can be used as a LIFO manually, but callers must manage node-to-parent recovery themselves. `intrusive.Stack` binds a caller-owned node field to a typed LIFO API without allocation or payload moves. |

### Ranges

#### `ranges.RangeSet`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `RangeSet.Static(T, N)` | Inline `[N]Range` | `init()` | Comptime `N` ranges |
| `RangeSet.Bounded(T)` | Caller-owned `[]Range` | `wrap(buffer)` | `buffer.len` ranges |

| Contract | Value |
| --- | --- |
| External allocation | Never. Storage is inline or caller-owned. |
| Waiting | Never. |
| Concurrency | Single-owner mutable value; shared mutable access requires external synchronization. |
| Performance | Queries and mutations scan stored canonical ranges; insertion/removal may shift or split entries. |
| Errors | `error.Full`, `error.InvalidRange`. |
| Mutation on error | Failed insert/remove leaves the set unchanged. |
| Invalidation | Mutations invalidate slices returned by `asConstSlice`. |
| Ordering | Stored ranges are sorted, non-overlapping, and non-adjacent; insertion coalesces overlap/adjacency. |
| Why not std.*? | `std.AutoHashMap` stores discrete keys, not intervals. `RangeSet` maintains sorted, non-overlapping, non-adjacent ranges with coalescing; there is no `std` equivalent. |

#### `ranges.RangeMap`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `RangeMap.Static(T, V, N)` | Inline `[N]Entry` | `init()` | Comptime `N` entries |
| `RangeMap.Bounded(T, V)` | Caller-owned `[]Entry` | `wrap(buffer)` | `buffer.len` entries |

| Contract | Value |
| --- | --- |
| External allocation | Never. Storage is inline or caller-owned. |
| Waiting | Never. |
| Concurrency | Single-owner mutable value; shared mutable access requires external synchronization. |
| Performance | Lookup and mutation scan sorted entries; insert/assign/remove may shift or split entries; coalescing scans adjacent entries. |
| Errors | `error.Full`, `error.InvalidRange`, `error.Overlap`. |
| Mutation on error | Failed insert/assign/remove leaves the map unchanged. |
| Invalidation | Mutations invalidate returned slices, entries, and value pointers. |
| Ordering | Entries are sorted by ascending range start; adjacent entries are allowed unless explicitly coalesced. |
| Why not std.*? | `std.AutoHashMap`/`std.AutoArrayHashMap` map single keys to values. `RangeMap` maps intervals to values with explicit `error.Overlap` on non-coalesced insert; there is no `std` equivalent. |

### Graph

#### `graph.Forest`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `Forest.Static(capacity)` | Inline `[capacity]Links` | `init()` | Comptime node count |
| `Forest.Bounded()` | Caller-owned `[]Links` | `wrap(links)` | `links.len` nodes |
| `Forest.Linked(T, field)` | Embedded `LinkedNode` fields in caller objects | `init()` | Caller object count |

| Contract | Value |
| --- | --- |
| External allocation | Never. Dense variants use inline/caller link tables; linked variant uses caller-owned objects. |
| Waiting | Never. |
| Concurrency | Single-owner mutable forest; shared mutable access requires external synchronization. |
| Performance | Dense append/access/remove are O(1) after validation; linked append/remove are pointer operations; clear/validation walk topology. |
| Errors | Dense variants return `OutOfBounds`, `AlreadyLinked`, `NotLinked`; linked misuse is a programmer error. |
| Mutation on error | Dense variant errors leave the forest unchanged. |
| Invalidation | Dense mutation changes topology for node IDs; linked remove/clear detach memberships; payload ownership stays with caller. |
| Ordering | Root and child sibling order is deterministic insertion order. |
| Why not std.*? | `std` has no tree/forest primitive; existing options are ad-hoc `std.ArrayList` wrapping. `Forest` provides both dense (index-keyed) and intrusive (pointer-keyed) topologies with explicit link-state errors. |

### Algorithms

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Allocation placement | `Request`, `Selection`, `FirstFit`, `BestFit`, `WorstFit` | Caller-provided free-range slice | Never | Pure selection over sorted non-overlapping ranges; does not mutate input; explicit invalid request/alignment/overflow errors. | `std` has no allocation-placement algorithm library — `std.heap.*` bundles allocation strategy into an `Allocator` implementation. `algo.allocation` exposes the placement decision alone, reusable across bitmap/pool/buddy substrates. |
| Buddy arithmetic | `Buddy` | Value inputs/outputs | Never | Pure block/order arithmetic; no allocator storage or mutation. | `std` has no buddy-tier arithmetic; downstream page-tier allocators can consume this without a chosen storage layout. |

### Tags

#### `tags.TagAllocator`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `TagAllocator.Static(Domain, Int, capacity)` | Inline bitmap words | `init()` | Comptime tag capacity |
| `TagAllocator.Bounded(Domain, Int)` | Caller-owned `[]u64` words | `wrap(words, tag_capacity)` | Runtime tag capacity |

| Contract | Value |
| --- | --- |
| External allocation | Never. Allocation state is stored in inline or caller-owned bitmap words. |
| Waiting | Never. |
| Concurrency | Single-owner mutable value; shared mutable access requires external synchronization. |
| Performance | `allocOne` scans for the lowest free tag; reserve/free-one are O(1); validation scans words. |
| Errors | `error.OutOfTags`, `error.OutOfBounds`, `error.AlreadyAllocated`, `error.NotAllocated`. |
| Mutation on error | Allocation, reserve, and free errors leave state unchanged. |
| Invalidation | Mutates tag allocation state only; tag values remain plain strong identifiers. |
| Ordering | Lowest-free-index allocation. |
| Why not std.*? | `std` has no strong-typed identifier allocator. `TagAllocator` gives per-domain identifier issuance with a bitmap substrate; identifiers are `Tag(Domain, Int)` values distinct from raw integers. |

#### `tags.Tag`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Strong tag | `Tag(Domain, Int)` | Value enum | Never | Domain identity is type-level; raw conversion is explicit. | Zig has no newtype; passing a `u32` reader ID and a `u32` writer ID indistinguishably is legal. `Tag(Domain, Int)` gives each domain a distinct type. |

### Target-specific

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Target gate | `arch.x86_64.supported` | Value constant | Never | Import is portable; instruction-emitting operations are gated to the matching target. | `std.builtin.cpu.arch` gives the raw target; `arch.x86_64.supported` is the boolean predicate an operation-emitting wrapper checks before `@compileError`ing on wrong targets. |
| Port I/O | `arch.x86_64.Port`, `ioWait` | Value enum plus instruction effects | Never | Strong `u16` port values; scalar and slice `in*`/`out*` operations. | `std` has no port I/O wrappers. `Port` is a strong `u16` newtype and the `in*`/`out*` calls emit `in`/`out` instructions directly. |
| CPU / query / control wrappers | `Cpuid` (raw + `Vendor`/`Version`/`BasicFeatureEdx`/`Ecx`/`StructuredEbx`/`Ecx`/`Edx`/`ExtendedFeatureEdx`/`Ecx` masks, `Cache.Descriptor`/`Iterator`, `AddressSizes`, `brandString`), `Msr`, `ControlRegister`, `Rflags`, `Interrupts`, `Cpu` (`halt`, `pause`, `breakpoint`, `Tsc.read`/`readSerializing`, `Tlb.invalidatePage`/`invalidatePcid`), `Descriptor` (`Gdt`, `Idt`, `TaskRegister`, `Ldtr`), `DebugRegister.Dr0..Dr7`, `Segment`, `Fence`, `Cache`, `Privilege` | Value wrappers or instruction effects | Never | Thin target-gated instruction primitives; typed CPUID decoders `@bitCast` the raw register words into `packed struct(u32)` masks with `hasReserved()` reporting on unknown bits; no generic policy, field decoding beyond bit layouts, or descriptor layout ownership. | `std` has no CPUID, MSR, CR, RFLAGS, TSC, TLB-invalidate, debug-register, or LDT wrapper. `arch.x86_64` gives the ISA layer with inline-asm-only wrappers matching Intel SDM instruction semantics and documented clobbers; the typed CPUID decoders replace the ~50-line `cpuid` + hand-`@bitCast` snippet every downstream project would otherwise write. |

### Diagnostics

#### `diag.Diagnostics`

| Family | APIs | Storage | Constructor |
| --- | --- | --- | --- |
| Scoped diagnostics | `Diagnostics.Static`, `Scope`, `FormattedDetail`, `fmt`, `scope` | Inline frame slots plus inline detail arena bytes | `Diagnostics.Static(.{ ... }).init()` |

| Contract | Value |
| --- | --- |
| External allocation | Never. Frames and formatted-detail bytes come from inline storage; arena exhaustion omits formatted detail without replacing the originating error. |
| Waiting | Never. Diagnostics uses no heap, syscalls, locks, or blocking operations. |
| Concurrency | Single-owner mutable diagnostics value; shared mutable access requires external synchronization. |
| Performance | Scope open is an inline frame-slot push; `fmt` details registered through `scope()` are formatted only by `Scope.unwind()` on the error path. |
| Errors | Diagnostic operations are infallible; diagnostic capacity exhaustion does not replace the originating error. |
| Mutation on error | Diagnostics never masks the original failure with diagnostic capacity exhaustion. |
| Invalidation | `clear()`/`deinit()` invalidate retained frames and formatted details and reset the inline arena. |
| Ordering | Retained frames render in deterministic DFS pre-order. |
| Why not std.*? | `std.log` is per-message logging with no scope-tree structure and no zero-alloc path. `Diagnostics` is scoped context for one propagated error path, formatted lazily, with strict "never replace the originating error" behavior. |

#### `diag.PanicLog`

| Family | APIs | Storage | Constructor |
| --- | --- | --- | --- |
| Panic-safe ring log | `PanicLog.Static(capacity_bytes)`, `PanicLog.DrainState`, `init`, `clear`, `write`, `drain`, `dropped`, `published`, `isSeated`, `isValid`, `assertValid` | Inline `[capacity_bytes]u8` plus cache-padded `head`, `tail`, `seat`, `seq`, `dropped_seq` atomics | `Static(N).init()` |

| Contract | Value |
| --- | --- |
| External allocation | Never. Byte storage is inline. |
| Waiting | Never. `write` is one bounded seat-CAS attempt (drop on contention); `drain` never blocks writers. |
| Concurrency | Multi-writer via seat CAS (NMI/IRQ/MCE safe); exactly one reader via `drain`. |
| Performance | `write` is one CAS + O(payload + overwrite frames); `drain` is O(bytes drained + sink cost); counter queries are O(1). |
| Errors | `write` returns `error.WriterBusy` (seat contention), `error.PayloadTooLarge`, `error.EmptyPayload`. `drain` propagates `std.Io.Writer.Error` unchanged. |
| Mutation on error | Empty/too-large payloads are rejected before any state change; `WriterBusy` still increments `dropped_seq`. |
| Invalidation | Byte-overflow eviction overwrites whole frames from `tail`; `dropped_seq` accounts for both seat-contention drops and overwrite drops. |
| Ordering | Monotonic 64-bit `seq` counter; header (`Le(u32)` length + `Le(u32)` seq_low) is written under seat exclusion; `head` release-store publishes the frame; `drain` uses acquire loads on `seq`, `head`, `dropped_seq`, resyncs mid-drain on overwrite races. |
| Why not std.*? | `std.log`/`std.debug` are per-message logging with no panic-safe fixed-capacity ring, no NMI-safe writer path, and no overwrite-oldest policy. `PanicLog` is the sink that survives kernel panic, hypervisor VM-exit faults, firmware pre-runtime failures, and NMI/MCE handlers. |

### CPU

#### `cpu.PerCpu`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `PerCpu.Static(T, N)` | Inline `[N]CachePad(T)` | `init(default)`, `initFn(make)`, `initEach(fill)`, `initUndefined()` | Comptime `N` slots |
| `PerCpu.Bounded(T)` | Caller-owned `[]CachePad(T)` | `wrap(slots, default)`, `wrapFn`, `wrapEach`, `wrapUndefined` | `slots.len` slots |

| Contract | Value |
| --- | --- |
| External allocation | Never. Storage is inline or caller-owned. |
| Waiting | Never. |
| Concurrency | Slots are cache-line padded; each slot is single-owner unless the payload type carries its own concurrency contract (e.g. `AtomicCell(T)`). |
| Performance | `get`, `getPtr`, `at`, `atPtr`, `slots`, `slotsConst` are O(1) with a `checksEnabled(.build_mode)`-gated bounds assert on the unchecked accessors. |
| Errors | `at`/`atPtr` return `error.OutOfBounds`; `get`/`getPtr` are unchecked in release with a debug-mode assert. |
| Mutation on error | Bounds errors leave the accessor's caller state unchanged. |
| Invalidation | Slot pointers are valid for the lifetime of the container. |
| Ordering | Slot index maps directly to CPU / partition identity chosen by the caller. |
| Why not std.*? | `std` has no per-CPU storage abstraction. `PerCpu` is the false-sharing-safe slot vector that scheduler code, per-CPU counters, and per-CPU state can plug into without hand-writing the cache-line padding. |

### Synchronization

#### `sync.Signal`

| Family | APIs | Storage | Constructor |
| --- | --- | --- | --- |
| Manual-reset signal | `Signal.State`, `Signal.Token`, `Signal.Manual(Backend)` | One atomic `usize` word plus backend value | `Signal.State.init(initial)`; `Signal.Manual(Backend).init(initial, backend)` |

| Contract | Value |
| --- | --- |
| External allocation | Never. State is one atomic word; the backend value is stored inline. |
| Waiting | `set` and `clear` never wait; `wait` delegates to the compile-time backend's `wait(&state, token)`. |
| Concurrency | Multi-producer `set`/`clear`; any number of `wait`ers via the backend. `Signal.State` observation is lock-free. |
| Performance | `set`, `clear`, `isSet`, and `stateRef` are O(1) CAS or acquire loads; `wait` loops until observing the set flag. |
| Errors | Backend-defined `WaitError`; propagated unchanged. `set` and `clear` are infallible. |
| Mutation on error | Redundant `set`/`clear` leave the state word unchanged; backend `wait` failure does not mutate state. |
| Invalidation | None; the primitive owns no external storage. Copying/moving after initialization is outside the contract. |
| Ordering | Sticky (manual reset). `set` release-publishes the unset->set transition and calls `backend.wakeAll()` exactly once on the winning CAS; `clear` release-publishes the set->unset transition and never wakes. Lost-wakeup protection is via `Token.changedSince(observed)` from the backend. |
| Why not std.*? | `std.Io.Event` bundles waiting with the hosted `Io` futex/cancellation surface. `Signal.Manual(Backend)` exposes sticky notification without picking a wait implementation: spin, futex, kernel wait queue, and cooperative parkers all plug in as compile-time backends. |

#### `sync.spin.Backend`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Spin-only wait/wake backend | `sync.spin.Backend`, `wait`, `wakeAll`, `WaitError = error{}` | Zero-sized value (`@sizeOf == 0`) | Never | Canonical minimal wait/wake backend for every wait-capable primitive in `stdx.sync` and `stdx.concurrent`. `wait` emits one `std.atomic.spinLoopHint()` and returns without observing state; `wakeAll` is a no-op. `state` and `observed` are ignored by design. Safe from any execution context including NMI. | `std.Io` owns hosted wait/futex surfaces, but `std` has no compile-time plug-in backend seam shared across freestanding wait-capable primitives. `sync.spin.Backend` is the compose-in-place substitute for scheduler parking, futex, or IO backends. |

#### `sync.AtomicCell`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Typed atomic value | `AtomicCell(T)`, `init`, ordering-suffixed `load*`, `store*`, `swap*`, `cmpxchg{Weak,Strong}*` (8 variants), integer arithmetic `fetchAdd*/Sub*/And*/Or*/Xor*` (× 4 orderings), `fromStd`, `fromStdConst` | Layout-compatible with `std.atomic.Value(T)`; single field `raw: std.atomic.Value(T)` | Never | Ordering encoded per method suffix (`AcqRel`/`Acquire`/`Release`/`Monotonic`); success/failure ordering fixed at each method site; arithmetic ops instantiate only for integer `T`; supported `T`: signed/unsigned 8/16/32/64/usize/isize integers, `bool`, `enum`, pointer, `packed struct` with a supported backing integer. In-body comptime asserts pin `@sizeOf`/`@alignOf` against `std.atomic.Value(T)`. | `std.atomic.Value(T)` takes ordering as a runtime parameter; readers must audit every callsite to know the ordering. `AtomicCell(T)` moves ordering into the method name, so a review reads the ordering off the identifier and cannot pick the wrong ordering under refactoring. |

#### `sync.RawSpinLock`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Raw atomic-word spinlock | `RawSpinLock`, `State`, `init`, `acquire`, `tryAcquire`, `release`, `isHeld`, `assertHeld` | One `AtomicCell(u32)` word (state 0/1) | Never | Test-and-test-and-set acquisition: monotonic-load spin loop until `unlocked`, then `cmpxchgWeakAcquire`; `release` is `storeRelease(.unlocked)`. `assertHeld` traps under `debug.checksEnabled(.build_mode)`. No fairness, no priority-inheritance, no wait queue. | `std.Thread.Mutex` couples OS parking, priority inheritance, and pthread APIs. `RawSpinLock` is the freestanding-safe atomic-word substrate — usable from firmware, kernel init, and interrupt-disabled contexts where OS APIs are unavailable. |

#### `sync.Once`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| One-shot init primitive | `sync.once.State`, `sync.once.Token`, `Once(Backend)`, `Once.init`, `isDone`, `stateRef`, `call`, `callChecked` | One atomic `u32` word (2-bit state + 30-bit generation) plus backend value | Never | Runs `work(ctx)` at most once against a `State` word; losers wait on the backend and re-check via `Token.changedSince(observed)` for lost-wakeup safety. `callChecked` supports error-returning initializers via a rollback + retry cycle; rollback bumps generation and wakes waiters so they re-race the claim. Under `debug.checksEnabled(.build_mode)` a thread-local recursion tripwire catches direct self-recursion. Backend must satisfy the shared `sync.spin.Backend`-shaped `wait`/`wakeAll` contract. | `std.once.Once` is a hosted primitive that couples the OS parker and does not support fallible initialization or a plug-in wait backend. `Once(Backend)` is compose-first: pair with `sync.spin.Backend` for freestanding contexts or a scheduler-parking backend for hosted runtime. |

#### `sync.Rendezvous`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `Rendezvous(Backend).Static(N)` | One atomic `u64` word plus backend value | `init(backend)` | Comptime `N` parties; `Static(0)` and `Static(N > maxInt(u32))` are compile errors |
| `Rendezvous(Backend).Bounded` | One `u32` capacity plus one atomic `u64` word plus backend value | `init(capacity_parties, backend)` | Runtime `capacity_parties`; `0` traps under `debug.checksEnabled(.build_mode)` |

| Contract | Value |
| --- | --- |
| External allocation | Never. State is one atomic `u64` word; the backend value is stored inline. |
| Waiting | `arrive` blocks on the compile-time backend's `wait(&state, token)` for every party except the last; the last arriver never waits. |
| Concurrency | Any number of arrivers per generation; exactly one wins the last-arriver CAS. `State` observation is lock-free. Not safe from NMI or nested-interrupt context. |
| Performance | `arrive` performs one bounded CAS per contention retry and one backend `wait` per non-last arriver; the last arriver calls `backend.wakeAll(&state)` exactly once. `pending`, `capacity`, `generation`, and `stateRef` are O(1) acquire loads. |
| Errors | Backend-defined `WaitError`; propagated unchanged. `arrive` itself is otherwise infallible. |
| Mutation on error | The caller's arrival CAS has already committed when `backend.wait` fails; no rollback. |
| Invalidation | None; the primitive owns no external storage. Copying/moving after any pointer is shared is outside the contract. |
| Ordering | Reusable N-way barrier. The last arriver installs `remaining = capacity_parties` and `generation +% 1` in a single `.acq_rel` CAS, then calls `backend.wakeAll(&state)`. Non-last arrivers `.acquire`-observe the generation advance to synchronize-with the last arriver's release publication. Lost-wakeup protection is via `State.changedSince(token)` from the backend. |
| Why not std.*? | `std.Io.Group` is task-resource management tied to the hosted `Io` surface, and `std.Io.Event` is a boolean event; neither is a reusable N-way cyclic barrier. `Rendezvous(Backend)` exposes the cyclic-barrier contract without picking a wait implementation: spin, futex, kernel wait queue, and cooperative parkers all plug in as compile-time backends. |

### Concurrent

#### `concurrent.mpsc.Ring`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `mpsc.Ring.Static(T, N)` | Inline `[N]Slot` | `init(self)` | Comptime `N` items; non-zero power of two |
| `mpsc.Ring.Bounded(T)` | Caller-owned `[]Slot` | `init(self, slots)` | `slots.len` items; non-zero power of two |

| Contract | Value |
| --- | --- |
| External allocation | Never. Slots come from inline or caller-owned storage. |
| Waiting | Never. `tryPushBack` is one bounded attempt; `popFront` returns `null` when no front item is published. Pair with `sync.Signal` when a consumer needs to park. |
| Concurrency | Any number of producers via `tryPushBack`; exactly one consumer via `popFront`. |
| Performance | `tryPushBack` is one acquire load, one CAS, one release store on success; `popFront` and `isEmpty` are one monotonic load plus one acquire load. |
| Errors | `error.Full` when the head/tail gap reaches capacity; `error.Contended` when the reservation CAS is lost. Zero-sized `T` and non-power-of-two `Static` capacity are compile errors. |
| Mutation on error | Both `Full` and `Contended` leave the ring unchanged; the producer's `item` is never stored. |
| Invalidation | `popFront` release-frees its slot; producers reuse freed slots only after the consumer's release-store. |
| Ordering | FIFO across successful reservations. Producer payload write is release-published via the slot sequence; consumer reads are acquire-ordered. `tryPushBack` performs no internal retry — retry/backoff belong to the caller. |
| Why not std.*? | `std.Io.Queue(T)` requires the `Io` vtable and blocks producers on full. `mpsc.Ring` is bounded, allocation-free, non-blocking, and works without an `Io` implementation; producers report `error.Full`/`error.Contended` explicitly for caller-owned retry policy. |

#### `concurrent.spsc.Ring`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `spsc.Ring.Static(T, N)` | Inline `[N]Slot` | `init(self)` | Comptime `N` items; non-zero power of two |
| `spsc.Ring.Bounded(T)` | Caller-owned `[]Slot` | `init(self, slots)` | `slots.len` items; non-zero power of two |

| Contract | Value |
| --- | --- |
| External allocation | Never. Slots come from inline or caller-owned storage. |
| Waiting | Never. `tryPushBack` returns `error.Full` when full; `popFront` returns `null` when empty. Pair with `sync.Signal` when a consumer needs to park. |
| Concurrency | Exactly one producer, exactly one consumer. `head` and `tail` are `CachePad(std.atomic.Value(usize))` so producer/consumer writes hit disjoint cache lines. |
| Performance | `tryPushBack` and `popFront` each perform one monotonic load, one acquire load, and one release store on success. No CAS. |
| Errors | `error.Full` when the ring is full; zero-sized `T` and non-power-of-two `Static` capacity are compile errors. No `Contended` variant (single producer). |
| Mutation on error | `error.Full` leaves the ring unchanged. |
| Invalidation | Producer publishes via release-store of `tail`; consumer frees via release-store of `head`. |
| Ordering | FIFO. Producer's item write is release-published; consumer's read is acquire-ordered. |
| Why not std.*? | `std.Io.Queue(T)` requires the `Io` vtable and blocks producers on full. `spsc.Ring` is bounded, allocation-free, non-blocking, false-sharing-isolated, and works without an `Io` implementation. |

### Time

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| `Instant` | `fromNanos`, `nanos`, `zero`, `add`, `since`, `afterOrEq` | Value `enum(u64)` | Never | Monotonic nanoseconds over ~584 years; `add` returns `error.Overflow` on signed under/overflow of the `u64` domain; `since` is infallible within the primitive's `±292` year contract. | `std.Io.Timestamp` is tied to the hosted `Io` clock surface. `stdx.time.Instant` is a strong `enum(u64)` that carries no clock and is composable with any backend clock. |
| `Duration` | `fromNanos`, `nanos`, `fromMicros`, `fromMillis`, `fromSeconds`, `isPositive`, `isNegative` | Value `enum(i64)` | Never | Signed nanoseconds over `±292` years; `from{Micros,Millis,Seconds}` multiplication returns `error.Overflow`. | `std.time.ns_per_*` are `comptime` constants without a strong type. `stdx.time.Duration` is a strong `enum(i64)` and returns `error.Overflow` on unit-conversion overflow. |

#### `time.Clock.Monotonic`

| Family | APIs | Storage | Constructor |
| --- | --- | --- | --- |
| Monotonic clock wrapper | `Clock.Monotonic(Backend)`, `init`, `now`, optional `sleep` | Backend value | `init(backend)` |

| Contract | Value |
| --- | --- |
| External allocation | Never. |
| Waiting | `now` never waits. `sleep` is present iff `Backend` declares `sleep(*Backend, Duration) void`, and delegates to it verbatim; the wrapper adds no scheduler, cancellation, or wakeup-accuracy policy. |
| Concurrency | Single-owner mutable value; shared mutable access requires external synchronization. |
| Performance | `now` is one backend call plus a return in release; under `.build_mode` safety it also asserts monotonicity against a stored `Instant` witness. `sleep`, when present, is one backend call plus a return in release; under `.build_mode` safety it also asserts `delta.nanos() >= 0`. |
| Errors | Infallible. A `Backend.now` returning an error union, or a declared `Backend.sleep` with a mismatched signature, is a compile error. |
| Mutation on error | Not applicable. |
| Invalidation | None; the wrapper owns no external storage. |
| Ordering | Backend-defined monotonicity, asserted under `core.debug.checksEnabled(.build_mode)`. Release builds hold `@sizeOf(Backend)` exactly. |
| Why not std.*? | `std.Io.Clock` reaches clock operations through an `Io` vtable. `Clock.Monotonic(Backend)` composes any monotonic source (kernel TSC, HPET, PMU counter, virtual clock, test fake) behind one compile-time API, forwards a backend-provided `sleep` verbatim, and asserts monotonicity + non-negative delta in debug builds. |

#### `time.Deadline`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Monotonic deadline | `Deadline`, `Deadline.at`, `Deadline.now`, `Deadline.never`, `Deadline.instant`, `Deadline.isNever`, `Deadline.expired`, `Deadline.remaining`, `Deadline.expireBy` | Value `enum(u64)` | Never | Strong monotonic-instant anchor; `expired` uses `afterOrEq` (boundary is expired); `remaining` returns signed `Duration` with `Deadline.never` saturating at `Duration.fromNanos(maxInt(i64))`; `expireBy` returns `error.Timeout` on past-deadline. Clock parameter is duck-typed at compile time; error-union `now` is a compile error. | `std.Io.Timeout` ties deadlines to the hosted `Io` clock/cancellation surface. `Deadline` is a `u64`-word deadline anchor composable with any monotonic backend. |

#### `time.Backoff`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Retry-delay generator | `Backoff`, `Backoff.Policy`, `Backoff.Step`, `Backoff.init`, `Backoff.reset`, `Backoff.next`, `Backoff.attempts`, `Backoff.assertValid` | Value struct with `Policy`, `attempt`, `next_wait` | Never | Structured spin → yield → sleep phase machine with geometric growth capped at `max_wait` and per-step deadline clipping; `next` returns `.spin` / `.yield` / `.sleep(Duration)` / `.timeout`; the caller executes the wait, never the primitive. `Policy.yield == null` skips the yield phase entirely. | `std.time.sleep` is a bare host sleep with no phase progression, deadline, or yield hook. `Backoff` is deterministic-first, freestanding-safe, and composes with `Deadline` and any monotonic clock. |

#### `time.RateCounter`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Fixed-rate counter projection | `RateCounter`, `RateCounter.Config`, `RateCounter.Sample`, `init`, `reset`, `peek`, `sample`, `assertValid` | Value struct with `base: Instant`, `rate_hz: u64`, `width_bits: u7`, `last_wrap_count: u64` | Never | Projects an `Instant` reading into a fixed-rate integer counter of configurable bit width (`1..=64`), tracking wrap events across `sample` calls. `peek` is const and never touches the wrap-edge state; `sample` advances `last_wrap_count` and reports `wrapped = true` iff the unbounded tick count crossed a `1 << width_bits` boundary since the previous `sample`, `init`, or `reset`. Multi-wrap gaps coalesce to a single `wrapped = true`. Projection uses a `u128` intermediate for the full `Instant × rate_hz` domain; release builds clamp `now < base` to zero elapsed. Under `checksEnabled(.build_mode)` `init` runs `Config.assertValid` and `peek`/`sample` assert `now.afterOrEq(base)`. | `std` has no rate-projection primitive. `RateCounter` is the arithmetic shared by every emulated hardware counter driven by a monotonic reference (ACPI PM timer, HPET main counter): the caller owns any register storage, status bit, or interrupt delivery; the primitive owns only the projection formula and the wrap-edge detector. |

### Barriers

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Compiler barrier | `barrier.compiler` | None | Never | `pub inline fn () void`; empty inline asm with `memory` clobber; no ISA emission; compiles on every target. | Zig exposes `@fence(order)` for atomics but no bare compiler-only reordering barrier. `barrier.compiler` is the empty-asm memory-clobber pattern under one name. |
| MMIO fences | `barrier.mmio.release`, `barrier.mmio.acquire`, `barrier.mmio.releaseAcquire` | None | Never | `pub inline fn () void`; lowers to `sfence`/`lfence`/`mfence` on x86_64; non-x86_64 `@compileError`; not a cross-CPU synchronization primitive; does not flush caches. | `std` has no MMIO-vs-DMA fence primitives. These wrappers name the intent (release/acquire/releaseAcquire) and lower to the correct ISA fence per target, with `@compileError` on unsupported targets. |
| DMA fences | `barrier.dma.release`, `barrier.dma.acquire`, `barrier.dma.releaseAcquire` | None | Never | `pub inline fn () void`; lowers to `sfence`/`lfence`/`mfence` on x86_64; non-x86_64 `@compileError`; not a cache-maintenance primitive. | Same rationale as MMIO fences; kept as a separate API surface so future non-x86_64 targets (aarch64 `dsb oshst` variants) can lower `mmio` and `dma` fences differently. |

### IO

#### `io.Mmio.Register`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Register lane factory | `Mmio.Register(T)`, `load`, `store`, `Native`, `width_bytes` | `extern struct { value: T align(@alignOf(T)) }` | Never | Accepts `u8`/`u16`/`u32`/`u64`, `layout.Le`/`Be` over those widths, or `packed struct(uN)` where `N ∈ {8, 16, 32, 64}` and the backing integer is explicit; every other `T` is a compile error. `@sizeOf == @sizeOf(T)`; `@alignOf == @alignOf(T)`. Composes losslessly inside overlay `extern struct`s that model fixed device register blocks; a `packed struct(u32)` field type gives named-bit access with reserved-bit preservation across piecemeal updates. | `*volatile T` gives volatile access at the pointer type but no field-composition contract. `Mmio.Register(T)` is a factory that produces `extern struct` register lanes that compose into device register blocks and reject invalid `T`. |

`Register(T)` provides compiler ordering only via Zig's `*volatile T`
lowering. Hardware ordering against DMA payloads or other MMIO accesses is
the caller's job via `stdx.barrier.mmio` and `stdx.barrier.dma`.

#### `io.Mmio.Window`

| Family | APIs | Storage | Constructor |
| --- | --- | --- | --- |
| MMIO byte window factory | `Mmio.Window(min_align)`, `Mmio.Window32`, `Mmio.Window64`, `default_window_align`, `wrap`, `byteLen`, `register`, `field`, `registerUnchecked` | Caller-owned aligned byte range | `Window(N).wrap(bytes)` |

| Contract | Value |
| --- | --- |
| External allocation | Never. Borrows the caller's MMIO mapping. |
| Waiting | Never. |
| Concurrency | Value type; the caller manages shared access to the underlying mapping. |
| Performance | `wrap`, `register`, `field`, and `registerUnchecked` are O(1) pointer arithmetic. |
| Errors | `register` returns `error.OutOfBounds` (including on `usize`-overflowing `offset`) or `error.Misaligned`. `field` propagates the same errors after comptime-checking that the named field exists in the overlay `Layout` and fits inside `@sizeOf(Layout)`. `registerUnchecked` skips runtime checks and asserts under `debug.checksEnabled(.build_mode)`. |
| Mutation on error | Errors leave the window unchanged. |
| Invalidation | Returned register pointers are valid for the lifetime of the underlying MMIO mapping. |
| Ordering | Not applicable at the type level. Hardware ordering is caller-driven via `stdx.barrier.mmio` and `stdx.barrier.dma`. |
| Why not std.*? | `std` has no MMIO byte-window abstraction. `Mmio.Window(min_align)` is a factory parameterized on the required alignment: `Window64` for canonical 8-byte-aligned BARs, `Window32` for 4-byte-aligned legacy BARs, `Window(1)` for byte-granular MMIO. `Window.field(Layout, "cap")` produces a typed pointer to a named overlay field without hand-computing offsets. |

#### `io.poll.until`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Wait-for-value poll loop | `poll.until(clock, deadline, backoff, predicate)`, `poll.PollReturnType(Predicate)` | No storage; composes caller-supplied `Deadline`, `*Backoff`, and clock | Never | Composes `time.Deadline` + `time.Backoff` + a caller predicate returning `E!?T`. Runs predicate first each iteration; on `null` calls `Backoff.next` and dispatches `.spin` (`spinLoopHint`), `.yield` (`policy.yield.?()`), `.sleep` (`clock.sleep(d)`), or `.timeout` (returns `error.Timeout`). Predicate accepts a bare function type OR a struct/pointer exposing `call`. Return type is `(Deadline.TimeoutError \|\| PredicateError)!T`. Debug-mode assert catches null-yield hook. | `std` has no composable poll-with-deadline loop; `std.time.sleep`, `std.Thread.yield`, and `std.Io` are unrelated. `poll.until` is the algorithm shape for every device-init handshake, controller-ready check, and capability negotiation. |

### DMA

#### `dma.Buffer`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| DMA buffer | `Buffer(T)`, `init`, `initAligned`, `slice`, `constSlice`, `bytes`, `constBytes`, `len`, `byteLen`, `isEmpty`, `dmaAddr`, `dmaAddrAt`, `sub`, `assertValid` | Caller-owned `[]T` plus paired `DmaAddr` | Never | Pairs host `[]T` with device-visible `DmaAddr`; validates alignment and byte-length overflow at init; `byteLen()` returns the descriptor-facing `Address.Raw` width; sub-buffering inherits the caller's contiguity claim. | `std` has no DMA primitive. `Buffer(T)` is the atomic unit of DMA-visible memory: a host view plus its device-visible address, allocated and mapped entirely by the caller. |

#### `dma.ScatterGather`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Scatter-gather segment | `ScatterGather.Segment`, `init`, `fromBuffer`, `byteLen`, `isEmpty`, `endAddr`, `isAligned`, `assertValid` | Value `extern struct { addr, len_bytes }` | Never | Descriptor-facing 16-byte segment; `len_bytes` uses the DMA address raw width so descriptor emission never converts through `usize`. | `std` has no descriptor-facing segment type. `Segment` gives a strong descriptor value with alignment and end-address helpers. |
| Scatter-gather list | `ScatterGather.List.Static(N)`, `ScatterGather.List.Bounded` | Inline or caller-owned `[]Segment` | Never | Bounded segment list with `append`/`appendBuffer`/`at`/`totalByteLen`; total length returns the DMA address raw width. | `std` has no bounded segment list. `List.Static/Bounded` is a fixed-capacity segment vector for descriptor construction. |
| Scatter-gather builder | `ScatterGather.Builder.Static(N, alignment)`, `ScatterGather.Builder.Bounded(alignment)` | Wraps a `List` variant | Never | Enforces a comptime per-segment alignment for consumers whose protocol requires uniform segment alignment (e.g. 4 KiB pages). | `std` has no descriptor alignment enforcer. `Builder` is a thin wrapper that returns `error.Misaligned` before `error.Full` and hands back the underlying `List` on `finish`. |

### Function primitives

#### `func.Callback`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Signature-typed callback | `Callback(Fn)`, `Signature`, `Args`, `Return`, `Invoke`, `init`, `wrap`, `bind`, `bindMethod`, `call`, `eql` | `{ context: ?*anyopaque, invoke: *const Invoke }`; `@sizeOf == 2 * @sizeOf(usize)` | Never | Runtime-erased single-function callback specialized on a comptime `Fn` signature. `wrap(&free_fn)` produces a context-less callback; `bind(Ctx, &ctx, &fn_ptr)` and `bindMethod(Ctx, &ctx, "method")` carry the context pointer. Generic (`comptime` / `anytype`) parameters, variadics, and naked returns are compile errors at `Callback(Fn)` instantiation; signature-mismatched `bind`/`bindMethod` targets are compile errors at each factory call. `context` is a borrowed pointer with caller-owned lifetime. `call` performs one indirect call plus one context load; NOT a substitute for comptime-specialized dispatch on hot paths. | `std.io.AnyReader`/`AnyWriter` are hardcoded single-function erasures for two specific signatures. `std.mem.Allocator` and `std.Io` vtables cover multi-method dispatch. `Callback(Fn)` is the generic single-function erasure Zig itself lacks: one shape reusable across interrupt vector tables, completion hooks, timer callbacks, event listeners, and deferred cleanup queues. |

#### `func.Closure`

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Small-buffer closure | `Closure(Fn, capacity_bytes)`, `Signature`, `capacity`, `alignment`, `init`, `callback` | Inline `[capacity_bytes]u8 align(@alignOf(usize))` plus thunk pointer | Never | Constructs a `Callback(Fn)` that owns its captured state. `init(State, state, &fn_ptr)` bit-copies `state` into the inline storage; `@sizeOf(State) > capacity`, over-aligned `State`, or a signature-mismatched `fn_ptr` are compile errors. `callback()` returns a `Callback(Fn)` borrowing the closure's storage — the closure must sit at a stable address (heap slot, arena slot, static storage) for the returned callback to remain valid. Trivially copyable iff `State` is; moving or copying the closure invalidates any previously-returned `Callback`. | Zig has no small-buffer closure primitive. `std` covers "handler with borrowed state" via patterns like `Allocator`'s `{ptr, vtable}`, but nothing generalizes to "handler that owns its state inline". `Closure(Fn, N)` fills the gap for deferred actions, per-invocation timer state, and completion continuations without touching an allocator. |

## Documentation

| Document | Purpose |
| --- | --- |
| [`docs/specs/project/scope.md`](docs/specs/project/scope.md) | Project scope, naming policy, behavior-documentation rules. |
| [`docs/specs/root-exports.md`](docs/specs/root-exports.md) | Root facade and root promotion rules. |
| [`docs/specs/`](docs/specs/) | Normative per-primitive specs. |
| [`docs/project-decisions.md`](docs/project-decisions.md) | Approved project facts and status labels. |

A public module lands only with an approved owning spec.
