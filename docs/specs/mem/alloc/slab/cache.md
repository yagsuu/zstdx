# Memory slab cache

Status: Approved.

`stdx.mem.alloc.SlabCache(T, RegionSource)` is a multi-region typed object cache. It
composes many `SlabAllocator.Bounded(T)` instances behind one class, growing by pulling
fixed-size aligned regions from a caller-supplied `RegionSource` on explicit
`refill` and returning fully-empty regions on explicit `drain`. Every object
handed out by `acquire` lives in exactly one region; `release` returns the
slot to that region's slab allocator without touching the region-source.

`SlabCache` never hides allocation. `acquire` never calls the `RegionSource`.
Growth is a caller decision expressed by `refill`.

## Owned scope

This spec owns:

- `mem.alloc.SlabCache(T, RegionSource)`;
- `SlabCache.PerCpu(cpu_count, local_capacity)`;
- the `RegionSource` interface contract (comptime-duck-typed);
- intrusive per-region metadata (`RegionHeader`) laid out inside each region;
- slab coloring during `refill`;
- empty / partial / full region-list membership;
- `acquire`, `release`, `refill`, `drain`, and `contains` semantics;
- exhaustion behavior when every region is full;
- pointer stability for outstanding acquisitions across `acquire`, `release`,
  `refill`, and other regions' `drain`;
- required tests.

This spec does not own:

- concrete region sources (page allocators, boot heaps, IOMMU-mapped
  regions, huge-page providers);
- CPU discovery, affinity, or interrupt policy;
- a general-purpose thread-safe `SlabCache`;
- destructors, release callbacks, or value finalizers;
- generation counters, stale-handle detection, or hazard-pointer schemes;
- iteration over live objects across regions;
- automatic zeroing or poisoning beyond the `SlabAllocator` debug-fill contract
  inherited from `docs/specs/mem/alloc/slab/allocator.md`;
- `std.mem.Allocator` views.

## Public namespace

`SlabCache` lives under `stdx.mem.alloc`:

```zig
stdx.mem.alloc.SlabCache
```

It is not root-promoted:

```zig
stdx.SlabCache // not exported
```

Source ownership:

```text
src/mem.zig
src/mem/alloc/slab/cache.zig
test/mem/alloc/slab/cache_test.zig
```

`src/mem/alloc/slab.zig` re-exports:

```zig
pub const cache = @import("slab/cache.zig");

pub const SlabCache = cache.SlabCache;
```

## `RegionSource` interface

`RegionSource` is a comptime-duck-typed interface. Any type used as
`RegionSource` MUST expose the following declarations, evaluated at
`SlabCache(T, RegionSource)` instantiation:

```zig
pub const region_bytes: usize;
pub const region_align: usize;
pub const Error: type;

pub fn acquire(self: *Self) Error!*align(region_align) [region_bytes]u8;
pub fn release(self: *Self, region: *align(region_align) [region_bytes]u8) void;
```

Requirements:

- `region_bytes > 0`;
- `region_align` is a non-zero power of two;
- `region_align >= region_bytes`, so masking an object address down to
  `region_align` recovers its region base;
- `region_align >= @alignOf(RegionHeader)` (the cache asserts this at
  compile time);
- `region_bytes >= @sizeOf(RegionHeader) + @sizeOf(SlabCache(T, ...).Slot)`
  (the cache asserts this at compile time; a region MUST fit at least the
  header and one slot);
- `Error` is a Zig error set;
- `acquire` returns a region whose full `region_bytes` byte window is
  writable for the region's lifetime with the cache;
- `release` returns exactly one region previously handed out by `acquire`;
  releasing a foreign pointer is a caller contract violation;
- neither method wakes threads, blocks, spins, or performs I/O within the
  cache's contract; source implementations that do so are outside the
  `SlabCache` spec.

The cache never inspects, retains, or forwards `RegionSource` state beyond
calling these two methods. The source pointer stored in the cache is used
only to dispatch `refill` and `drain`.

## Approved API

```zig
pub fn SlabCache(comptime T: type, comptime RegionSource: type) type;
```

`SlabCache.PerCpu(cpu_count, local_capacity)` returns a cache with
cache-line-padded local object caches and a synchronized global `SlabCache`.

Returned namespace:

```zig
pub const Self = struct {
    source: *RegionSource,
    empty_head: ?*RegionHeader = null,
    partial_head: ?*RegionHeader = null,
    full_head: ?*RegionHeader = null,
    region_count: usize = 0,
    live_count: usize = 0,

    pub const Slot = SlabAllocator.Bounded(T).Slot;

    pub const Error = error{ OutOfMemory };
    pub const RefillError = RegionSource.Error;

    pub const slots_per_region: usize = /* comptime derived */;

    pub fn init(source: *RegionSource) Self;

    pub fn len(self: *const Self) usize;
    pub fn regionCount(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;

    pub fn acquire(self: *Self) Error!*T;
    pub fn release(self: *Self, item: *T) void;

    pub fn refill(self: *Self) RefillError!void;
    pub fn drain(self: *Self) void;

    pub fn contains(self: *const Self, item: *const T) bool;

    pub fn isValid(self: *const Self) bool;
    pub fn assertValid(self: *const Self) void;

    pub fn PerCpu(comptime cpu_count: usize, comptime local_capacity: usize) type;
};
```

`T` MUST be a runtime value type with `@sizeOf(T) > 0`.

`RegionSource` MUST satisfy the interface contract above. Violations are
compile errors with messages that name the missing or invalid declaration.

`RegionHeader` is a private implementation detail. Callers MUST NOT rely
on its exact layout beyond what this spec requires.

## Region layout

Every region acquired from the source begins with a `RegionHeader` at
offset zero. The cache computes an aligned base slot offset after the
header.

`color_stride` is `max(std.atomic.cache_line, @alignOf(Slot))`. If a
region can hold at least one slot at both the base offset and at
`base offset + color_stride`, the cache uses two colors. Otherwise, the
cache uses one color. `refill` alternates the selected color.

`slots_per_region` is computed for the largest selected offset. Thus,
every region has identical capacity even when it has a different color.

`slots_per_region >= 1` is required at compile time. When this condition
fails, `SlabCache(T, RegionSource)` is a compile error with a message
naming `region_bytes`, `region_align`, and the resulting layout.

`RegionHeader` contains:

- `prev` and `next` links for the empty, partial, and full lists;
- a list identifier;
- a `SlabAllocator.Bounded(T)` instance whose `buffer` field points into the
  colored in-region slot array;
- `region: *align(region_align) [region_bytes]u8`, used by `drain`;
- `slot_offset`, the byte offset from `region` to the slot array.

The cache uses `region_align` to recover a candidate `RegionHeader` from
an object pointer. The source alignment requirement makes this operation
valid for every colored slot.

## Region membership lists

Every region held by the cache appears on exactly one of three intrusive
doubly-linked lists:

- **empty**: `RegionHeader.inner.len() == 0`;
- **partial**: `0 < RegionHeader.inner.len() < slots_per_region`;
- **full**: `RegionHeader.inner.len() == slots_per_region`.

Every mutating operation preserves this partition. Transitions are:

| Trigger | From | To |
| --- | --- | --- |
| `acquire` moves a region from empty | empty | partial (or full if `slots_per_region == 1`) |
| `acquire` fills the region's last slot | partial | full |
| `release` frees a slot from a full region | full | partial |
| `release` frees the region's last live slot | partial | empty |
| `refill` adds a fresh region | (none) | empty |
| `drain` returns an empty region | empty | (none) |

Implementations MAY choose any deterministic list order (LIFO or FIFO)
per list. The spec does not fix an order and tests SHOULD NOT depend on
one.

## `init(source)` semantics

`init(source)` returns a cache with zero regions and zero live items:

```zig
Self{
    .source = source,
    .empty_head = null,
    .partial_head = null,
    .full_head = null,
    .region_count = 0,
    .live_count = 0,
}
```

`init` never calls `source.acquire`. A freshly-initialized cache is empty
and its next `acquire` returns `error.OutOfMemory`.

## `refill()` semantics

`refill()` acquires exactly one region from the source and installs it on
the empty list.

Logic:

1. Call `source.acquire()`. Propagate its error unchanged. Cache state
   is not modified when `source.acquire` returns an error.
2. Cast the returned region pointer's first `@sizeOf(RegionHeader)` bytes
   as a `*RegionHeader`.
3. Select the next slot-start color.
4. Initialize the header. Initialize the inner `SlabAllocator.Bounded(T)`
   over the colored slot array with `SlabAllocator.Bounded(T).wrap`.
   Store `region` and `slot_offset`.
5. Link the header at the empty-list head.
6. Increment `region_count`.

`refill` propagates the exact error returned by `source.acquire` under
`RefillError = RegionSource.Error`. Cache-side exhaustion is reported by
`acquire`, not by `refill`.

## `drain()` semantics

`drain()` returns every region on the empty list to the source.

Logic:

1. For each `RegionHeader` on the empty list:
   - unlink the header from the empty list;
   - call `source.release(header.region)`;
   - decrement `region_count`.
2. Regions on the partial or full list are not touched.

`drain` never fails and never allocates.

`drain` MUST NOT reorder regions on the partial or full lists.

## `acquire()` semantics

`acquire()` allocates one `*T` from any region that has free slots.

Logic:

1. If the partial list is non-empty, choose its head region and call
   `header.inner.acquire()`. On success, if the region is now full,
   move it from the partial list to the full list. Increment
   `live_count`. Return the pointer.
2. Otherwise, if the empty list is non-empty, choose its head region,
   move it from the empty list to the partial list (or full list if
   `slots_per_region == 1`), and call `header.inner.acquire()`.
   Increment `live_count`. Return the pointer.
3. Otherwise, return `error.OutOfMemory` and leave the cache
   unchanged. The caller decides whether to call `refill()` next.

`acquire` never calls `source.acquire`. It never walks the full list.

The returned `*T` satisfies `@alignOf(T)` and points at uninitialized
storage (subject to `SlabAllocator`'s debug-fill contract on Debug/ReleaseSafe).

## `release(item)` semantics

`release(item)` returns `item` to its owning region's slab allocator.

Logic:

1. Mask `@intFromPtr(item)` down to `region_align` to recover the region
   base, then recover the `RegionHeader`.
2. Under `stdx.core.debug.checksEnabled(.build_mode)`, assert that the
   header belongs to this cache.
3. Call `header.inner.release(item)`.
4. Decrement `live_count`.
5. Move the region when its occupancy changes.

`release` never calls `source.release`. Regions that reach the empty
list stay in the cache until `drain()` is called explicitly.

`release` is O(1) amortized. It does not walk any list.

## `contains(item)` semantics

`contains(item)` returns `true` iff `item` points into a region currently
owned by this cache.

Logic:

1. Mask `@intFromPtr(item)` down to `region_align` to obtain a candidate
   region base.
2. Walk the empty, partial, and full lists and return `true` when a
   header address matches the candidate base.
3. Return `false` otherwise.

`contains` walks up to `region_count` headers and is O(region_count).
It never calls the source and never mutates cache state.

`contains` is provided for downstream dispatch layers that own multiple
caches and need to route a `*T` back to the correct one. Callers that
already know the owning cache never need it.

## `capacity`, `len`, `remaining`, `regionCount`, `isEmpty`

`capacity()` returns `region_count * slots_per_region`. It does not walk
any list.

`len()` returns `live_count`.

`remaining()` returns `capacity() - len()`.

`regionCount()` returns `region_count`.

`isEmpty()` returns `live_count == 0`.

There is no `isFull()`. A cache with every held region full is not
"full" in the usual sense — the caller can grow it with `refill()`.
Callers that need to detect the acquire-must-refill boundary observe
`remaining() == 0` or handle `acquire`'s `error.OutOfMemory` directly.

None of these operations walks a list or calls the source.

## `PerCpu(cpu_count, local_capacity)` semantics

`PerCpu` owns one global `SlabCache` and `cpu_count` cache-line-padded
local object caches. `cpu_count` and `local_capacity` must be non-zero at
compile time.

The caller supplies `cpu_index` to `acquire` and `release`. The caller
MUST route each index to one concurrent executor. The type does not
discover CPUs or enforce affinity.

`acquire(cpu_index)` pops from the local cache first. When the local cache
is empty, it acquires the global spin lock, obtains one object for the
caller, and reserves additional objects for the local cache. It never
calls the region source.

`release(cpu_index, item)` pushes to the local cache. When the local cache
is full, it acquires the global spin lock and flushes the local objects to
the global cache before it pushes `item`.

`refill()` acquires the global spin lock and delegates to the global cache.
`drain()` acquires the global spin lock, flushes all local caches, then
delegates to the global cache. The caller MUST quiesce local CPU operations
before it calls `drain()`.

`PerCpu.len()` excludes objects reserved by local caches. `capacity()`,
`regionCount()`, `remaining()`, and `isEmpty()` use this external-object
view. `len()`, `remaining()`, and `isEmpty()` are O(`cpu_count`).

## Base cache behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `init` | none | never | O(1) | none | caller-owned value | none |
| `capacity`/`len`/`remaining`/`regionCount`/`isEmpty` | none | never | O(1) | none | caller-owned value | none |
| `acquire` | none | never | O(1) amortized | none | caller-owned value | pops slot; may move region |
| `release` | none | never | O(1) amortized | released pointer | caller-owned value | pushes slot; may move region |
| `refill` | region-source | source-defined | O(1) + source | none | caller-owned value | appends to empty list |
| `drain` | none | never | O(empty list) | pointers into drained regions | caller-owned value | releases every empty region |
| `contains` | none | never | O(region_count) | none | caller-owned value | none |
| `assertValid`/`isValid` | none | never | O(regions + slots) | none | caller-owned value | walks lists |

These operations perform no heap allocation, no hidden global access,
no atomics, no barriers, no volatile access, no target probing, no
syscalls, no locks, and no I/O beyond what `RegionSource` may perform
inside `refill`.

Concurrent mutation is outside the contract. Callers MUST externally
synchronize shared mutable access to the cache and to the underlying
`RegionSource`.

## Pointer stability

Acquired pointers remain valid until any of:

- the matching `release(item)` call;
- `drain()` when the owning region has become fully empty (a `release`
  that empties the region followed by `drain` MAY reclaim the region
  and invalidate every pointer that used to point into it — but by that
  point every such pointer has already been released, so no live
  pointer is affected);
- destruction or move of the cache value (programmer error);
- destruction or move of the `RegionSource` (programmer error).

`acquire` / `release` of other items and `refill` do not invalidate
outstanding acquisitions.

## Error behavior

- `acquire` returns `error.OutOfMemory` when every region is full. State
  unchanged.
- `refill` propagates `RegionSource.Error` on source failure. Cache
  state unchanged.
- `release`, `drain`, and `contains` do not return errors; misuse is a
  programmer error caught by `assertValid` where practical.
- zero-sized `T` is a compile error.
- `slots_per_region == 0` is a compile error at
  `SlabCache(T, RegionSource)` instantiation.

All error returns leave the cache unchanged.

## Debug assertion behavior

`assertValid()` walks the empty, partial, and full lists and checks:

- each list's regions have the expected `header.inner.len()` class;
- `prev` and `next` links are mutually consistent;
- `region_count` equals the sum of the three list lengths;
- `live_count` equals the sum of `header.inner.len()` across every
  region;
- every region's inner `SlabAllocator.Bounded(T)` passes its own `isValid`;
- each header equals the base address of `header.region`;
- each `slot_offset` and inner slot buffer is valid for the selected color.

`assertValid()` is O(region_count + region_count * slots_per_region) and
is called explicitly. Operations do not call it unconditionally on hot
paths.

`isValid()` returns whether the same conditions hold, without
asserting.

## Implementation constraints

Implementation MUST:

- store the region-list metadata inside `RegionHeader` at region offset
  zero (no external metadata array);
- initialize each region's inner `SlabAllocator.Bounded(T)` via
  `SlabAllocator.Bounded(T).wrap` — do NOT reimplement the SlabAllocator bookkeeping
  inside the cache;
- respect the SlabAllocator debug-fill contract by delegating `acquire`/`release`
  to the inner slab allocator;
- never call `RegionSource.acquire` from `acquire`;
- never call `RegionSource.release` from `release`;
- perform O(1) list moves on transitions between empty / partial / full
  with intrusive `prev` and `next` links in `RegionHeader`;
- reject `T` and `RegionSource` violations at comptime with clear
  messages;
- compile for freestanding targets;
- avoid heap fallback and hidden globals.

## Usage

Typical shape — one cache per class, one region-source shared across
classes:

```zig
const stdx = @import("stdx");

const Cmd = struct { id: u32, opcode: u32, payload: [16]u8 };

const CmdCache = stdx.mem.alloc.SlabCache(Cmd, PageFrameSource);

var cache = CmdCache.init(&page_source);

// Grow when needed.
if (cache.remaining() == 0) try cache.refill();

const cmd = try cache.acquire();
cmd.* = .{ .id = 1, .opcode = 0x12, .payload = undefined };

// … use cmd …

cache.release(cmd);

// Return empty regions to the source when the working set shrinks.
cache.drain();
```

Composing over `FrameAllocator.FrameSource` (documented in
`docs/specs/mem/alloc/frame.md`):

```zig
const Phys4K = stdx.addr.Page(stdx.addr.PhysAddr, stdx.addr.pages._4kib);
const FrameAlloc = stdx.mem.alloc.FrameAllocator.Static(
    stdx.mem.alloc.BuddyAllocator.Static(1024, 6),
    Phys4K,
    try Phys4K.Frame.fromAddressInt(0x0010_0000),
);

var frames = FrameAlloc.init();
var source = frames.frameSource(0);            // one 4 KiB region per acquire

const NodeCache = stdx.mem.alloc.SlabCache(Node, @TypeOf(source));
var cache = NodeCache.init(&source);
```

## Planned use

- kernel typed-object allocation with page-backed growth (analog to
  `kmem_cache_alloc`);
- hypervisor typed pools whose backing region set grows and shrinks
  across guest lifetimes;
- firmware pre-runtime typed pools over caller-supplied physical
  regions;
- freestanding drivers that dispatch (size-class → cache) by pointer
  ownership.

## Required tests

Tests live in `test/mem/alloc/slab/cache_test.zig`. A mock region source with
recorded `acquire` / `release` counts backs every test unless a variant
under test names its concrete source.

### Construction

- `init(&source)` reports `len == 0`, `regionCount == 0`, `capacity == 0`,
  and never calls `source.acquire`;
- freshly-initialized cache returns `error.OutOfMemory` from `acquire`.

### Refill

- `refill` calls `source.acquire` exactly once and increments
  `regionCount` by one;
- `refill` propagating `source.acquire`'s error leaves the cache
  unchanged (`regionCount`, `live_count`, all three list heads
  identical to pre-call snapshot).

### Slab coloring

- consecutive `refill` calls use distinct slot offsets when
  `color_count == 2`;
- each colored region has `slots_per_region` slots;
- the empty-list `prev` and `next` links remain consistent after refill.

### Acquire and release

- `acquire` after `refill` succeeds and returns a pointer inside the
  newly-acquired region (`contains(ptr) == true`);
- LIFO within a single region: the most recently released slot is the
  next slot returned by `acquire` on that region;
- `release` returns the slot to the free list and moves the region from
  full → partial when applicable;
- `release` on the region's last live slot moves the region to the
  empty list;
- `acquire` never calls `source.acquire`;
- `release` never calls `source.release`.

### Per-CPU cache

- a local release is returned by a later acquire on the same CPU index;
- `len` excludes local cached objects;
- `drain` flushes local objects and releases empty regions;
- `assertValid` succeeds with objects in local caches.

### Exhaustion

- after every region is full, `acquire` returns `error.OutOfMemory`
  without calling the source and without mutating state;
- a subsequent `refill` + `acquire` sequence succeeds.

### Drain

- `drain` on a cache with only empty regions releases each region back
  to the source exactly once and clears `regionCount`;
- `drain` with mixed empty / partial regions releases only the empty
  regions and leaves the partial ones untouched.

### Pointer stability

- outstanding acquisitions remain valid across other slots'
  `acquire` / `release`;
- outstanding acquisitions remain valid across `refill`.

### Contains

- `contains(item)` returns `true` for every currently-live pointer;
- `contains` returns `false` for a pointer released from the cache
  after that region has been drained;
- `contains` returns `false` for a pointer that never came from this
  cache.

### Invariants

- `assertValid` succeeds after every legal sequence of `acquire`,
  `release`, `refill`, `drain`;
- `isValid` returns the same boolean as `assertValid`'s condition;
- corrupted `region_count` (test-only backdoor) fails `isValid`.

### Model test

Reference: `std.ArrayList(?T)` oracle sized to the cache's current
capacity. Reference operations mirror `acquire` / `release`; `refill`
and `drain` grow and shrink the oracle by `slots_per_region`.

- 2 000 random operations over a `SlabCache(u64, MockSource)` with
  `region_bytes = 512` and `region_align = 512`;
- the model checks pointer validity, `contains` correctness, list
  membership invariants after every op;
- at the end of the sequence, a final `drain` returns the cache to
  zero regions and the mock source's `acquire`/`release` counts
  balance.

### Comptime rejections

- zero-sized `T` fails to instantiate;
- a `RegionSource` missing `region_bytes` fails to instantiate;
- a `RegionSource` missing `acquire` fails to instantiate;
- a `RegionSource` whose `region_align < region_bytes` fails to
  instantiate;
- a `RegionSource` whose `region_bytes` cannot fit at least one header
  plus one colored slot fails to instantiate.

### Debug fill inheritance

- `SlabCache`'s acquired pointers are subject to the same
  `0xCD` / `0xFD` fill discipline as `SlabAllocator` under
  `checksEnabled(.build_mode) == true` — the test relies on the
  underlying `SlabAllocator.Bounded(T)` inside each region enforcing it.

## Open questions

None.
