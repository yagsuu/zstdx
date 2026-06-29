# Memory pool

Status: Approved.

`stdx.mem.Pool(T)` is a fixed-capacity, typed, intrusive-free-list object pool
with O(1) acquire and release and pointer-stable storage for the lifetime of
each acquired slot. It does not allocate, wait, or call destructors.

`Pool.Static(T, N)` owns inline `[N]Slot` storage. `Pool.Bounded(T)` borrows
caller-owned `[]Slot` storage. Both share every observable behavior except
construction.

## Owned scope

This spec owns:

- `mem.Pool.Static(T, N)`;
- `mem.Pool.Bounded(T)`;
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
- thread-safe pools;
- iteration over live objects;
- shrinking, defragmentation, or compaction;
- automatic zeroing or poisoning;
- runtime-changeable capacity;
- alignment override beyond `@alignOf(T)`;
- bulk acquire/release helpers;
- `std.mem.Allocator` views.

## Public namespace

`Pool` lives under `stdx.mem`:

```zig
stdx.mem.Pool
stdx.mem.Pool.Static
stdx.mem.Pool.Bounded
```

It is not root-promoted:

```zig
stdx.Pool // not exported
```

Source ownership:

```text
src/mem.zig
src/mem/pool.zig
test/mem/pool_test.zig
```

`src/mem.zig` re-exports:

```zig
pub const pool = @import("mem/pool.zig");

pub const Pool = pool.Pool;
```

## Approved API

```zig
pub const Pool = struct {
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

`Static` and `Bounded` have identical observable pool semantics. They differ
only in storage ownership.

## Type and capacity contract

`Slot = union(enum) { free: ?*Slot, occupied: T }` is the per-element storage.
A free slot stores the next pointer in the intrusive free list. An occupied
slot stores `T`. The slot's tag identifies the discriminator; callers never
read the tag directly.

`@alignOf(Slot) >= @alignOf(T)` is guaranteed by Zig's union alignment rules.
Acquired pointers satisfy `@alignOf(T)`.

A valid pool satisfies:

```zig
self.live_count <= self.capacity()
```

`Static(T, 0)` and `Bounded(T).wrap(&.{})` are valid; the pool is empty and
full simultaneously.

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

`Static.init()` returns an empty pool with all internal indices at zero. It
does not pre-link any slots. `Static(T, 0)` is empty and full.

`Bounded.wrap(buffer)` returns an empty pool over `buffer`. It does not
pre-link any slots. Empty `buffer` results in an empty-and-full pool.

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

## Implementation constraints

Implementation must:

- store the free list inside `Slot` itself (no external metadata);
- use `@fieldParentPtr("occupied", item)` to recover the slot from a `*T`;
- never destruct, zero, or otherwise touch the payload of an occupied slot;
- not loop in `acquire` or `release`;
- not walk the free list in capacity helpers;
- not perform unconditional invariant scans on hot paths;
- avoid hidden globals, atomics, fences, syscalls, target probes, allocation;
- compile for freestanding targets.

## Usage

Static pool:

```zig
const Frame = struct { id: u32, data: [256]u8 };
var pool = stdx.mem.Pool.Static(Frame, 16).init();

const f = try pool.acquire();
f.* = .{ .id = 7, .data = undefined };
// … use f …
pool.release(f);
```

Bounded pool with caller storage:

```zig
const PoolT = stdx.mem.Pool.Bounded(Frame);
var storage: [16]PoolT.Slot = undefined;
var pool = PoolT.wrap(&storage);

const f = try pool.acquire();
f.* = .{ .id = 7, .data = undefined };
pool.release(f);
```

Bounded pool over arena storage:

```zig
var arena = stdx.mem.Arena.Static(4096).init();
const PoolT = stdx.mem.Pool.Bounded(Job);
const storage = try arena.allocSlice(PoolT.Slot, 64);
var jobs = PoolT.wrap(storage);
```

Exhaustion and reuse:

```zig
const PoolT = stdx.mem.Pool.Static(u32, 2);
var p = PoolT.init();
const a = try p.acquire();
const b = try p.acquire();
try std.testing.expectError(error.OutOfMemory, p.acquire());
p.release(a);
const c = try p.acquire(); // reuses a's slot (LIFO)
_ = b;
_ = c;
```

## Consumer requirements

- `zvm`: vCPU control blocks, event entries, identity records can sit in
  static or bounded pools without hot-path heap allocation.
- `zfw`: protocol-handle tables, request structures, packet descriptors that
  need pointer stability across firmware phases.
- `zacpi`: namespace nodes, table descriptors, parser scratch entries.

## Required tests

### Construction and capacity

- `Pool.Static(T, N).init()` reports `len == 0`, `capacity == N`,
  `remaining == N`;
- `Pool.Bounded(T).wrap(buffer)` reports `capacity == buffer.len`;
- `Pool.Static(T, 0).init()` is both empty and full; `acquire` returns
  `error.OutOfMemory`;
- `Pool.Bounded(T).wrap(&.{})` is both empty and full; `acquire` returns
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

- `Pool.Static(T, 1)` cycles through acquire/release without losing the
  slot;
- `Pool.Static(T, N).item_capacity == N`.

### Type identity

- `Pool.Bounded(A)` and `Pool.Bounded(B)` are distinct types for distinct
  `T`;
- `Pool.Static(T, M)` and `Pool.Static(T, N)` are distinct types for
  `M != N`.

## Open questions

None.
