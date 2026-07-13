# Memory buddy allocator

Status: Approved.

`stdx.mem.BuddyAllocator` is a fixed-unit power-of-two buddy allocator over a
caller-supplied backing region. It manages abstract unit indexes at multiple
orders, splits blocks on demand, and coalesces buddies eagerly on `free`. It
does not own the resources those indexes name.

The allocator is for page frames, DMA regions, guest-page tables, descriptor
groups, and any resource domain where the allocation grain is a power-of-two
count of fixed units. It never allocates backing memory and never performs
domain-specific policy.

## Owned scope

This spec owns:

- `mem.BuddyAllocator.Static(unit_capacity, order_count)`;
- `mem.BuddyAllocator.Bounded`;
- per-order bitmap free-list discipline over caller-provided backing words;
- `alloc`/`free`/`reserve` semantics with the shared
  `algo.allocation.Buddy.Block` value shape;
- eager on-`free` coalescing;
- deterministic lowest-index split-and-place policy;
- exhaustion, bounds, order-range, invalid-request, double-reserve, and
  double-free behavior;
- no-mutation-on-error behavior;
- structural invariants and `assertValid` contract;
- required tests (unit, model, stress).

## Deferred scope and non-goals

This spec does not own:

- byte-level allocation; `alloc` returns `Buddy.Block` values, never `*u8`;
- page-size policy, page-frame types, physical or virtual address translation;
- NUMA locality, per-CPU caches, or hot-path per-order counters;
- dynamic backing growth or shrinkage;
- coalesce policies other than eager on `free`;
- defragmentation, compaction, or page migration;
- concurrency, atomics, locking, or wait behavior;
- iteration over live allocations, watermarks, statistics, or tracing;
- automatic zeroing or poisoning of allocated regions;
- alignment override, generation counts, or handle stability guarantees
  across `free`;
- `std.mem.Allocator` views — this is not a byte allocator;
- root promotion of `BuddyAllocator`.

## Public namespace

`BuddyAllocator` lives under `stdx.mem`:

```zig
stdx.mem.BuddyAllocator
stdx.mem.BuddyAllocator.Static
stdx.mem.BuddyAllocator.Bounded
```

It is not root-promoted:

```zig
stdx.BuddyAllocator // not exported
```

Source ownership:

```text
src/mem.zig
src/mem/buddy.zig
test/mem/buddy_test.zig
```

`src/mem.zig` re-exports:

```zig
pub const buddy = @import("mem/buddy.zig");

pub const BuddyAllocator = buddy.BuddyAllocator;
```

## Approved API

```zig
pub const BuddyAllocator = struct {
    pub fn Static(comptime unit_capacity: usize, comptime order_count: u8) type;

    pub const Bounded = struct {
        words: []Word,
        unit_capacity: usize,
        order_count: u8,

        pub const Word = u64;
        pub const word_bits = @bitSizeOf(Word);
        pub const Block = stdx.algo.allocation.Buddy.Block;
        pub const Range = stdx.core.Range(usize);
        pub const Error = error{
            OutOfMemory,
            OutOfBounds,
            InvalidOrder,
            InvalidRequest,
            AlreadyAllocated,
            NotAllocated,
        };

        pub fn wrap(words: []Word, unit_capacity: usize, order_count: u8) Error!Bounded;
        pub fn clearRetainingCapacity(self: *Bounded) void;

        pub fn capacity(self: Bounded) usize;
        pub fn orderCount(self: Bounded) u8;
        pub fn maxOrder(self: Bounded) u8;
        pub fn allocatedUnits(self: Bounded) usize;
        pub fn remainingUnits(self: Bounded) usize;

        pub fn alloc(self: *Bounded, order: u8) Error!Block;
        pub fn free(self: *Bounded, block: Block) Error!void;
        pub fn reserve(self: *Bounded, range: Range) Error!void;

        pub fn isFreeBlock(self: Bounded, block: Block) bool;

        pub fn isValid(self: Bounded) bool;
        pub fn assertValid(self: Bounded) void;
    };
};
```

`Static(unit_capacity, order_count)` returns a type with inline word storage
and the same query, allocation, reserve, free, validation, and clear
operations as `Bounded`. It uses `init()` as its constructor instead of
`wrap(...)`:

```zig
pub const Self = struct {
    words: [word_count]Word = [_]Word{0} ** word_count,

    pub const Word = u64;
    pub const word_bits = @bitSizeOf(Word);
    pub const Block = stdx.algo.allocation.Buddy.Block;
    pub const Range = stdx.core.Range(usize);
    pub const Error = BuddyAllocator.Bounded.Error;

    pub const unit_capacity_const: usize = unit_capacity;
    pub const order_count_const: u8 = order_count;
    pub const max_order_const: u8 = order_count - 1;
    pub const word_count: usize = /* required_word_count(unit_capacity, order_count) */;

    pub fn init() Self;

    // Same non-construction methods as BuddyAllocator.Bounded.
};
```

There is no `Static.wrap` and no `Bounded.init` — construction shape is
deliberately split.

There is no byte-level `alloc`, no `[]u8` return, no `*T` conversion, and no
`std.mem.Allocator` interface. `Block` values are unit-indexed and the caller
translates to whatever domain they own.

## Unit and block model

A unit is an abstract resource slot identified by an index in
`[0, unit_capacity)`.

An allocation is a `Buddy.Block`:

```zig
Block{ .start = start_unit, .order = order }
```

where `start_unit` is aligned to `1 << order` and the block covers
`[start_unit, start_unit + (1 << order))`.

Order names a block size in units:

```text
size_units(order) = 1 << order
```

`Buddy.Block`, `Buddy.blockSize`, `Buddy.buddyOf`, `Buddy.parentOf`,
`Buddy.split`, and `Buddy.canCoalesce` come from
`docs/specs/algo/allocation.md` and are used verbatim. This spec does not
redefine them.

The allocator does not know what a unit represents. A unit may name a page
frame, a table entry, a memory-map slot, a descriptor block, or any other
fixed-size resource chosen by the caller. Consumers translate `usize` unit
indexes to their domain externally:

```zig
// 4 KiB page frames, unit-0 == one frame:
const phys = base_phys.add(block.start * page_size);

// 4 KiB base with orders 0/9/18 for 4 KiB / 2 MiB / 1 GiB pages:
const bytes = block.start * page_size;
const nbytes = (@as(usize, 1) << block.order) * page_size;
```

## Storage model

`Static(unit_capacity, order_count)` owns inline bitmap words. A default
struct literal and `init()` both produce a fresh allocator whose free state
covers `[0, unit_capacity)`.

`Bounded.wrap(words, unit_capacity, order_count)` borrows `words`, clears
every borrowed word, populates the initial free-block decomposition, and
returns the allocator. It returns `error.InvalidRequest` when the constraints
in `wrap` semantics below are violated.

Direct mutation of `words` outside the allocator's public methods breaks the
free-list invariants and is a caller contract violation. `assertValid`
diagnoses the common failure modes.

### Bitmap layout

Free state is tracked as one bit per unit-`(1 << k)` slot at each order `k`
in `0..order_count`. Bit `b` of order `k` is `1` when a same-order block
starting at unit `b * (1 << k)` is currently free.

`required_word_count(unit_capacity, order_count)` = sum over `k` of
`ceilDiv(ceilDiv(unit_capacity, 1 << k), word_bits)` words. The exact word
count is what `Static.word_count` reports and what `Bounded.wrap` requires
`words.len` to be at least.

Bits beyond the logical per-order length are unused. Public operations
preserve the "unused high bits are zero" invariant.

## Capacity, counts, and clearing

`capacity()` returns the fixed unit capacity.

`orderCount()` returns the number of orders. `maxOrder()` returns
`order_count - 1`.

`allocatedUnits()` returns the number of currently-allocated units.

`remainingUnits()` returns `capacity() - allocatedUnits()`.

`clearRetainingCapacity()` restores the initial fully-free decomposition
without releasing the borrowed backing storage.

## `wrap` semantics

`Bounded.wrap(words, unit_capacity, order_count)` returns
`error.InvalidRequest` when:

- `order_count == 0`;
- `order_count > 32`;
- `unit_capacity == 0`;
- `unit_capacity > (std.math.maxInt(usize) >> (order_count - 1))` — the
  largest addressable block would overflow `usize`;
- `words.len < required_word_count(unit_capacity, order_count)`.

On success, `wrap` clears every borrowed word and installs the fully-free
initial decomposition described in "Initial decomposition" below. It does not
mutate the input on error.

## `Static` compile-time constraints

`Static(unit_capacity, order_count)` is a `@compileError` when:

- `order_count == 0`;
- `order_count > 32`;
- `unit_capacity == 0`;
- `unit_capacity > (std.math.maxInt(usize) >> (order_count - 1))`.

The error messages name the offending parameter.

## Initial decomposition

After `init()` or `wrap`, the allocator's free state covers `[0, capacity())`
with the largest fitting blocks at the highest orders:

- while at least `1 << max_order` units remain uncovered, mark one order-
  `max_order` block at the current cursor and advance the cursor by
  `1 << max_order`;
- otherwise, if at least `1 << k` units remain, mark one order-`k` block and
  advance by `1 << k`; repeat with the largest remaining fitting order.

This is the standard buddy-build decomposition of a possibly non-power-of-two
range into a sequence of aligned power-of-two blocks. It is unique for a
given `(capacity, order_count)` pair.

## `alloc(order)` semantics

`alloc(order)` allocates the lowest-index free block of exactly order `order`
and returns it.

Logic:

1. Return `error.InvalidOrder` when `order >= order_count`. No mutation.
2. If a same-order free block exists, clear its bit and return
   `Block{ .start, .order }` for the lowest-index such block.
3. Otherwise, find the lowest-index free block at any order `order + 1
   .. maxOrder()`. If none exists, return `error.OutOfMemory`. No mutation.
4. Otherwise, split repeatedly from that higher order down to `order`:
   - `let (left, right) = Buddy.split(current);`
   - mark the right child free in its order's bitmap;
   - continue with `left` as `current` until `current.order == order`.
   Return `current`.

The lowest-source-order tie-break in step 3 keeps splits shallow and
deterministic. Splitting itself uses `algo.allocation.Buddy.split`, which
never fails for `order >= 1`.

## `free(block)` semantics — eager coalesce

`free(block)` returns the block to the free pool and coalesces with its
buddy while the buddy is also free.

Logic:

1. Return `error.InvalidOrder` when `block.order >= order_count`. No
   mutation.
2. Return `error.InvalidRequest` when
   `block.start % (1 << block.order) != 0` or
   `block.start + (1 << block.order) > unit_capacity`. No mutation.
3. Return `error.NotAllocated` when the corresponding bitmap bit at
   `(block.order, block.start >> block.order)` is already set — that means
   the caller is freeing a block that is currently free (double-free). No
   mutation.
4. While `block.order < maxOrder()`:
   - compute `buddy := Buddy.buddyOf(block)`;
   - if `buddy` is free at `block.order` in the bitmap, clear the buddy's
     bit and set `block := Buddy.parentOf(block)`;
   - otherwise break.
5. Set the bit for `(block.order, block.start >> block.order)`.

Under `stdx.core.debug.checksEnabled(.build_mode)`, `free` asserts after
step 5 that no two same-order buddies are both free — a violation would mean
step 4 missed a coalesce and is a bug in this primitive rather than in the
caller.

## `reserve(range)` semantics

`reserve(range)` marks every unit in `range` unavailable to future `alloc`
calls. It may be called at any time on any allocator state.

Logic:

1. Return `error.InvalidRequest` when `range` is not a valid `Range`. No
   mutation.
2. Return `error.OutOfBounds` when `range.end > unit_capacity`. No mutation.
3. Walk `range` and confirm every unit is currently free; if any unit is
   already allocated, return `error.AlreadyAllocated`. No mutation.
4. For each unit in `range`, split its containing free block down to
   order 0 (marking the non-reserved siblings free at each step), then
   clear the order-0 bit for that unit.

The validate-then-commit split in steps 3 and 4 preserves no-mutation-on-
error semantics. An empty range with `range.start <= unit_capacity` is a
no-op.

`reserve` is not more efficient than allocating individual order-0 blocks
covering the same span, but it consumes no `alloc` return values and
never introduces a `Block` handle the caller would need to hold. Reserved
units remain unavailable to `alloc` until the caller `free`s the containing
order-0 blocks they can synthesize themselves (with the free-order
invariant).

## `isFreeBlock(block)` semantics

`isFreeBlock(block)` returns `true` when `block.order < order_count`,
`block.start` is `(1 << block.order)`-aligned,
`block.start + (1 << block.order) <= unit_capacity`, and the corresponding
bitmap bit is set. It returns `false` otherwise.

`isFreeBlock` is a query and never mutates the allocator.

## Free-order invariant

The caller must pass a `block` value to `free` whose `(start, order)` pair
exactly matches what `alloc` returned. Passing a `block` with a different
order — even one aligned to that order and inside the allocator's range — is
a caller contract violation.

Under `stdx.core.debug.checksEnabled(.build_mode)`:

- `free` traps when `block.start % (1 << block.order) != 0`;
- `free` traps when the bit is already set (double-free);
- `assertValid` fails when the free-list state is internally inconsistent.

In release builds without `checksEnabled`, `free` returns `error.NotAllocated`
on double-free and `error.InvalidRequest` on unaligned starts, both without
mutation. Passing a `block` with a start aligned to a different order but
matching a currently-allocated block at that other order is undefined
behavior; the primitive does not defend against this case.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `Static(...)` | never | never | comptime | type factory | none | `@compileError` on invalid params |
| `wrap` | never | never | O(order_count) | single-owner | none | `InvalidRequest` |
| `clearRetainingCapacity` | never | never | O(order_count · words) | single-owner | none | infallible |
| `capacity` / `orderCount` / `maxOrder` | never | never | O(1) | value type | none | infallible |
| `allocatedUnits` / `remainingUnits` | never | never | O(order_count · words) | reader | none | infallible |
| `alloc` | never | never | O(order_count · words) | single-owner | none | `OutOfMemory` / `InvalidOrder`; no-mutation-on-error |
| `free` | never | never | O(order_count) | single-owner | none | `NotAllocated` / `InvalidRequest` / `InvalidOrder`; no-mutation-on-error |
| `reserve` | never | never | O(range.len · order_count) | single-owner | none | `OutOfBounds` / `AlreadyAllocated` / `InvalidRequest`; no-mutation-on-error |
| `isFreeBlock` | never | never | O(1) | reader | none | infallible |
| `isValid` / `assertValid` | never | never | O(order_count · words) | reader | none | infallible / traps on invalid |

`BuddyAllocator` performs no heap allocation, sleeping, blocking, hidden
scheduler calls, target probing, atomics, barriers, or hidden global access.
Every state-changing operation requires exclusive ownership; concurrent
callers must serialize externally.

## Debug assertion behavior

`stdx.core.debug.checksEnabled(.build_mode)` gates:

- `free`'s trap on unaligned `block.start`;
- `free`'s trap on double-free (bit already set) instead of the release-mode
  `error.NotAllocated`;
- the post-`free` invariant check that no same-order buddies are both free;
- `alloc`'s post-condition that the returned block's bit is now clear.

`assertValid()` runs unconditionally when called. Common structural failures
it catches:

- `order_count == 0`, `order_count > 32`, or
  `unit_capacity > (maxInt(usize) >> (order_count - 1))`;
- `words.len < required_word_count(unit_capacity, order_count)`;
- a same-order buddy pair both marked free;
- unused high bits set in any order's tail word;
- `allocatedUnits() + remainingUnits() != capacity()`.

`isValid()` returns whether the same conditions hold, without trapping.

## `std.Io` lane

`BuddyAllocator` serves both lanes declared in the spec queue:

1. Composes inside a downstream `std.Io` backend implementation (e.g. a
   hosted physical-memory allocator wrapping this allocator behind
   `Io.Threaded`), by owning the state that the backend surfaces.
2. Serves freestanding consumers directly — kernel physical-memory maps,
   hypervisor guest-page-table allocators, firmware pre-runtime allocators
   — against caller-provided backing words.

Distinct from `std.heap.*`: byte-granular std allocators have hidden
allocation, no explicit unit/order concept, and no split/coalesce policy.
Distinct from `std.bit_set.IntegerBitSet`: no allocation state or split/
coalesce; a bit set is not an allocator.

## Examples

Physical-frame allocator with a small three-order allocator:

```zig
const stdx = @import("stdx");

const Buddy = stdx.mem.BuddyAllocator.Static(64, 4); // 64 frames, orders 0..3

var frames: Buddy = .init();

// Reserve firmware-owned frames [0, 4).
try frames.reserve(Buddy.Range.fromBounds(0, 4) catch unreachable);

// Allocate an order-2 block (4 contiguous frames).
const region = try frames.alloc(2);
defer frames.free(region) catch unreachable;

const phys = base_phys.add(region.start * page_size);
_ = phys;
```

Bounded variant over caller-owned words:

```zig
var backing: [64]stdx.mem.BuddyAllocator.Bounded.Word = @splat(0);
var frames = try stdx.mem.BuddyAllocator.Bounded.wrap(&backing, 128, 5);

const big = try frames.alloc(4); // 16 units
try frames.free(big);
```

## Required tests

Tests live in `test/mem/buddy_test.zig`. Unit tests use small parameters;
model tests compare against a naive reference; stress tests exercise
random-op sequences.

### `Static(...)` factory

- `Static(16, 5)` compiles.
- `Static(0, 5)`, `Static(16, 0)`, `Static(16, 33)`, and
  `Static(std.math.maxInt(usize), 5)` are compile errors.
- `Static(16, 5).unit_capacity_const == 16`,
  `Static(16, 5).order_count_const == 5`, and
  `Static(16, 5).max_order_const == 4`.
- `@sizeOf(Static(16, 5)) > 0` and `@sizeOf(Static(16, 5)) < @sizeOf([16]u64)`.

### `wrap` behavior

- `wrap` succeeds with `unit_capacity = 16, order_count = 5` and sufficient
  words.
- `wrap` returns `error.InvalidRequest` on `unit_capacity = 0`,
  `order_count = 0`, `order_count = 33`, or insufficient
  `words.len`.
- `wrap` clears every borrowed word before installing the initial
  decomposition.

### Initial decomposition

- `init()` on `Static(1, 1)` yields `isFreeBlock({0, 0}) == true` and
  `maxOrder() == 0`.
- `init()` on `Static(8, 4)` yields `isFreeBlock({0, 3}) == true` and no
  free blocks at lower orders.
- `init()` on `Static(12, 4)` (non-power-of-two capacity) yields
  `isFreeBlock({0, 3}) == true` and `isFreeBlock({8, 2}) == true`, with no
  other free blocks.

### `alloc` / `free` round-trip

- On `Static(16, 5)`, `alloc(0)` returns `Block{0, 0}` and reduces
  `remainingUnits` by 1.
- `alloc(maxOrder())` returns the top block.
- Successive `alloc(0)` calls return `{0,0}, {1,0}, {2,0}, ...` on a fully-
  free allocator.
- Every `alloc(order)` returns a `Block` whose `start` is `(1 << order)`
  -aligned.
- `alloc → free → alloc` returns the same block for the same order sequence.

### Splitting behavior

- `Static(8, 4)`: `alloc(0)` returns `{0, 0}`. Post-alloc, `isFreeBlock`
  reports `{1, 0}`, `{2, 1}`, `{4, 2}` free and no others.
- Post-`alloc(0)`, `alloc(0)` returns `{1, 0}`.
- Post-`alloc(0)`, `alloc(1)` returns `{2, 1}`.
- Post-`alloc(0)`, `alloc(2)` returns `{4, 2}`.

### Eager coalescing

- `Static(8, 4)`: allocate `{0,0}, {1,0}, {2,1}, {4,2}` (allocator now full).
- `free({0,0})` marks `{0,0}` free.
- `free({1,0})` triggers coalesce → `{0,1}` free.
- `free({2,1})` triggers coalesce → `{0,2}` free.
- `free({4,2})` triggers coalesce → `{0,3}` free (top-level restored).
- `allocatedUnits() == 0` and `alloc(3)` succeeds returning `{0,3}`.

### Non-coalescing when buddy is allocated

- After `alloc({0,0}); alloc({1,0}); alloc({2,0})`, `free({0,0})` marks
  `{0,0}` free but does NOT coalesce because `{1,0}` is allocated.

### `OutOfMemory`

- `Static(4, 3)`: allocate the two order-1 blocks; next `alloc(1)` returns
  `error.OutOfMemory`; state unchanged.
- After exhausting all orders, `alloc(0)` also returns `error.OutOfMemory`.

### `InvalidOrder`

- `alloc(order_count_const)` returns `error.InvalidOrder`; no mutation.
- `free(Block{ .start = 0, .order = order_count_const })` returns
  `error.InvalidOrder`; no mutation.

### `reserve`

- On `Static(8, 4)`, `reserve(Range.fromBounds(3, 5))` succeeds. Subsequent
  `alloc(0)` returns `{0,0}`, `{1,0}`, `{2,0}`, then `{5,0}` (units 3–4
  reserved).
- `reserve(Range.fromBounds(0, 9))` on `Static(8, 4)` returns
  `error.OutOfBounds`; no mutation.
- After `alloc({0,0})`, `reserve(Range.fromBounds(0, 2))` returns
  `error.AlreadyAllocated`; state unchanged (verified by then successfully
  reserving `Range.fromBounds(1, 2)`).
- `reserve(Range.empty(5))` is a no-op when `5 <= unit_capacity`.
- `reserve` at any time (not init-only): after several `alloc`/`free`
  round-trips, a subsequent `reserve` on a currently-free span succeeds.

### No-mutation-on-error

- Model test: for each error path (`OutOfMemory`, `NotAllocated`,
  `AlreadyAllocated`, `OutOfBounds`, `InvalidRequest`, `InvalidOrder`)
  snapshot `allocatedUnits`, `remainingUnits`, and the raw `words` array
  before the failing call and compare after.

### Debug assertions

- Under `checksEnabled(.build_mode)`, `free(Block{ .start = 1, .order = 1 })`
  (start not `(1 << 1)`-aligned) traps.
- Under `checksEnabled`, double-free traps instead of returning
  `error.NotAllocated`.
- Under `checksEnabled`, no test path observes two same-order buddies both
  free after any `free` (invariant checker inside `free`).
- Under `checksEnabled == false`, double-free returns `error.NotAllocated`
  and unaligned-start `free` returns `error.InvalidRequest`.

### `isValid` / `assertValid`

- Fresh `Static` / `Bounded` values are `isValid() == true`.
- Values with a manually mutated bitmap that marks both order-`k` buddies
  free fail `isValid()`; `assertValid()` traps.
- Values with `unit_capacity > (maxInt(usize) >> (order_count - 1))`
  (constructed via test-only backdoor) fail `isValid()`.

### Model test

Reference implementation: `[]bool` per unit tracking free/allocated, and a
naive "find lowest-index aligned power-of-two run" allocator.

- Random-op sequence over `alloc`/`free`/`reserve` (valid inputs only).
- Assert allocator state matches the reference bit-for-bit after every op.
- Assert no same-order buddy pair is both free at any point.
- Parameter grid: `unit_capacity ∈ {1, 4, 8, 16, 64}` and
  `order_count ∈ {1, 2, 3, 5}`.

### Stress test

- 10 000 random ops over `unit_capacity = 256, order_count = 6`.
- Every op is checked against the reference; the reference tracks a
  histogram of live block orders; on completion the allocator restored to
  fully free must equal `init()`.

### Compile-only

- `Block = stdx.algo.allocation.Buddy.Block` (identity comparison of the
  types).
- `Static(1, 1)` compiles and yields a degenerate one-block allocator.
- Non-x86 build compiles the module.

## Open questions

None.
