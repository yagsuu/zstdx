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
| `stdx.bits` | Power-of-two helpers, `BitSet` |
| `stdx.addr` | `Address`, `PhysAddr`, `VirtAddr`, `DmaAddr`, `Page`, page constants |
| `stdx.layout` | `EndianInt`, `Le`, `Be` |
| `stdx.bytes` | Unaligned access, checked offset access, `Cursor` |
| `stdx.mem` | Alignment helpers, `Arena`, `Pool`, `BitmapAllocator` |
| `stdx.collections` | `List`, `Ring` |
| `stdx.intrusive` | Intrusive `List`, `Queue`, `Stack` |
| `stdx.ranges` | `RangeSet`, `RangeMap` |
| `stdx.graph` | `Forest` |
| `stdx.algo` | Allocation placement algorithms, buddy arithmetic |
| `stdx.tags` | `Tag`, `TagAllocator` |
| `stdx.arch` | Target-gated instruction primitives |
| `stdx.diag` | Scoped diagnostics |
| `stdx.sync` | `Signal` |
| `stdx.concurrent` | `mpsc.Ring` |
| `stdx.time` | `Instant`, `Duration`, `Clock.Monotonic` |
| `stdx.barrier` | `compiler`, `mmio` fences, `dma` fences |
| `stdx.io` | `Mmio.Register`, `Mmio.Window` |
| `stdx.dma` | `Buffer`, `ScatterGather.Segment`/`List`/`Builder` |

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
| Callback traits | `Order`, `Compare`, `LessThan`, `Eql`, `Hash` | Function type factories | Never | `*const T` operands avoid required copies; laws are caller contracts. | `std.sort`/`std.HashMap` require ad-hoc closure or context types with no shared trait vocabulary; these factories give one shape reused across collections. |
| Ranges | `Range(T)` | Value struct | Never | Unsigned half-open `[start, end)` range; checked construction/arithmetic; O(1); no mutation outside returned values. | Zig has no `Range` type; `std` treats slices as ranges implicitly. `Range(T)` gives a strongly-typed half-open interval independent of any slice. |

### Bits

| Family | APIs / variants | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| Power-of-two helpers | `isPowerOfTwo`, `nextPowerOfTwo` | None | Never | Pure O(1) unsigned helpers; `isPowerOfTwo(0) == false`; `nextPowerOfTwo(0) == 1`; overflow is explicit. | `std.math.isPowerOfTwo` exists but does not fix `0`'s answer; `std.math.ceilPowerOfTwo*` families are split across signed/unsigned/assert variants. `stdx.bits` gives one contract per name. |
| `BitSet` | `BitSet.Static(N)` | Inline `u64` words | Never | Fixed index set over `0..N`; index ops O(1); scans/algebra O(word_count); mutator bounds errors leave state unchanged; mutators return the prior bit. | `std.bit_set.StaticBitSet` panics on out-of-bounds and its mutators return `void`; `BitSet.Static` returns `error.OutOfBounds` and the prior bit value so callers can branch on the transition. |

### Addresses and pages

| Family | APIs / variants | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| `Address` | `Address(Tag, Int)`, `PhysAddr`, `VirtAddr`, `DmaAddr` | Value enum | Never | Strong typed unsigned address values; checked arithmetic and alignment; tag identity prevents accidental domain mixing. | Zig has no newtype and `std` uses bare `usize`/`u64` for addresses; nothing prevents mixing physical, virtual, and DMA addresses. `Address(Tag, Int)` makes each domain a distinct type. |
| Page constants | `_4kib`, `_16kib`, `_64kib`, `_2mib`, `_1gib` | None | Never | Exact byte counts only; no platform support or policy implied. | `std.mem.page_size` is a single host page size at build time; page-tier constants for firmware, MMU, and DMA sizing have no home in `std`. |
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
| Ordering | Released slots are reused LIFO. |
| Why not std.*? | `std.heap.MemoryPool` is an allocator wrapper that grows. `Pool.Static/Bounded` is fixed-capacity, freestanding, and returns `error.OutOfMemory` deterministically at the caller-declared limit. |

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
| Why not std.*? | `std.ArrayList` allocates through an `Allocator` and grows. `List.Static/Bounded` refuses to grow: `error.Full` at capacity, no allocator dependency, works freestanding. |

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
| Why not std.*? | `std` has no bounded FIFO ring; `std.fifo.LinearFifo` uses an `Allocator` and copies on rebalance. `Ring.Static/Bounded` is fixed-capacity with explicit `Full` behavior. |

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
| Why not std.*? | `std.SinglyLinkedList`/`std.DoublyLinkedList` own the node storage. `intrusive.List` binds `field` inside a caller-declared struct so multiple lists can thread one object without extra allocation. |

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
| Why not std.*? | `std.fifo.LinearFifo` allocates and stores payload by value. `intrusive.Queue` requires zero allocations because caller objects carry the link fields. |

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
| Why not std.*? | `std` has no LIFO container that borrows caller storage. `intrusive.Stack` is the intrusive counterpart of `SinglyLinked`, in LIFO order. |

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
| CPU/query/control wrappers | `Cpuid`, `Msr`, `ControlRegister`, `Rflags`, `Interrupts`, `Cpu`, `Descriptor`, `Segment`, `Fence`, `Cache`, `Privilege` | Value wrappers or instruction effects | Never | Thin target-gated instruction primitives; no generic policy, field decoding, or descriptor layout ownership. | `std` has no CPUID, MSR, CR, RFLAGS, or descriptor-table wrappers. These are inline-asm-only wrappers matching Intel SDM instruction semantics with documented clobbers. |

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
| Why not std.*? | `std.Thread.ResetEvent` bundles OS parking and requires a hosted thread runtime. `Signal.Manual(Backend)` exposes the sticky notification without picking a wait implementation: spin, futex, kernel wait queue, and cooperative parkers all plug in as compile-time backends. |

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

### Time

| Family | APIs | Storage | External allocation | Contract highlights | Why not std.*? |
| --- | --- | --- | --- | --- | --- |
| `Instant` | `fromNanos`, `nanos`, `zero`, `add`, `since`, `afterOrEq` | Value `enum(u64)` | Never | Monotonic nanoseconds over ~584 years; `add` returns `error.Overflow` on signed under/overflow of the `u64` domain; `since` is infallible within the primitive's `±292` year contract. | `std.time.Instant` is host-clock aware and returns via OS calls. `stdx.time.Instant` is a strong `enum(u64)` that carries no clock and is composable with any backend clock. |
| `Duration` | `fromNanos`, `nanos`, `fromMicros`, `fromMillis`, `fromSeconds`, `isPositive`, `isNegative` | Value `enum(i64)` | Never | Signed nanoseconds over `±292` years; `from{Micros,Millis,Seconds}` multiplication returns `error.Overflow`. | `std.time.ns_per_*` are `comptime` constants without a strong type. `stdx.time.Duration` is a strong `enum(i64)` and returns `error.Overflow` on unit-conversion overflow. |

#### `time.Clock.Monotonic`

| Family | APIs | Storage | Constructor |
| --- | --- | --- | --- |
| Monotonic clock wrapper | `Clock.Monotonic(Backend)`, `init`, `now` | Backend value | `init(backend)` |

| Contract | Value |
| --- | --- |
| External allocation | Never. |
| Waiting | Never. `now` calls `Backend.now(*Backend) Instant` exactly once. |
| Concurrency | Single-owner mutable value; shared mutable access requires external synchronization. |
| Performance | `now` is one backend call plus a return in release; under `.build_mode` safety it also asserts monotonicity against a stored `Instant` witness. |
| Errors | Infallible. A `Backend.now` returning an error union is a compile error. |
| Mutation on error | Not applicable. |
| Invalidation | None; the wrapper owns no external storage. |
| Ordering | Backend-defined monotonicity, asserted under `core.debug.checksEnabled(.build_mode)`. Release builds hold `@sizeOf(Backend)` exactly. |
| Why not std.*? | `std.time.Timer` calls the host monotonic clock directly. `Clock.Monotonic(Backend)` composes any monotonic source (kernel TSC, HPET, PMU counter, virtual clock, test fake) behind one API and asserts monotonicity in debug builds. |

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
| Register lane factory | `Mmio.Register(T)`, `load`, `store`, `Native`, `width_bytes` | `extern struct { value: T align(@alignOf(T)) }` | Never | Accepts `u8`/`u16`/`u32`/`u64` or `layout.Le`/`Be` over those widths; every other `T` is a compile error. `@sizeOf == @sizeOf(T)`; `@alignOf == @alignOf(T)`. Composes losslessly inside overlay `extern struct`s that model fixed device register blocks. | `*volatile T` gives volatile access at the pointer type but no field-composition contract. `Mmio.Register(T)` is a factory that produces `extern struct` register lanes that compose into device register blocks and reject invalid `T`. |

`Register(T)` provides compiler ordering only via Zig's `*volatile T`
lowering. Hardware ordering against DMA payloads or other MMIO accesses is
the caller's job via `stdx.barrier.mmio` and `stdx.barrier.dma`.

#### `io.Mmio.Window`

| Family | APIs | Storage | Constructor |
| --- | --- | --- | --- |
| MMIO byte window | `Mmio.Window`, `wrap`, `register`, `registerUnchecked` | Caller-owned aligned byte range | `wrap(bytes)` |

| Contract | Value |
| --- | --- |
| External allocation | Never. Borrows the caller's MMIO mapping. |
| Waiting | Never. |
| Concurrency | Value type; the caller manages shared access to the underlying mapping. |
| Performance | `wrap`, `register`, and `registerUnchecked` are O(1) pointer arithmetic. |
| Errors | `register` returns `error.OutOfBounds` (including on `usize`-overflowing `offset`) or `error.Misaligned`. `registerUnchecked` skips runtime checks. |
| Mutation on error | Errors leave the window unchanged. |
| Invalidation | Returned register pointers are valid for the lifetime of the underlying MMIO mapping. |
| Ordering | Not applicable at the type level. Hardware ordering is caller-driven via `stdx.barrier.mmio` and `stdx.barrier.dma`. |
| Why not std.*? | `std` has no MMIO byte-window abstraction. `Mmio.Window` is a bounds- and alignment-checked view over a caller-owned aligned byte range, producing typed `Register(T)` pointers by offset. |

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

## Documentation

| Document | Purpose |
| --- | --- |
| [`docs/specs/project/scope.md`](docs/specs/project/scope.md) | Project scope, naming policy, behavior-documentation rules. |
| [`docs/specs/root-exports.md`](docs/specs/root-exports.md) | Root facade and root promotion rules. |
| [`docs/specs/`](docs/specs/) | Normative per-primitive specs. |
| [`docs/project-decisions.md`](docs/project-decisions.md) | Approved project facts and status labels. |

A public module lands only with an approved owning spec.
