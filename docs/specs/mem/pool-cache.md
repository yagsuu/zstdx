# Memory pool cache

Status: Approved.

`stdx.mem.PoolCache(T, RegionSource)` is a multi-region typed object cache. It
composes many `Pool.Bounded(T)` instances behind one class, growing by pulling
fixed-size aligned regions from a caller-supplied `RegionSource` on explicit
`refill` and returning fully-empty regions on explicit `drain`. Every object
handed out by `acquire` lives in exactly one region; `release` returns the
slot to that region's pool without touching the region-source.

`PoolCache` never hides allocation. `acquire` never calls the `RegionSource`.
Growth is a caller decision expressed by `refill`.

## Owned scope

This spec owns:

- `mem.PoolCache(T, RegionSource)`;
- the `RegionSource` interface contract (comptime-duck-typed);
- intrusive per-region metadata (`RegionHeader`) laid out inside each region;
- the empty / partial / full three-list membership discipline;
- `acquire`, `release`, `refill`, `drain`, and `contains` semantics;
- exhaustion behavior when every region is full;
- pointer stability for outstanding acquisitions across `acquire`, `release`,
  `refill`, and other regions' `drain`;
- required tests.

This spec does not own:

- concrete region sources (page allocators, boot heaps, IOMMU-mapped
  regions, huge-page providers);
- per-CPU sharding or a `PoolCache.PerCpu` sibling;
- reclamation ordering across regions;
- destructors, release callbacks, or value finalizers;
- generation counters, stale-handle detection, or hazard-pointer schemes;
- thread-safe caches;
- iteration over live objects across regions;
- automatic zeroing or poisoning beyond the `Pool` debug-fill contract
  inherited from `docs/specs/mem/pool.md`;
- `std.mem.Allocator` views.

## Public namespace

`PoolCache` lives under `stdx.mem`:

```zig
stdx.mem.PoolCache
```

It is not root-promoted:

```zig
stdx.PoolCache // not exported
```

Source ownership:

```text
src/mem.zig
src/mem/pool_cache.zig
test/mem/pool_cache_test.zig
```

`src/mem.zig` re-exports:

```zig
pub const pool_cache = @import("mem/pool_cache.zig");

pub const PoolCache = pool_cache.PoolCache;
```

## `RegionSource` interface

`RegionSource` is a comptime-duck-typed interface. Any type used as
`RegionSource` MUST expose the following declarations, evaluated at
`PoolCache(T, RegionSource)` instantiation:

```zig
pub const region_bytes: usize;
pub const region_align: usize;
pub const Error: type;

pub fn acquire(self: *Self) Error!*align(region_align) [region_bytes]u8;
pub fn release(self: *Self, region: *align(region_align) [region_bytes]u8) void;
```

Requirements:

- `region_bytes > 0` and a multiple of `region_align`;
- `region_align` is a non-zero power of two;
- `region_align >= @alignOf(RegionHeader)` (the cache asserts this at
  compile time);
- `region_bytes >= @sizeOf(RegionHeader) + @sizeOf(PoolCache(T, ...).Slot)`
  (the cache asserts this at compile time; a region MUST fit at least the
  header and one slot);
- `Error` is a Zig error set;
- `acquire` returns a region whose full `region_bytes` byte window is
  writable for the region's lifetime with the cache;
- `release` returns exactly one region previously handed out by `acquire`;
  releasing a foreign pointer is a caller contract violation;
- neither method wakes threads, blocks, spins, or performs I/O within the
  cache's contract; source implementations that do so are outside the
  `PoolCache` spec.

The cache never inspects, retains, or forwards `RegionSource` state beyond
calling these two methods. The source pointer stored in the cache is used
only to dispatch `refill` and `drain`.

## Approved API

```zig
pub fn PoolCache(comptime T: type, comptime RegionSource: type) type;
```

Returned namespace:

```zig
pub const Self = struct {
    source: *RegionSource,
    empty_head: ?*RegionHeader = null,
    partial_head: ?*RegionHeader = null,
    full_head: ?*RegionHeader = null,
    region_count: usize = 0,
    live_count: usize = 0,

    pub const Slot = Pool.Bounded(T).Slot;

    pub const Error = error{ OutOfMemory };
    pub const RefillError = RegionSource.Error || Error;

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
};
```

`T` MUST be a runtime value type with `@sizeOf(T) > 0`.

`RegionSource` MUST satisfy the interface contract above. Violations are
compile errors with messages that name the missing or invalid declaration.

`RegionHeader` is a private implementation detail. Callers MUST NOT rely
on its exact layout beyond what this spec requires.

## Region layout

Every region acquired from the source begins with a `RegionHeader` at
offset zero. The remaining `region_bytes - header_bytes` bytes host a
contiguous `[slots_per_region]Slot` array whose first slot starts at the
first byte-position at or after the header whose alignment satisfies
`@alignOf(Slot)`. `slots_per_region` is chosen at compile time as the
largest integer for which the header, alignment padding, and slot array
all fit in `region_bytes`.

`slots_per_region >= 1` is required at compile time. When this condition
fails, `PoolCache(T, RegionSource)` is a compile error with a message
naming `region_bytes`, `region_align`, and the resulting layout.

`RegionHeader` contains at minimum:

- an intrusive list link used by the empty / partial / full lists;
- a `Pool.Bounded(T)` instance whose `buffer` field points into the
  in-region slot array;
- a `region_ptr: *align(region_align) [region_bytes]u8` back-pointer used
  by `drain` when returning the region to the source.

Implementations MAY add extra fields (e.g. a `back_link` for O(1) removal,
a live-count cache) provided the additions do not weaken the spec's
guarantees.

## Region membership lists

Every region held by the cache appears on exactly one of three intrusive
singly-linked lists:

- **empty**: `RegionHeader.pool.len() == 0`;
- **partial**: `0 < RegionHeader.pool.len() < slots_per_region`;
- **full**: `RegionHeader.pool.len() == slots_per_region`.

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
3. Initialize the header: install the intrusive link, initialize the
   inner `Pool.Bounded(T)` over the in-region slot array via
   `Pool.Bounded(T).wrap(slot_slice)`, store `region_ptr = region`.
4. Push the header onto the empty list.
5. Increment `region_count`.

`refill` propagates the exact error returned by `source.acquire` under
`RefillError = RegionSource.Error || error{ OutOfMemory }`. When
`RegionSource.Error` already contains `OutOfMemory`, the merged set
collapses that case; otherwise `error.OutOfMemory` in `RefillError`
signals a cache-side pre-check failure. This spec does not define such a
pre-check today; the extra variant is reserved so implementations that
add one later do not widen the error set.

## `drain()` semantics

`drain()` returns every region on the empty list to the source.

Logic:

1. For each `RegionHeader` on the empty list (in list order):
   - unlink it from the empty list;
   - call `source.release(header.region_ptr)`;
   - decrement `region_count`.
2. Regions on the partial or full list are not touched.

`drain` never fails and never allocates.

`drain` MUST NOT reorder regions on the partial or full lists.

## `acquire()` semantics

`acquire()` allocates one `*T` from any region that has free slots.

Logic:

1. If the partial list is non-empty, choose its head region and call
   `header.pool.acquire()`. On success, if the region is now full,
   move it from the partial list to the full list. Increment
   `live_count`. Return the pointer.
2. Otherwise, if the empty list is non-empty, choose its head region,
   move it from the empty list to the partial list (or full list if
   `slots_per_region == 1`), and call `header.pool.acquire()`.
   Increment `live_count`. Return the pointer.
3. Otherwise, return `error.OutOfMemory` and leave the cache
   unchanged. The caller decides whether to call `refill()` next.

`acquire` never calls `source.acquire`. It never walks the full list.

The returned `*T` satisfies `@alignOf(T)` and points at uninitialized
storage (subject to `Pool`'s debug-fill contract on Debug/ReleaseSafe).

## `release(item)` semantics

`release(item)` returns `item` to its owning region's pool.

Logic:

1. Compute `region_ptr` by masking `@intFromPtr(item)` down to
   `region_align`. Under `stdx.core.debug.checksEnabled(.build_mode)`,
   assert that the result matches one of the cache's known region
   pointers. In release builds this is a caller contract violation
   silently accepted for O(1) release.
2. Recover the `RegionHeader` at the base of the region.
3. Note the region's pre-release list class (empty, partial, or full)
   from `header.pool.len()` versus `slots_per_region`.
4. Call `header.pool.release(item)`.
5. Move the region to its new list class if it changed (see the
   transitions table above).
6. Decrement `live_count`.

`release` never calls `source.release`. Regions that reach the empty
list stay in the cache until `drain()` is called explicitly.

`release` is O(1) amortized. It does not walk any list.

## `contains(item)` semantics

`contains(item)` returns `true` iff `item` points into a region currently
owned by this cache.

Logic:

1. Mask `@intFromPtr(item)` down to `region_align` to obtain a candidate
   `region_ptr`.
2. Walk the empty, partial, and full lists (in any order) and return
   `true` when a header's `region_ptr` matches.
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

## Behavior contract

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
- `refill` may return `error.OutOfMemory` from `RefillError` for
  cache-side pre-check failures introduced by future extensions. State
  unchanged.
- `release`, `drain`, and `contains` do not return errors; misuse is a
  programmer error caught by `assertValid` where practical.
- zero-sized `T` is a compile error.
- `slots_per_region == 0` is a compile error at
  `PoolCache(T, RegionSource)` instantiation.

All error returns leave the cache unchanged.

## Debug assertion behavior

`assertValid()` walks the empty, partial, and full lists and checks:

- each list's regions have the expected `header.pool.len()` class;
- `region_count` equals the sum of the three list lengths;
- `live_count` equals the sum of `header.pool.len()` across every
  region;
- every region's inner `Pool.Bounded(T)` passes its own `isValid`;
- no region appears on more than one list;
- every region's `region_ptr` is `region_align`-aligned.

`assertValid()` is O(region_count + region_count * slots_per_region) and
is called explicitly. Operations do not call it unconditionally on hot
paths.

`isValid()` returns whether the same conditions hold, without
asserting.

## Implementation constraints

Implementation MUST:

- store the region-list metadata inside `RegionHeader` at region offset
  zero (no external metadata array);
- initialize each region's inner `Pool.Bounded(T)` via
  `Pool.Bounded(T).wrap` — do NOT reimplement the Pool bookkeeping
  inside the cache;
- respect the Pool debug-fill contract by delegating `acquire`/`release`
  to the inner pool;
- never call `RegionSource.acquire` from `acquire`;
- never call `RegionSource.release` from `release`;
- perform O(1) list moves on transitions between empty / partial / full
  (an intrusive next+prev link in `RegionHeader` if singly-linked lists
  cannot support O(1) unlink);
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

const CmdCache = stdx.mem.PoolCache(Cmd, PageFrameSource);

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
`docs/specs/mem/frame-allocator.md`):

```zig
const Phys4K = stdx.addr.Page(stdx.addr.PhysAddr, stdx.addr.pages._4kib);
const FrameAlloc = stdx.mem.FrameAllocator.Static(
    stdx.mem.BuddyAllocator.Static(1024, 6),
    Phys4K,
    try Phys4K.Frame.fromAddressInt(0x0010_0000),
);

var frames = FrameAlloc.init();
var source = frames.frameSource(0);            // one 4 KiB region per acquire

const NodeCache = stdx.mem.PoolCache(Node, @TypeOf(source));
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

Tests live in `test/mem/pool_cache_test.zig`. A mock region source with
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

- 10 000 random operations over a `PoolCache(u64, MockSource)` with
  `region_bytes = 256` and `region_align = 64`;
- the model checks pointer validity, `contains` correctness, list
  membership invariants after every op;
- at the end of the sequence, a final `drain` returns the cache to
  zero regions and the mock source's `acquire`/`release` counts
  balance.

### Comptime rejections

- zero-sized `T` fails to instantiate;
- a `RegionSource` missing `region_bytes` fails to instantiate;
- a `RegionSource` missing `acquire` fails to instantiate;
- a `RegionSource` whose `region_align` does not satisfy
  `@alignOf(RegionHeader)` fails to instantiate;
- a `RegionSource` whose `region_bytes` cannot fit at least one header
  plus one slot fails to instantiate.

### Debug fill inheritance

- `PoolCache`'s acquired pointers are subject to the same
  `0xCD` / `0xFD` fill discipline as `Pool` under
  `checksEnabled(.build_mode) == true` — the test relies on the
  underlying `Pool.Bounded(T)` inside each region enforcing it.

## Open questions

None.
