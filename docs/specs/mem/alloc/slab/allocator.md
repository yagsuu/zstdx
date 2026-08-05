# Memory slab allocator

Status: Approved.

`stdx.mem.alloc.SlabAllocator` is a fixed-capacity, typed, intrusive-free-list object slab allocator
with O(1) acquire and release and pointer-stable storage for the lifetime of
each acquired slot. It does not allocate, wait, or call destructors.

`SlabAllocator.Static(T, N)` owns inline `[N]Slot` storage. `SlabAllocator.Bounded(T)` borrows
caller-owned `[]Slot` storage. Both share every observable behavior except
construction.

## Owned scope

This spec owns:

- `mem.alloc.SlabAllocator.Static(T, N)`;
- `mem.alloc.SlabAllocator.Bounded(T)`;
- private intrusive free-list discipline using `Slot = union(enum)`;
- `acquire`/`release` semantics with O(1) cost;
- pointer-stability rules and uninitialized-payload rules;
- the `error{ OutOfMemory }` error mode;
- zero-capacity behavior;
- `clearRetainingCapacity` rebuild semantics;
- `assertValid` invariants;
- required tests.

This spec does not own:

- destructors, release callbacks, or value finalizers;
- generation counters or stale-handle detection;
- multi-typed slab allocators;
- thread-safe slab allocators;
- iteration over live objects;
- shrinking, defragmentation, or compaction;
- automatic zeroing or poisoning;
- runtime-changeable capacity;
- alignment override beyond `@alignOf(T)`;
- bulk acquire/release helpers;
- `std.mem.Allocator` views.

## Public namespace

`SlabAllocator` lives under `stdx.mem.alloc`:

```zig
stdx.mem.alloc.SlabAllocator
stdx.mem.alloc.SlabAllocator.Static
stdx.mem.alloc.SlabAllocator.Bounded
```

It is not root-promoted:

```zig
stdx.SlabAllocator // not exported
```

Source ownership:

```text
src/mem.zig
src/mem/alloc/slab/allocator.zig
test/mem/alloc/slab/allocator_test.zig
```

`src/mem/alloc/slab.zig` re-exports:

```zig
pub const allocator = @import("slab/allocator.zig");

pub const SlabAllocator = allocator.SlabAllocator;
```

## Approved API

```zig
pub const SlabAllocator = struct {
    pub fn Static(comptime T: type, comptime capacity_items: usize) type;
    pub fn Bounded(comptime T: type) type;
};
```

`T` must be a runtime value type with `@sizeOf(T) > 0`. Zero-sized element
types are compile errors where practical.

### `Static(T, N)` returned type

```zig
pub const Self = struct {
    buffer: [N]Slot = undefined,
    free_head: ?*Slot = null,
    bump_index: usize = 0,
    live_count: usize = 0,

    pub const Slot = union(enum) {
        free: ?*Slot,
        occupied: T,
    };

    pub const Error = error{ OutOfMemory };
    pub const item_capacity = N;

    pub fn init() Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn acquire(self: *Self) Error!*T;
    pub fn release(self: *Self, item: *T) void;

    pub fn isValid(self: *const Self) bool;
    pub fn assertValid(self: *const Self) void;
};
```

### `Bounded(T)` returned type

```zig
pub const Self = struct {
    buffer: []Slot,
    free_head: ?*Slot = null,
    bump_index: usize = 0,
    live_count: usize = 0,

    pub const Slot = union(enum) {
        free: ?*Slot,
        occupied: T,
    };

    pub const Error = error{ OutOfMemory };

    pub fn wrap(buffer: []Slot) Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn acquire(self: *Self) Error!*T;
    pub fn release(self: *Self, item: *T) void;

    pub fn isValid(self: *const Self) bool;
    pub fn assertValid(self: *const Self) void;
};
```

`Static` and `Bounded` have identical observable slab semantics. They differ
only in storage ownership.

## Type and capacity contract

`Slot = union(enum) { free: ?*Slot, occupied: T }` is the per-element storage.
A free slot stores the next pointer in the intrusive free list. An occupied
slot stores `T`. The slot's tag identifies the discriminator; callers never
read the tag directly.

`@alignOf(Slot) >= @alignOf(T)` is guaranteed by Zig's union alignment rules.
Acquired pointers satisfy `@alignOf(T)`.

A valid slab allocator satisfies:

```zig
self.live_count <= self.capacity()
```

`Static(T, 0)` is a compile error. `Bounded(T).wrap(&.{})` is valid; the allocator
is empty and full.

## Ownership and lifetime

`Static(T, N)` owns inline `Slot` storage. The pool value must not move while
any acquired pointer is live, because the pointer borrows into the pool's
inline buffer.

`Bounded(T)` borrows `[]Slot` from the caller. The caller must keep the buffer
alive for the lifetime of the pool and every acquired pointer.

Copying a pool value duplicates the slice pointer (Bounded) or the inline
buffer (Static). The pool family does not support multiple authoritative
mutable copies over the same storage. Use one pool value per storage.

## Construction and clearing

`Static.init()` returns an empty pool with all internal indices at zero. It does
not pre-link any slots. `Static(T, N)` requires `N > 0`.

`Bounded.wrap(buffer)` returns an empty pool over `buffer`. It does not pre-link
any slots. An empty `buffer` produces an empty-and-full pool.

The pool maintains an internal bump cursor and an intrusive free list. New
slots are carved off the bump cursor first (storage order). Released slots
are linked into the free list and reused on subsequent acquire calls before
the cursor advances again. This avoids materializing self-referential
pointers during construction, which is required so `Static.init()` can
return its value safely.

`clearRetainingCapacity()` clears the bump cursor, the free list, and
`live_count`. It invalidates every outstanding acquired pointer. It does
not zero, poison, or destruct anything.

There is no `deinit` or `clearAndFree`; the pool owns no heap allocation.

## Capacity operations

`len()` returns `live_count`.

`capacity()` returns the slot capacity (`N` for Static, `buffer.len` for
Bounded).

`remaining()` returns `capacity() - len()`.

`isEmpty()` returns `len() == 0`.

`isFull()` returns `len() == capacity()`.

These operations do not walk the free list.

## Acquire semantics

`acquire()` returns a pointer into the pool's storage for one slot.

- If `free_head` is non-null, pops the head slot from the free list,
  switches the slot to the `.occupied` tag with the payload left
  uninitialized (`undefined`), increments `live_count`, and returns
  `&slot.occupied`.
- Otherwise, if `bump_index < capacity()`, carves the next un-touched slot
  from storage at `buffer[bump_index]`, advances `bump_index`, marks the
  slot `.occupied` with an uninitialized payload, increments `live_count`,
  and returns `&slot.occupied`.
- Otherwise (no free slot and `bump_index == capacity()`), returns
  `error.OutOfMemory` and leaves the pool unchanged.

The returned pointer satisfies `@alignOf(T)` and references uninitialized
storage. Callers must initialize before reading.

The free list is single-linked and intrusive in the slot itself. Acquire is
O(1) and never branches into a loop.

## Release semantics

`release(item: *T)` returns the slot owning `item` to the free list.

The implementation recovers the owning slot via `@fieldParentPtr("occupied",
item)`.

Preconditions, all programmer errors if violated:

- `item` was returned by this pool's `acquire`,
- the slot is currently occupied (`item` has not already been released),
- the pool value has not been moved or copied since `item` was acquired.

`release` does not run destructors and does not zero the payload. The slot
transitions from `.occupied` to `.free` with the free-list link pointing at
the prior `free_head`. `free_head` is set to the released slot.

`release` is O(1) and never branches into a loop.

There is no error return; pool misuse is a programmer error.

## Free-list reuse order

The free list is LIFO: the most recently released slot is the next slot
returned by `acquire`. Spec promises this order; implementations must not
deviate.

## Pointer stability

Acquired pointers remain valid until any of:

- the matching `release(item)` call,
- `clearRetainingCapacity()`,
- destruction or move of the pool value (programmer error),
- (Bounded only) destruction or move of the borrowed buffer.

`acquire`/`release` of other slots does not invalidate previously acquired
pointers.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `Static.init` | none | never | O(N) | none | caller-owned value | initializes free list |
| `Bounded.wrap` | none | never | O(buffer.len) | none | caller-owned buffer | initializes free list |
| `len`, `capacity`, etc. | none | never | O(1) | none | caller-owned value | none |
| `acquire` | inline / caller buffer | never | O(1) | none | caller-owned value | pops free-list head |
| `release` | none | never | O(1) | released pointer | caller-owned value | pushes free-list head |
| `clearRetainingCapacity` | none | never | O(N) | all live pointers | caller-owned value | rebuilds free list |
| `assertValid` | none | never | O(N) | none | caller-owned value | walks free list |
| `isValid` | none | never | O(N) | none | caller-owned value | walks free list |

These operations perform no heap allocation, waiting, hidden global access,
atomics, barriers, volatile access, target probing, syscalls, locks, or I/O.

Concurrent mutation is outside the contract. Callers must externally
synchronize shared mutable access.

## Error behavior

- `acquire` returns `error.OutOfMemory` when both the free list is empty
  and the bump cursor has reached `capacity()`;
- `release` does not return an error; misuse is a programmer error;
- zero-sized `T` is a compile error;
- corrupted `free_head`, `bump_index`, `live_count`, or `Slot` tag is a
  programmer error caught by `assertValid` where practical.

All error returns leave the pool unchanged.

## Debug assertion behavior

`assertValid()` walks the free list and checks:

- `bump_index <= capacity()`;
- `live_count <= bump_index`;
- every visited free-list slot pointer lies inside the pool's `buffer`;
- the free list has no cycles (bounded by `bump_index - live_count + 1`
  steps);
- the free list contains exactly `bump_index - live_count` entries.

`assertValid()` is called explicitly. Operations do not call it
unconditionally on hot paths.

## Debug fill

When `stdx.core.debug.checksEnabled(.build_mode)` is `true`, `acquire` and
`release` overwrite the payload byte window with fixed patterns so that
use-after-free and use-before-init errors are visible in Debug and
ReleaseSafe:

- `acquire`, after switching the slot tag to `.occupied` and before
  returning `&slot.occupied`, writes `0xCD` to every byte of the payload
  window `[&slot.occupied, &slot.occupied + @sizeOf(T))`;
- `release`, after asserting the slot is currently `.occupied` and
  before switching the tag back to `.free`, writes `0xFD` to every byte
  of the same payload window. Immediately after the release the free-
  list link overwrites the first `@sizeOf(?*Slot)` bytes of that
  window; only bytes at offsets `[@sizeOf(?*Slot), @sizeOf(T))` remain
  observable as `0xFD` for use-after-free diagnostics.

When `checksEnabled(.build_mode)` is `false` (ReleaseFast and
ReleaseSmall), neither fill runs and the payload window is left in
whatever state the last public operation left it. Callers that need
deterministic zeroing must do it themselves.

Debug fill does not touch the `Slot` tag bytes, the free-list link stored
in the `.free` variant, or any bytes outside `[0, @sizeOf(T))` at the
payload location. Padding bytes inside the union are unspecified.

Debug fill is a payload-only diagnostic. It is not a poisoning policy, not
a leak detector, and does not affect the observable free-list order,
`live_count`, `bump_index`, or `free_head`.

## Implementation constraints

Implementation must:

- store the free list inside `Slot` itself (no external metadata);
- use `@fieldParentPtr("occupied", item)` to recover the slot from a `*T`;
- never destruct or touch the payload of an occupied slot outside the
  debug-fill contract defined above;
- not loop in `acquire` or `release`;
- not walk the free list in capacity helpers;
- not perform unconditional invariant scans on hot paths;
- avoid hidden globals, atomics, fences, syscalls, target probes,
  allocation, and unconditional payload writes on release builds;
- compile for freestanding targets.

## Usage

Static pool:

```zig
const Frame = struct { id: u32, data: [256]u8 };
var pool = stdx.mem.alloc.SlabAllocator.Static(Frame, 16).init();

const f = try pool.acquire();
f.* = .{ .id = 7, .data = undefined };
// … use f …
pool.release(f);
```

Bounded pool with caller storage:

```zig
const SlabT = stdx.mem.alloc.SlabAllocator.Bounded(Frame);
var storage: [16]SlabT.Slot = undefined;
var pool = SlabT.wrap(&storage);

const f = try pool.acquire();
f.* = .{ .id = 7, .data = undefined };
pool.release(f);
```

Bounded pool over arena storage:

```zig
var arena = stdx.mem.alloc.Arena.Static(4096).init();
const SlabT = stdx.mem.alloc.SlabAllocator.Bounded(Job);
const storage = try arena.allocSlice(SlabT.Slot, 64);
var jobs = SlabT.wrap(storage);
```

Exhaustion and reuse:

```zig
const SlabT = stdx.mem.alloc.SlabAllocator.Static(u32, 2);
var p = SlabT.init();
const a = try p.acquire();
const b = try p.acquire();
try std.testing.expectError(error.OutOfMemory, p.acquire());
p.release(a);
const c = try p.acquire(); // reuses a's slot (LIFO)
_ = b;
_ = c;
```

## Planned use

- control blocks, event entries, and record structures that fit in a static
  or bounded pool without hot-path heap allocation;
- handle tables, request structures, and packet descriptors that need
  pointer stability across long-lived phases;
- namespace nodes, table descriptors, and parser scratch entries.

## Required tests

### Construction and capacity

- `SlabAllocator.Static(T, N).init()` reports `len == 0`, `capacity == N`,
  `remaining == N`;
- `SlabAllocator.Bounded(T).wrap(buffer)` reports `capacity == buffer.len`;
- `SlabAllocator.Static(T, 0).init()` is both empty and full; `acquire` returns
  `error.OutOfMemory`;
- `SlabAllocator.Bounded(T).wrap(&.{})` is both empty and full; `acquire` returns
  `error.OutOfMemory`.

### Acquire and release

- `acquire` returns a non-null `*T` with `@alignOf(T)` alignment;
- writes through the returned pointer round-trip until `release`;
- `acquire` after capacity exhaustion returns `error.OutOfMemory` and leaves
  `live_count` unchanged;
- `release` returns a slot to the free list and allows a subsequent
  `acquire` to succeed;
- LIFO reuse: the most recently released slot is the next one acquired;
- multiple live pointers do not alias each other's payloads.

### Lifecycle

- `clearRetainingCapacity` resets `live_count` to 0 and restores full
  capacity;
- acquire/release cycles preserve `len + remaining == capacity`;
- a repeated acquire/release loop over many iterations leaves the pool
  valid.

### Invariants

- `assertValid` succeeds for empty, partial, and full pools;
- `isValid` returns the same boolean as `assertValid`'s result without
  asserting.

### Bounded specifics

- a Bounded pool backed by an arena slice acquires up to `buffer.len` items
  and then returns `error.OutOfMemory`;
- a Bounded pool over a zero-length buffer is empty and full.

### Static specifics

- `SlabAllocator.Static(T, 1)` cycles through acquire/release without losing the
  slot;
- `SlabAllocator.Static(T, N).item_capacity == N`.

### Type identity

- `SlabAllocator.Bounded(A)` and `SlabAllocator.Bounded(B)` are distinct types for distinct
  `T`;
- `SlabAllocator.Static(T, M)` and `SlabAllocator.Static(T, N)` are distinct types for
  `M != N`.

### Debug fill

Required with a payload type large enough that the last byte lies beyond
`@sizeOf(?*Slot)`, e.g. `[64]u8` or `struct { bytes: [64]u8 }`:

- under `stdx.core.debug.checksEnabled(.build_mode) == true`, every byte
  of the payload window returned by `acquire` equals `0xCD`;
- under `checksEnabled(.build_mode) == true`, immediately after
  `release` every byte of the payload window at offsets
  `[@sizeOf(?*Slot), @sizeOf(T))` equals `0xFD` when read through a raw
  pointer that outlives the release. Bytes at offsets
  `[0, @sizeOf(?*Slot))` are overwritten by the free-list link and MUST
  NOT be asserted;
- under `checksEnabled(.build_mode) == false`, the fill patterns MUST
  NOT appear. The test asserts that neither `0xCD` nor `0xFD` is
  observed in the payload window after `acquire` or after `release`;
- fills do not affect `len`, `remaining`, `bump_index`, `free_head`,
  LIFO reuse order, or `assertValid` results.

## Open questions

None.
