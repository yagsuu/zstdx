# `stdx.mem.alloc.SlabCache`

`SlabCache(T, RegionSource)` acquires typed objects from explicitly supplied
regions and returns empty regions to their source. Its `PerCpu` variant adds
bounded local caches around a synchronized global cache.

## Region source and layout

`T` must have nonzero size. `RegionSource` supplies these declarations:

```zig
pub const region_bytes: usize;
pub const region_align: usize;
pub const Error: type;

pub fn acquire(self: *Self) Error!*align(region_align) [region_bytes]u8;
pub fn release(self: *Self, region: *align(region_align) [region_bytes]u8) void;
```

`Error` is an error set. `region_bytes` must be positive. `region_align` must be
a nonzero power of two, at least `region_bytes`, and sufficient for the in-region
header and slot array. Each acquired region must provide distinct writable storage
until the cache returns that region through `release`.

The cache reserves a header at the region base and aligns the slot array after
that header. `Slot` is `SlabAllocator.Bounded(T).Slot`, so capacity includes the
slot's tag, link, and padding. The layout must fit at least one slot. Invalid
type, source, or layout constraints fail at compile time.

`slots_per_region` is the maximum whole-slot count after the aligned header.
Every region has this capacity. Coloring shifts the slot array within the unused
trailing bytes without reducing capacity:

- `color_stride = max(std.atomic.cache_line, @alignOf(Slot))`.
- `color_count = 1 + trailing_bytes / color_stride`.

Successful refills cycle through the colors, starting at zero. Failed refills
preserve the next color. Returned object pointers satisfy `@alignOf(T)`.

## Base cache operations

Here, `Cache` denotes the type returned by `SlabCache(T, RegionSource)`.

`Cache.init(source)` borrows the source and starts empty.

| Operation | Result and resource effect | Failure state |
| --- | --- | --- |
| `Cache.refill()` | Calls `source.acquire()` once and adds one empty region. | Propagates `RegionSource.Error` unchanged. Cache state is unchanged. Source state follows the source's contract. |
| `Cache.acquire()` | Acquires one object, preferring a partially used region over an empty region. | Returns `error.OutOfMemory` when all held slots are occupied. Cache state is unchanged. |
| `Cache.release(item)` | Returns one live object to its region. The region remains held. | No returned error. |
| `Cache.drain()` | Calls `source.release()` once for each empty region. Regions with live objects remain held. | No returned error. |

Call `Cache.refill()` to reserve capacity and `Cache.drain()` to reclaim empty
regions. Only these operations call the source. Their callback costs follow the
source contract. Base-cache operations add no waiting.

Acquire returns uninitialized storage. Initialize the object before reading it.
Release requires an exact, currently live pointer acquired from this cache.
The caller must clean up resources owned by an object before releasing it.
The [slab allocator's payload-fill contract](allocator.md#acquire-release-and-clear)
applies to base-cache acquire and release.
Released slots follow LIFO reuse within each region. There is no global object
reuse-order guarantee.

Length counts live objects. Capacity is `Cache.regionCount() * slots_per_region`.

`Cache.contains(item)` tests whether the pointer's `region_align`-aligned base
matches a held region. `Cache.isValid()` checks structural consistency.

## Per-CPU variant

`Cache.PerCpu(cpu_count, local_capacity)` requires both counts to be positive at
compile time. `PerCpu.init(source)` creates an empty cache.

Supply `cpu` in `0..cpu_count` to acquire and release. Each local cache requires
exclusive access by one executor at a time. The caller supplies CPU routing and
prevents overlapping operations on the same index.

`PerCpu.acquire(cpu)` first pops a local object in LIFO order. If that local cache
is empty, the operation takes the global spin lock, acquires one object for the
caller, and reserves up to `local_capacity` additional global objects locally.
It returns `error.OutOfMemory` unchanged when the global acquisition fails.
The operation never obtains regions from the source.

Objects reserved by another local cache are unavailable to this acquisition.
Consequently, `PerCpu.acquire()` can fail while `PerCpu.remaining()` is positive.

`PerCpu.release(cpu, item)` accepts a live object acquired through this per-CPU
cache, including an object acquired through another CPU index. When the selected
local cache is full, release takes the global lock and returns all its cached
objects to the global cache before caching `item`.
A local release ends the caller's acquisition, but the underlying slot remains
reserved until a flush. Local pop and push do not run payload fills.

`PerCpu.refill()` holds the global lock while it delegates to `Cache.refill()`.
Its source error leaves the cache unchanged. `PerCpu.drain()` holds the global
lock, flushes all local objects to the global cache, then drains empty regions.
These operations execute source callbacks while holding the lock. Callbacks must
not re-enter operations that require that lock.

Quiesce local operations before `PerCpu.drain()`. Aggregate queries,
`PerCpu.contains()`, and `PerCpu.isValid()` require no concurrent mutation.
`PerCpu.len()` excludes locally reserved objects. `PerCpu.remaining()` and
`PerCpu.isEmpty()` use that caller-live count.

## Ownership, cleanup, and costs

Keep the borrowed source and all held regions alive at stable addresses until
their regions have been returned. Use one authoritative mutable cache value.
The base cache requires external synchronization for shared access that overlaps
mutation. Synchronize any source access outside the cache separately.

An object's acquisition remains valid until release. Other object operations,
refill, and drain preserve live object pointers. Before discarding a cache:

1. For `PerCpu`, quiesce local operations.
2. Clean up and release all live objects.
3. Call `Cache.drain()` or `PerCpu.drain()`.

Neither variant performs automatic object or region cleanup.

Base-cache construction, count queries, and acquisition perform constant metadata
work. Release performs constant metadata work with checks disabled. With checks
enabled, cache membership validation costs O(regionCount).
Payload fills add O(`@sizeOf(T)`) when enabled. Refill adds constant metadata work
to one source acquisition. Drain costs O(empty regions) plus source releases.
`Cache.contains()` costs O(regionCount), and `Cache.isValid()` costs
O(regions + total slots) in the worst case.

Per-CPU local hits take constant work. Global fallback and full-local flush take
O(local_capacity) object operations under a spin lock. Lock acquisition can spin.
`PerCpu.len()`, `PerCpu.remaining()`, and `PerCpu.isEmpty()` cost O(cpu_count). Drain additionally
flushes up to `cpu_count * local_capacity` pointers. Validation includes global
validation and a region-membership query for each locally cached pointer.

## References

- [Region caches](../../../../../src/mem/alloc/slab/cache.zig)
- [Object pools](allocator.md)
