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

## Public surface

| Namespace | Families |
| --- | --- |
| `stdx.core` | `SafetyMode`, debug checks, callback traits, `Range(T)` |
| `stdx.bits` | Power-of-two helpers, `BitSet` |
| `stdx.addr` | `Address`, `PhysAddr`, `VirtAddr`, `Page`, page constants |
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
| `stdx.concurrent` | `MpscRing` |

| Root export | Canonical home | Notes |
| --- | --- | --- |
| `stdx.List` | `stdx.collections.List` | Root-promoted family: `Static`, `Bounded`. |
| `stdx.Ring` | `stdx.collections.Ring` | Root-promoted family: `Static`, `Bounded`. |

Stateless functions and domain-specific strong types stay namespaced. Examples:
`stdx.mem.alignUp`, `stdx.bytes.loadUnaligned`, `stdx.addr.PhysAddr`.

## Implemented primitive families

### Core

| Family | APIs | Storage | External allocation | Contract highlights |
| --- | --- | --- | --- | --- |
| Safety options | `SafetyMode` | Value enum | Never | `build_mode`, `checked`, `unchecked`; controls optional zstdx checks only. |
| Debug checks | `debug.checksEnabled(mode)` | None | Never | Comptime predicate; explicit `assertValid` calls always check. |
| Callback traits | `Order`, `Compare`, `LessThan`, `Eql`, `Hash` | Function type factories | Never | `*const T` operands avoid required copies; laws are caller contracts. |
| Ranges | `Range(T)` | Value struct | Never | Unsigned half-open `[start, end)` range; checked construction/arithmetic; O(1); no mutation outside returned values. |

### Bits

| Family | APIs / variants | Storage | External allocation | Contract highlights |
| --- | --- | --- | --- | --- |
| Power-of-two helpers | `isPowerOfTwo`, `nextPowerOfTwo` | None | Never | Pure O(1) unsigned helpers; `isPowerOfTwo(0) == false`; `nextPowerOfTwo(0) == 1`; overflow is explicit. |
| `BitSet` | `BitSet.Static(N)` | Inline `u64` words | Never | Fixed index set over `0..N`; index ops O(1); scans/algebra O(word_count); mutator bounds errors leave state unchanged. |

### Addresses and pages

| Family | APIs / variants | Storage | External allocation | Contract highlights |
| --- | --- | --- | --- | --- |
| `Address` | `Address(Tag, Int)`, `PhysAddr`, `VirtAddr` | Value enum | Never | Strong typed unsigned address values; checked arithmetic and alignment; tag identity prevents accidental domain mixing. |
| Page constants | `_4kib`, `_16kib`, `_64kib`, `_2mib`, `_1gib` | None | Never | Exact byte counts only; no platform support or policy implied. |
| `Page` | `Page(Addr, page_size)` | Value types under returned namespace | Never | `Size`, `Count`, `Frame`, `FrameRange`; checked byte/page conversion, frame arithmetic, containment, overlap, span, and split. |

### Layout

| Family | APIs / variants | Storage | External allocation | Contract highlights |
| --- | --- | --- | --- | --- |
| `EndianInt` | `EndianInt(T, endian)`, `Le(T)`, `Be(T)` | Value `extern struct` with byte array | Never | Alignment 1; size from bit width; unsigned byte-aligned integer lanes; target-endian independent conversion. |

### Bytes

| Family | APIs / variants | Storage | External allocation | Contract highlights |
| --- | --- | --- | --- | --- |
| Unaligned access | `loadUnaligned`, `storeUnaligned` | Caller byte window | Never | Byte-copy fixed-window typed access; no bounds check, endian conversion, validation, volatile access, or pointer reinterpretation. |
| Checked offset access | `load`, `store`, `loadSlice`, `storeSlice`, `loadTail` | Caller byte slice | Never | Bounds-checked random access; `error.EndOfStream` for overrun or offset overflow; failed stores do not partially write. |
| `Cursor` | `Cursor` | Borrowed `[]const u8` plus index | Never | Forward read cursor; checked peek/read/skip; typed reads compose unaligned access; value-copy checkpointing. |

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

#### Memory alignment helpers

| Family | APIs | Storage | External allocation | Contract highlights |
| --- | --- | --- | --- | --- |
| Alignment helpers | `alignUp`, `alignDown`, `isAligned`, `alignUpDelta`, `alignDownDelta` | None | Never | Pure O(1) unsigned helpers; invalid alignment is explicit where fallible; rounding overflow is explicit. |

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

### Algorithms

| Family | APIs | Storage | External allocation | Contract highlights |
| --- | --- | --- | --- | --- |
| Allocation placement | `Request`, `Selection`, `FirstFit`, `BestFit`, `WorstFit` | Caller-provided free-range slice | Never | Pure selection over sorted non-overlapping ranges; does not mutate input; explicit invalid request/alignment/overflow errors. |
| Buddy arithmetic | `Buddy` | Value inputs/outputs | Never | Pure block/order arithmetic; no allocator storage or mutation. |

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

#### `tags.Tag`

| Family | APIs | Storage | External allocation | Contract highlights |
| --- | --- | --- | --- | --- |
| Strong tag | `Tag(Domain, Int)` | Value enum | Never | Domain identity is type-level; raw conversion is explicit. |

### Target-specific

| Family | APIs | Storage | External allocation | Contract highlights |
| --- | --- | --- | --- | --- |
| Target gate | `arch.x86_64.supported` | Value constant | Never | Import is portable; instruction-emitting operations are gated to the matching target. |
| Port I/O | `arch.x86_64.Port`, `ioWait` | Value enum plus instruction effects | Never | Strong `u16` port values; scalar and slice `in*`/`out*` operations. |
| CPU/query/control wrappers | `Cpuid`, `Msr`, `ControlRegister`, `Rflags`, `Interrupts`, `Cpu`, `Descriptor`, `Segment`, `Fence`, `Cache`, `Privilege` | Value wrappers or instruction effects | Never | Thin target-gated instruction primitives; no generic policy, field decoding, or descriptor layout ownership. |

### Diagnostics

#### `diag.Diagnostics`

| Family | APIs | Storage | Constructor |
| --- | --- | --- | --- |
| Scoped diagnostics | `Diagnostics`, `ScopeOptions`, `Scope`, `LazyDetail`, `lazy` | Private arena plus retained frame forest | `Diagnostics.init(gpa)` |

| Contract | Value |
| --- | --- |
| External allocation | Yes. Uses the allocator passed to `Diagnostics.init(gpa)` for retained frames, labels, details, and lazy captures. Allocation failure degrades to no-op diagnostics. |
| Waiting | Follows supplied allocator behavior; diagnostics itself performs no blocking operation beyond allocator calls. |
| Concurrency | Single-owner mutable diagnostics value; shared mutable access requires external synchronization. |
| Performance | Scope open/detail may allocate; successful scopes discard; formatting walks retained frames in DFS order. |
| Errors | Diagnostic operations are infallible; diagnostic allocation failure does not replace the originating error. |
| Mutation on error | Diagnostics never masks the original failure with diagnostic allocation failure. |
| Invalidation | `deinit()` invalidates retained frames, labels, details, and lazy captures. |
| Ordering | Retained frames render in deterministic DFS pre-order. |

### Synchronization

#### `sync.Signal`

| Family | APIs | Storage | Constructor |
| --- | --- | --- | --- |
| Manual-reset signal | `Signal.State`, `Signal.Token`, `Signal.Manual(Backend)` | One atomic `usize` word plus backend value | `Signal.State.init(initial)`; `Signal.Manual(Backend).init(self, initial, backend)` |

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

### Concurrent

#### `concurrent.MpscRing`

| Variant | Storage | Constructor | Capacity |
| --- | --- | --- | --- |
| `MpscRing.Static(T, N)` | Inline `[N]Slot` | `init(self)` | Comptime `N` items; non-zero power of two |
| `MpscRing.Bounded(T)` | Caller-owned `[]Slot` | `init(self, slots)` | `slots.len` items; non-zero power of two |

| Contract | Value |
| --- | --- |
| External allocation | Never. Slots come from inline or caller-owned storage. |
| Waiting | Never. `tryPushBack` is one bounded attempt; `popFront` returns `null` when no front item is published. Pair with `sync.Signal` when a consumer needs to park. |
| Concurrency | Any number of producers via `tryPushBack`; exactly one consumer via `popFront`. |
| Performance | `tryPushBack` is one acquire load, one CAS, one release store on success; `popFront` and `isEmpty` are one monotonic load plus one acquire load. |
| Errors | `error.Full` when `tail - head >= capacity`; `error.Contended` when the tail-reservation CAS is lost. Zero-sized `T` and non-power-of-two `Static` capacity are compile errors. |
| Mutation on error | Both `Full` and `Contended` leave the ring unchanged; the producer's `item` is never stored. |
| Invalidation | `popFront` release-frees its slot; producers reuse freed slots only after the consumer's release-store. |
| Ordering | FIFO across successful reservations. Producer payload write is release-published via the slot sequence; consumer reads are acquire-ordered. `tryPushBack` performs no internal retry — retry/backoff belong to the caller. |

## Documentation

| Document | Purpose |
| --- | --- |
| [`docs/specs/project/scope.md`](docs/specs/project/scope.md) | Project scope, naming policy, behavior-documentation rules. |
| [`docs/specs/root-exports.md`](docs/specs/root-exports.md) | Root facade and root promotion rules. |
| [`docs/specs/`](docs/specs/) | Normative per-primitive specs. |
| [`docs/project-decisions.md`](docs/project-decisions.md) | Approved project facts and status labels. |

A public module lands only with an approved owning spec.
