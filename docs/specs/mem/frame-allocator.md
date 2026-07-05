# Memory frame allocator

Status: Approved.

`stdx.mem.FrameAllocator(Backend, Page)` lifts a unit-index allocator
(`Backend`) into an `addr.Page.Frame` / `addr.Page.FrameRange` vocabulary.
It owns the unit-to-frame conversion, a base-frame anchor, `reserve`
translation, and canonical frame-count statistics. It does not own the
underlying free-list state — the `Backend` (typically
`mem.BuddyAllocator.Static` or `mem.BuddyAllocator.Bounded`) owns that.

Every consumer today rewrites the same "block start × page size + base
frame = Frame" adapter and gets `reserve` accounting subtly wrong.
`FrameAllocator` closes that gap once for every sibling project.

## Owned scope

This spec owns:

- `mem.FrameAllocator.Static(Backend, Page, base_frame)`;
- `mem.FrameAllocator.Bounded(Backend, Page)`;
- unit-index ↔ `Page.Frame` conversion around any conforming `Backend`;
- `alloc(order)` returning a `Page.FrameRange`;
- `free(range)` translated to `Backend.free(block)`;
- `reserve(range)` translated to `Backend.reserve(unit_range)`;
- `isFree(range)` query;
- canonical stats: `freeFrames`, `allocatedFrames`, `largestFreeOrder`,
  `remainingBytes`, `capacityFrames`;
- nested `FrameSource(order)` region-source view satisfying
  `docs/specs/mem/pool-cache.md`'s `RegionSource` interface;
- structural invariants and `assertValid` contract;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- byte-granular allocation; `alloc` returns `Page.FrameRange`, never
  `[]u8`;
- physical-memory-map ownership (E820, EFI memory map, ACPI tables);
- virtual-to-physical translation, MMU state, or paging structures;
- NUMA locality or per-CPU caches;
- dynamic backing growth or shrinkage;
- concurrency, atomics, locking, or wait behavior;
- iteration over live allocations, watermarks, tracing, or statistics
  beyond the canonical frame counts named above;
- automatic zeroing or poisoning of allocated frames;
- `std.mem.Allocator` byte-view adapter;
- root promotion.

## Public namespace

`FrameAllocator` lives under `stdx.mem`:

```zig
stdx.mem.FrameAllocator
stdx.mem.FrameAllocator.Static
stdx.mem.FrameAllocator.Bounded
```

It is not root-promoted:

```zig
stdx.FrameAllocator // not exported
```

Source ownership:

```text
src/mem.zig
src/mem/frame.zig
test/mem/frame_test.zig
```

`src/mem.zig` re-exports:

```zig
pub const frame = @import("mem/frame.zig");

pub const FrameAllocator = frame.FrameAllocator;
```

## Backend interface

`Backend` is a comptime-duck-typed unit allocator. Every conforming type
MUST expose the following declarations, evaluated at `FrameAllocator(...)`
instantiation:

```zig
pub const Block: type;    // structurally equal to algo.allocation.Buddy.Block
pub const Range: type;    // structurally equal to core.Range(usize)
pub const Error: type;    // a Zig error set

pub fn capacity(self: *const Self) usize;
pub fn orderCount(self: *const Self) u8;
pub fn maxOrder(self: *const Self) u8;
pub fn allocatedUnits(self: *const Self) usize;
pub fn remainingUnits(self: *const Self) usize;

pub fn alloc(self: *Self, order: u8) Error!Block;
pub fn free(self: *Self, block: Block) Error!void;
pub fn reserve(self: *Self, range: Range) Error!void;
pub fn isFreeBlock(self: *const Self, block: Block) bool;

pub fn assertValid(self: *const Self) void;
```

Requirements:

- `Block` MUST expose `start: usize` and `order: u8` fields with the
  semantics of `stdx.algo.allocation.Buddy.Block`;
- `Range` MUST expose `start: usize` and `end: usize` fields with the
  half-open semantics of `stdx.core.Range(usize)`;
- `Error` MUST be a subset of, or equal to, the `FrameAllocator` error
  set below. Broader backend error sets are compile errors — the
  frame-allocator does not silently widen the caller-visible surface.

`mem.BuddyAllocator.Static(unit_capacity, order_count)` and
`mem.BuddyAllocator.Bounded` satisfy this interface directly.
`mem.BitmapAllocator` does not (it exposes `allocOne` / `allocRange` in
place of `alloc(order)` / `free(block)`); adding a wrapper for the
order-0-only case is outside this spec.

## Error set

```zig
pub const Error = error{
    OutOfMemory,
    OutOfBounds,
    InvalidRequest,
    InvalidOrder,
    AlreadyAllocated,
    NotAllocated,
    Overflow,
};
```

Semantics:

- `OutOfMemory`: propagated from `Backend.alloc` when no free block of
  the requested order exists;
- `OutOfBounds`: `reserve`/`free` range escapes `[base, base + capacity)`;
- `InvalidRequest`: malformed request — invalid `FrameRange`, or
  `wrap` parameters that violate the base-frame alignment or backend
  capacity;
- `InvalidOrder`: `order >= Backend.orderCount()`;
- `AlreadyAllocated`: propagated from `Backend.reserve` on overlap;
- `NotAllocated`: propagated from `Backend.free` on double-free;
- `Overflow`: unit-index / frame arithmetic overflows `AddressInt`
  (`Page.AddressInt`).

All error returns leave the allocator unchanged (subject to the same
no-mutation-on-error guarantee from the backend).

## Approved API

```zig
pub const FrameAllocator = struct {
    pub fn Static(
        comptime Backend: type,
        comptime Page: type,
        comptime base_frame: Page.Frame,
    ) type;

    pub fn Bounded(
        comptime Backend: type,
        comptime Page: type,
    ) type;
};
```

Both variants return a type exposing:

```zig
pub const Self = struct {
    backend: Backend,          // Static: default-initialized; Bounded: passed to wrap
    base: Page.Frame,          // Static: comptime base_frame; Bounded: stored per instance

    pub const Frame = Page.Frame;
    pub const FrameRange = Page.FrameRange;
    pub const AddressInt = Page.AddressInt;
    pub const Error = /* see "Error set" above */;

    // Static-only:
    pub fn init() Self;

    // Bounded-only:
    pub fn wrap(backend: Backend, base: Frame) Error!Self;

    pub fn baseFrame(self: *const Self) Frame;
    pub fn capacityFrames(self: *const Self) AddressInt;
    pub fn freeFrames(self: *const Self) AddressInt;
    pub fn allocatedFrames(self: *const Self) AddressInt;
    pub fn largestFreeOrder(self: *const Self) ?u8;
    pub fn remainingBytes(self: *const Self) Error!AddressInt;

    pub fn alloc(self: *Self, order: u8) Error!FrameRange;
    pub fn free(self: *Self, range: FrameRange) Error!void;
    pub fn reserve(self: *Self, range: FrameRange) Error!void;
    pub fn isFree(self: *const Self, range: FrameRange) bool;

    pub fn FrameSource(comptime order: u8) type;
    pub fn frameSource(self: *Self, comptime order: u8) FrameSource(order);

    pub fn isValid(self: *const Self) bool;
    pub fn assertValid(self: *const Self) void;
};
```

`Static(Backend, Page, base_frame)` requires:

- `Backend` to be a `Static`-shaped type (its own `init()` returns a
  default-initialized value);
- `base_frame` to be a comptime `Page.Frame`. Misalignment is a
  compile error owned by `Page.Frame` construction.

`Bounded(Backend, Page)` accepts any runtime `backend` value and stores
`base: Page.Frame` per instance. `wrap` validates:

- `base.addressInt() % Page.Size.bytes == 0` (already guaranteed by
  `Frame` construction);
- `base.add(Count.fromPages(backend.capacity()))` does not overflow.

## Unit ↔ frame conversion

The allocator maintains the invariant:

```
frame_at(unit) = base.add(Count.fromPages(unit))
unit_at(frame) = (frame.addressInt() - base.addressInt()) >> Page.Size.shift
```

Every public conversion goes through these helpers. Overflow returns
`error.Overflow` with no mutation. Frames outside
`[base, base + capacityFrames)` return `error.OutOfBounds`.

`alloc(order)` returns:

```
FrameRange {
    base  = frame_at(block.start),
    count = Count.fromPages(1 << order),
}
```

`free(range)` computes `unit_at(range.base)` and calls
`Backend.free(Block{ .start = unit, .order = order })`, where
`order` is derived from `range.count.pages()` via
`stdx.algo.allocation.Buddy.orderForLen`. If `range.count.pages()` is
zero or not a power of two, `free` returns `error.InvalidRequest`
without mutation.

`reserve(range)` computes `unit_at(range.base)` and calls
`Backend.reserve(Range{ .start = unit, .end = unit + range.count.pages() })`.
An empty range with `range.base` inside `[base, base + capacityFrames]`
is a no-op.

`isFree(range)` returns `true` iff the range is a single power-of-two
block aligned to its order, lies inside `[base, base + capacityFrames)`,
and `Backend.isFreeBlock(block)` is `true` for the corresponding
`Block`. It returns `false` otherwise.

## Stats

`capacityFrames()` returns `@intCast(Backend.capacity())` in
`AddressInt`. Overflow at instantiation time (a backend whose capacity
does not fit in `AddressInt`) is a compile error for `Static` and an
`error.InvalidRequest` from `Bounded.wrap`.

`freeFrames()` returns `Backend.remainingUnits()` cast to `AddressInt`.

`allocatedFrames()` returns `Backend.allocatedUnits()` cast to
`AddressInt`.

`largestFreeOrder()` returns the highest order `k` for which a free
block exists in the backend, or `null` when the allocator is fully
allocated.

Implementations MAY walk the backend's bitmap once per call. This spec
does not require constant-time access; consumers that need per-op
constant-time stats maintain their own counters outside.

`remainingBytes()` returns `freeFrames() * Page.Size.bytes` with
checked multiplication. Returns `error.Overflow` when the product does
not fit in `AddressInt`.

## `FrameSource(order)` — RegionSource adapter

`FrameSource(order)` is a zero-state view type parameterized on a
comptime order. It satisfies the `RegionSource` interface from
`docs/specs/mem/pool-cache.md`:

```zig
pub fn FrameSource(comptime order: u8) type {
    return struct {
        parent: *Self,

        pub const region_bytes: usize = @intCast(Page.Size.bytes << order);
        pub const region_align: usize = @intCast(Page.Size.bytes);
        pub const Error = Self.Error;

        pub fn acquire(self: *@This()) Error!*align(region_align) [region_bytes]u8;
        pub fn release(self: *@This(), region: *align(region_align) [region_bytes]u8) void;
    };
}

pub fn frameSource(self: *Self, comptime order: u8) FrameSource(order);
```

Requirements:

- `order` MUST be less than `Backend.orderCount()`. Violations are
  compile errors when `Backend` is `Static` (order count known at
  comptime) and rejected at construction otherwise.
- `region_bytes` MUST fit in `usize`. When `Page.Size.bytes << order`
  overflows `usize`, `FrameSource(order)` is a compile error.
- `acquire(self)` calls `self.parent.alloc(order)`; on success, it
  translates the returned `FrameRange` to
  `*align(region_align) [region_bytes]u8` via
  `@ptrFromInt(@intCast(range.base.addressInt()))`. The returned
  pointer is valid only when `Page.Address` is a domain the caller can
  dereference (`VirtAddr` or a custom `Address` type whose values are
  usable pointers).

Callers that instantiate `FrameSource` with `Page = Page(PhysAddr, ...)`
and no identity-map contract MUST NOT dereference the returned pointer.
`FrameSource` is address-domain-agnostic; typing safety is the caller's
responsibility.

- `release(self, region)` translates the pointer back to a `FrameRange`
  of the same order and calls `self.parent.free(range)`. Errors from
  `free` are contract violations (the caller passed a foreign or
  double-freed region) and are asserted under
  `stdx.core.debug.checksEnabled(.build_mode)`; in release builds the
  error is silently swallowed to match `RegionSource.release`'s
  infallible signature.

`FrameSource(order)` is a plain struct with one field. It does not
allocate, does not spin, and does not read backend state outside its
`acquire`/`release` calls.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `Static.init` | none | never | comptime | none | caller-owned value | initializes backend |
| `Bounded.wrap` | none | never | O(1) | none | caller-owned value | validates base + capacity |
| `baseFrame`, `capacityFrames` | none | never | O(1) | none | caller-owned value | none |
| `freeFrames`, `allocatedFrames` | none | never | O(backend words) | none | caller-owned value | none |
| `largestFreeOrder` | none | never | O(backend words) | none | caller-owned value | none |
| `remainingBytes` | none | never | O(backend words) | none | caller-owned value | Overflow-checked |
| `alloc` | none | never | O(backend) | none | caller-owned value | lowest-index free block of the requested order |
| `free` | none | never | O(backend) | released range | caller-owned value | eager coalesce on release |
| `reserve` | none | never | O(range) | reserved range | caller-owned value | validates whole range before commit |
| `isFree` | none | never | O(1) | none | caller-owned value | none |
| `FrameSource.acquire` | none | never | O(backend) | none | caller-owned value | delegates to `alloc` |
| `FrameSource.release` | none | never | O(backend) | released range | caller-owned value | delegates to `free` |
| `assertValid`, `isValid` | none | never | O(backend words) | none | caller-owned value | walks backend |

`FrameAllocator` performs no heap allocation, sleeping, blocking,
scheduler calls, target probing, atomics, barriers, or hidden global
access. Every state-changing operation requires exclusive ownership;
concurrent callers MUST synchronize externally.

## Debug assertion behavior

`assertValid()` calls `Backend.assertValid()` and additionally checks:

- `base.isValid()`;
- `base.add(Count.fromPages(Backend.capacity()))` does not overflow;
- `capacityFrames() == Backend.capacity()`;
- `allocatedFrames() + freeFrames() == capacityFrames()`.

`isValid()` returns whether the same conditions hold, without
asserting.

Under `stdx.core.debug.checksEnabled(.build_mode)`, `alloc`, `free`, and
`reserve` MAY assert `assertValid()` after mutation. On release builds
the check is compiled out.

## Implementation constraints

Implementation MUST:

- store only the `Backend` and `base: Page.Frame` in the allocator
  value (`Static` inlines the backend; `Bounded` stores it by value);
- forward every state-changing call to the backend without local
  caching;
- perform every unit-to-frame and frame-to-unit conversion through
  checked arithmetic;
- validate the frame-to-unit conversion input's alignment and range
  before every backend call;
- reject `Backend` interface violations at comptime with clear
  messages;
- compile for freestanding targets;
- add no runtime allocation and no hidden globals.

Implementation MAY:

- specialize the `alloc → FrameRange` fast path for the common
  power-of-two-page-count case;
- share helpers between `Static` and `Bounded` bodies.

## Usage

Static physical-frame allocator at a fixed base:

```zig
const stdx = @import("stdx");

const Phys4K = stdx.addr.Page(stdx.addr.PhysAddr, stdx.addr.pages._4kib);
const Buddy = stdx.mem.BuddyAllocator.Static(1024, 6);
const Frames = stdx.mem.FrameAllocator.Static(
    Buddy,
    Phys4K,
    try Phys4K.Frame.fromAddressInt(0x0010_0000),
);

var frames = Frames.init();

// Reserve firmware-owned frames [0x0010_0000, 0x0010_4000).
const reserved = try Phys4K.FrameRange.fromAddressBytes(
    stdx.addr.PhysAddr.fromInt(0x0010_0000),
    4 * stdx.addr.pages._4kib,
);
try frames.reserve(reserved);

const region = try frames.alloc(2);   // 4 contiguous frames (order 2)
defer frames.free(region) catch unreachable;

const bytes = try frames.remainingBytes();
_ = bytes;
```

Runtime-base bounded allocator over caller words:

```zig
var backing: [64]stdx.mem.BuddyAllocator.Bounded.Word = @splat(0);
const backend = try stdx.mem.BuddyAllocator.Bounded.wrap(&backing, 128, 5);

const Virt4K = stdx.addr.Page(stdx.addr.VirtAddr, stdx.addr.pages._4kib);
const Frames = stdx.mem.FrameAllocator.Bounded(
    stdx.mem.BuddyAllocator.Bounded,
    Virt4K,
);

const base = try Virt4K.Frame.fromAddressInt(0xffff_ffff_8000_0000);
var frames = try Frames.wrap(backend, base);

const region = try frames.alloc(3);
try frames.free(region);
```

Compose with `PoolCache` for `kmem_cache_alloc`-shaped growth:

```zig
var source = frames.frameSource(0);   // 4 KiB regions

const NodeCache = stdx.mem.PoolCache(Node, @TypeOf(source));
var cache = NodeCache.init(&source);

try cache.refill();
const node = try cache.acquire();
_ = node;
```

## Planned use

- kernel physical-memory allocators that hand out ranges typed as
  `PhysAddr` frames;
- hypervisor guest-physical-memory allocators typed against a
  custom `Address(GpaTag, u64)` domain;
- firmware pre-runtime frame allocators over a caller-provided
  physical-memory region;
- page-source for `PoolCache(T, FrameSource(order))` used by kernel
  and driver typed-object caches.

## Required tests

Tests live in `test/mem/frame_test.zig`. Backends exercised: at least
`BuddyAllocator.Static(16, 5)` paired with `Page(PhysAddr, _4kib)`,
`BuddyAllocator.Bounded` paired with `Page(VirtAddr, _4kib)`, and one
`BuddyAllocator.Static(...)` paired with a custom
`Page(Address(Tag, u64), _2mib)`.

### Construction

- `Static.init()` yields `capacityFrames() == Backend.capacity()`,
  `allocatedFrames() == 0`, `freeFrames() == capacityFrames()`;
- `Bounded.wrap(backend, base)` succeeds for a valid base and reports
  the same stats;
- `Bounded.wrap` returns `error.InvalidRequest` when the base plus
  capacity would overflow `Page.AddressInt`.

### Alloc and free

- `alloc(order)` returns a `FrameRange` whose `count.pages() ==
  1 << order`;
- the returned `range.base` lies inside `[base, base + capacity)`;
- `range.base.addressInt()` is `(1 << order) * Page.Size.bytes`-aligned
  in unit space (i.e., `(range.base.addressInt() -
  base.addressInt()) % ((1 << order) * Page.Size.bytes) == 0`);
- `alloc → free` restores `freeFrames` to the pre-alloc value;
- `alloc(order_count)` returns `error.InvalidOrder`;
- exhaustion returns `error.OutOfMemory` and leaves stats unchanged.

### Reserve

- `reserve(range)` prevents subsequent `alloc` from returning a range
  overlapping the reserved span;
- `reserve` of a range escaping `[base, base + capacity)` returns
  `error.OutOfBounds` and leaves state unchanged;
- `reserve` overlapping an already-allocated range returns
  `error.AlreadyAllocated` and leaves state unchanged;
- `reserve` of an empty range at a valid boundary is a no-op.

### Query

- `isFree(range)` returns `true` for a free order-aligned block and
  `false` for an allocated one;
- `isFree` returns `false` for a range escaping `[base, base +
  capacity)` and for a range not aligned to a valid order.

### Stats

- `freeFrames + allocatedFrames == capacityFrames` after every op;
- `largestFreeOrder()` matches the highest order present in the free
  set (verified against the backend's own `isFreeBlock`);
- `remainingBytes()` returns the expected byte count and traps
  `error.Overflow` when `freeFrames * Page.Size.bytes` exceeds
  `AddressInt` (constructed via a small custom `Address(Tag, u8)`
  domain).

### FrameSource

- `frameSource(order)` yields a view with `region_bytes = Page.Size.bytes
  << order` and `region_align = Page.Size.bytes`;
- `view.acquire()` returns a pointer whose integer value equals
  `range.base.addressInt()` for the underlying `alloc(order)`;
- `view.release(ptr)` restores the pre-acquire state;
- `FrameSource(order)` where `order >= Backend.orderCount()` is a
  compile error (verified for `Static` backends);
- `FrameSource` satisfies `RegionSource`: instantiating
  `PoolCache(u64, @TypeOf(view))` succeeds and a round-trip
  `refill → acquire → release → drain` cycle balances the frame
  allocator's stats.

### Type identity

- `FrameAllocator.Static(Buddy, Phys4K, ...)` and
  `FrameAllocator.Static(Buddy, Virt4K, ...)` are distinct types;
- `FrameAllocator.Bounded(BuddyBounded, Phys4K)` and
  `FrameAllocator.Bounded(BuddyBounded, Phys2M)` are distinct types;
- `FrameRange` values from different instantiations are not
  assignment-compatible where practical.

### Invariants

- `assertValid` succeeds after every legal `alloc` / `free` /
  `reserve` sequence;
- `isValid` returns the corresponding boolean;
- a corrupted `base` (test-only backdoor) fails `isValid`.

### Model test

Reference: `[capacity_units]bool` oracle tracking free/allocated. On
each random `alloc(order)`, `free(range)`, or `reserve(range)`, the
oracle updates the corresponding units. The model asserts that:

- `allocatedFrames()` equals the oracle's allocated-unit count;
- `freeFrames()` equals the oracle's free-unit count;
- for every legal randomly-generated `FrameRange`, `isFree(range)`
  agrees with the oracle.

Parameter grid: `unit_capacity ∈ {8, 16, 64, 128}`, `order_count ∈
{2, 4, 6}`, one `Phys4K` and one `Virt4K` pass.

### Comptime rejections

- a `Backend` missing `alloc` fails to instantiate;
- a `Backend` whose `Error` set contains errors not in
  `FrameAllocator.Error` fails to instantiate;
- a `Page` whose `AddressInt` cannot hold `Backend.capacity() *
  Page.Size.bytes` still compiles (validated at runtime by
  `remainingBytes` / `wrap`).

## Open questions

None.
