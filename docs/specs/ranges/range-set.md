# Range set

Status: Approved.

`zstdx.ranges.RangeSet` is a fixed-capacity canonical set of unsigned half-open ranges. It stores `zstdx.core.Range(T)` values sorted by start, merges overlapping or adjacent ranges on insertion, and subtracts ranges with head/tail splitting on removal.

## Owned scope

This spec owns:

- `ranges.RangeSet` family namespace;
- `RangeSet.Static(T, N)` inline fixed-capacity storage;
- `RangeSet.Bounded(T)` caller-storage-backed fixed-capacity storage;
- canonical sorted, non-empty, non-overlapping, non-adjacent range storage;
- range union insertion;
- range subtraction removal;
- containment and overlap queries;
- deterministic iteration order through a const slice;
- capacity, invalidation, and full-capacity behavior;
- required tests.

This spec does not own:

- values attached to ranges; use `ranges.RangeMap` for that after its spec is approved;
- address-specific ranges;
- page-specific ranges;
- pointer spans or provenance;
- gap allocators;
- first-fit, best-fit, highest-fit, or alignment-aware allocation policy;
- memory classification such as usable RAM, reserved memory, MMIO, DMA eligibility, or firmware memory type;
- UEFI descriptors, attributes, GCD policy, map keys, or allocation services;
- MMIO/PIO handler dispatch;
- immutable owned frozen slices;
- managed or unmanaged heap allocation;
- interval trees, B-trees, radix trees, or crit-bit trees;
- concurrency or synchronization.

## Public namespace

`RangeSet` lives under `zstdx.ranges`:

```zig
zstdx.ranges.RangeSet
```

It is not root-promoted:

```zig
zstdx.RangeSet // not exported
```

Source ownership:

```text
src/ranges.zig
src/ranges/set.zig
test/ranges/set_test.zig
```

`src/ranges.zig` re-exports:

```zig
pub const set = @import("ranges/set.zig");

pub const RangeSet = set.RangeSet;
```

The package root may export the `ranges` namespace when `src/ranges.zig` lands, as governed by `docs/specs/root-exports.md`.

## Approved API

```zig
pub const RangeSet = struct {
    pub fn Static(comptime T: type, comptime capacity_ranges: usize) type;
    pub fn Bounded(comptime T: type) type;
};
```

`T` must be an unsigned integer type. Other types are compile errors because `RangeSet` stores `zstdx.core.Range(T)`.

### `Static` returned type

```zig
pub const Self = struct {
    buffer: [capacity_ranges]Range = undefined,
    count: usize = 0,

    pub const Range = zstdx.core.Range(T);
    pub const Error = error{ Full, InvalidRange };
    pub const range_capacity = capacity_ranges;

    pub fn init() Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn asConstSlice(self: *const Self) []const Range;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn insert(self: *Self, range: Range) Error!void;
    pub fn remove(self: *Self, range: Range) Error!void;

    pub fn contains(self: *const Self, value: T) bool;
    pub fn containsRange(self: *const Self, range: Range) bool;
    pub fn overlaps(self: *const Self, range: Range) bool;

    pub fn findContaining(self: *const Self, value: T) ?Range;
    pub fn findIntersecting(self: *const Self, range: Range) ?Range;

    pub fn assertValid(self: *const Self) void;
};
```

### `Bounded` returned type

```zig
pub const Self = struct {
    buffer: []Range,
    count: usize = 0,

    pub const Range = zstdx.core.Range(T);
    pub const Error = error{ Full, InvalidRange };

    pub fn wrap(buffer: []Range) Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn asConstSlice(self: *const Self) []const Range;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn insert(self: *Self, range: Range) Error!void;
    pub fn remove(self: *Self, range: Range) Error!void;

    pub fn contains(self: *const Self, value: T) bool;
    pub fn containsRange(self: *const Self, range: Range) bool;
    pub fn overlaps(self: *const Self, range: Range) bool;

    pub fn findContaining(self: *const Self, value: T) ?Range;
    pub fn findIntersecting(self: *const Self, range: Range) ?Range;

    pub fn assertValid(self: *const Self) void;
};
```

`Static` and `Bounded` have identical observable range semantics. They differ only in storage ownership.

## Type and capacity contract

`RangeSet` stores `zstdx.core.Range(T)` values.

A valid set satisfies:

```zig
count <= capacity()
```

For every stored range:

```zig
range.isValid()
!range.isEmpty()
```

Stored ranges are canonical. For adjacent stored entries:

```zig
items[i].end < items[i + 1].start
```

This strict inequality means stored ranges are sorted, non-overlapping, and non-adjacent. Adjacent inputs are coalesced because they represent one contiguous set of values.

`capacity_ranges == 0` and `Bounded.wrap(buffer[0..0])` are valid. A zero-capacity set is empty and full.

## Ownership and lifetime

`RangeSet.Static(T, N)` owns inline storage. Moving or copying the set value moves or copies the storage and current contents.

`RangeSet.Bounded(T)` borrows caller-owned `[]Range` storage. The caller must keep the buffer alive for the lifetime of the set and any slices returned by `asConstSlice`.

Copying a bounded set copies the slice pointer and `count`; it does not copy the backing storage. Divergent mutable copies over the same buffer are outside this primitive's contract. Use one authoritative mutable set value for each backing buffer.

Do not store a `RangeSet.Bounded` field that points at another field in the same outer struct. Moving the outer struct can leave the slice pointer referring to the old address. Use `RangeSet.Static` for embedded storage.

## Construction and clearing

`Static.init()` is equivalent to `.{}`. It creates an empty set with uninitialized spare storage.

`Bounded.wrap(buffer)` returns an empty set backed by `buffer`. `buffer.len` is the runtime range capacity.

`clearRetainingCapacity()` sets `count` to zero. It does not zero spare storage, release resources, or change capacity.

There is no `deinit` or `clearAndFree`; neither variant owns heap allocation.

## Capacity operations

`len()` returns the number of stored canonical ranges.

`capacity()` returns the maximum stored canonical range count.

`remaining()` returns `capacity() - len()`.

`isEmpty()` returns `len() == 0`.

`isFull()` returns `len() == capacity()`.

These operations do not inspect spare storage.

## Slice exposure

`asConstSlice()` returns the initialized canonical range prefix sorted by ascending `start`.

The returned slice is invalidated by any mutation that can change stored ranges, including `insert`, `remove`, and `clearRetainingCapacity`. Moving a static set invalidates slices into the old value. Mutating a bounded set can invalidate slices into its borrowed buffer.

There is no mutable slice exposure. Direct mutable access would allow callers to break canonical invariants.

## Insert semantics

`insert(range)` adds every value in `range` to the set.

If `range.isValid()` is false, `insert` returns `error.InvalidRange` and leaves the set unchanged.

If `range.isEmpty()` is true, `insert` succeeds and leaves the set unchanged.

Insertion coalesces every stored range that overlaps or is adjacent to the inserted range.

Examples:

```text
{} insert [10, 20)                    => {[10, 20)}
{[10, 20)} insert [20, 30)            => {[10, 30)}
{[10, 20)} insert [15, 25)            => {[10, 25)}
{[10, 20), [30, 40)} insert [18, 35) => {[10, 40)}
```

If the final canonical set needs more stored ranges than capacity allows, `insert` returns `error.Full` and leaves the set unchanged.

Insertion must check capacity before mutation when expansion is required. A failed insert must preserve the previous set exactly.

## Remove semantics

`remove(range)` subtracts every value in `range` from the set.

If `range.isValid()` is false, `remove` returns `error.InvalidRange` and leaves the set unchanged.

If `range.isEmpty()` is true, `remove` succeeds and leaves the set unchanged.

Removing a disjoint range succeeds and leaves the set unchanged.

Removal may delete, shrink, or split stored ranges.

Examples:

```text
{[10, 30)} remove [15, 20) => {[10, 15), [20, 30)}
{[10, 30)} remove [0, 20)  => {[20, 30)}
{[10, 30)} remove [30, 40) => {[10, 30)}
```

A middle removal can split one stored range into two stored ranges. If that split needs one extra slot and the set is full, `remove` returns `error.Full` and leaves the set unchanged.

Removal must check capacity before mutation when splitting is required. A failed remove must preserve the previous set exactly.

## Query semantics

Query methods require their `range` argument to be valid. Passing an invalid range to a query method is a programmer error and may assert.

`contains(value)` returns true when any stored range contains `value`.

`findContaining(value)` returns the stored range containing `value`, or `null` when no stored range contains it.

`containsRange(range)` returns true when the set contains every value in `range`.

For empty `range`, `containsRange` follows the `core.Range(T)` boundary convention: an empty range is contained when its point is inside a stored range or on a stored range boundary. An empty range in a gap is not contained.

`overlaps(range)` returns true when `range` has a non-empty intersection with any stored range. Empty ranges never overlap.

`findIntersecting(range)` returns the first stored range, in ascending order, that has a non-empty intersection with `range`, or `null` when there is no intersection.

## Ordering

Stored ranges are always exposed in ascending `start` order.

Operations must produce deterministic ordering independent of insertion order.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `Static.init` | never | never | O(1) | none | caller-owned value | none |
| `Bounded.wrap` | never | never | O(1) | none | caller-owned buffer | none |
| `len` | never | never | O(1) | none | caller-owned value | none |
| `capacity` | never | never | O(1) | none | caller-owned value | none |
| `remaining` | never | never | O(1) | none | caller-owned value | none |
| `isEmpty` | never | never | O(1) | none | caller-owned value | none |
| `isFull` | never | never | O(1) | none | caller-owned value | none |
| `asConstSlice` | never | never | O(1) | invalidated by mutation/move | caller-owned value | ascending range order |
| `clearRetainingCapacity` | never | never | O(1) | invalidates slices | caller-owned value | none |
| `insert` | never | never | O(n) | invalidates slices | caller-owned value | preserves ascending order |
| `remove` | never | never | O(n) | invalidates slices | caller-owned value | preserves ascending order |
| `contains` | never | never | O(log n) | none | caller-owned value | none |
| `containsRange` | never | never | O(log n) | none | caller-owned value | none |
| `overlaps` | never | never | O(log n) | none | caller-owned value | none |
| `findContaining` | never | never | O(log n) | none | caller-owned value | none |
| `findIntersecting` | never | never | O(log n) | none | caller-owned value | ascending first hit |
| `assertValid` | never | never | O(n) | none | caller-owned value | checks ascending order |

These operations perform no allocation, waiting, sleeping, spinning, hidden global access, atomics, barriers, syscalls, target probing, or architecture probing.

Concurrent mutation is outside the contract. Callers must externally synchronize shared mutable access. Immutable reads through an immutable set require no synchronization beyond ordinary Zig aliasing rules.

## Error behavior

- invalid `T` is a compile error;
- `insert` and `remove` return `error.InvalidRange` for invalid input ranges;
- `insert` returns `error.Full` when the canonical result needs more stored ranges than capacity;
- `remove` returns `error.Full` when a split needs an extra stored range and capacity is full;
- failed mutators leave the set unchanged;
- query methods may assert on invalid input ranges;
- methods that require a valid receiver may assert when internal invariants are broken.

## Debug assertion behavior

`assertValid()` checks:

- `count <= capacity()`;
- all stored ranges are valid;
- no stored range is empty;
- stored ranges are sorted by ascending `start`;
- stored ranges do not overlap;
- stored ranges are not adjacent;
- spare storage is not inspected.

Explicit `assertValid()` calls always perform the check.

Automatic invariant checks inside operations, if implemented, must be gated through `zstdx.core.debug.checksEnabled` when the operation exposes a `SafetyMode` option. This spec does not require `RangeSet` operations to expose a `SafetyMode` option.

Assertions document programmer errors and internal invariant failures. Malformed external ranges passed to `insert` or `remove` must return `error.InvalidRange`.

## Implementation constraints

Implementation must:

- use `zstdx.core.Range(T)` as the stored range value;
- reject non-unsigned `T` where practical through `Range(T)`;
- keep initialized ranges in `buffer[0..count]`;
- leave `buffer[count..]` as spare storage;
- never expose mutable range storage;
- preserve canonical invariants after every successful mutation;
- leave the set unchanged on `error.Full` and `error.InvalidRange`;
- precheck capacity before any mutation that may need more slots;
- use overlap-safe moves when shifting stored ranges;
- avoid loops proportional to the value domain size;
- use loops proportional only to stored range count;
- avoid hidden globals, allocation, atomics, fences, volatile operations, target probes, architecture probes, and I/O.

Implementation may use binary search for query start points and linear compaction/expansion for mutation.

## Usage

Static set:

```zig
const RangeSet = zstdx.ranges.RangeSet;
const Range = zstdx.core.Range(u64);

var used = RangeSet.Static(u64, 8).init();

try used.insert(try Range.fromBounds(10, 20));
try used.insert(try Range.fromBounds(20, 30));

// Canonical storage is now {[10, 30)}.
```

Bounded set:

```zig
const RangeSet = zstdx.ranges.RangeSet;

var backing: [16]RangeSet.Bounded(u64).Range = undefined;
var free = RangeSet.Bounded(u64).wrap(backing[0..]);

try free.insert(try free.Range.fromBounds(0, 100));
try free.remove(try free.Range.fromBounds(40, 60));

// Canonical storage is now {[0, 40), [60, 100)}.
```

Overlap validation policy remains caller-owned:

```zig
if (reserved.overlaps(candidate)) return error.OverlappingRange;
try reserved.insert(candidate);
```

Attached metadata belongs in `RangeMap`, not `RangeSet`:

```zig
// Not RangeSet-owned policy:
// - usable_ram versus reserved
// - free versus allocated
// - EfiMemoryType
// - MMIO handler pointer
```

## Required tests

Required for:

- `RangeSet.Static(u8, N)` with small capacity for split/full and model tests;
- `RangeSet.Static(u64, N)` for normal wide ranges;
- `RangeSet.Bounded(u64)` with caller-owned backing storage;
- zero-capacity `Static` and `Bounded` sets.

### Construction and capacity

- static init creates an empty set;
- bounded init creates an empty set over caller storage;
- zero capacity is valid, empty, and full;
- `len`, `capacity`, `remaining`, `isEmpty`, and `isFull` report correct values;
- `clearRetainingCapacity` empties without changing capacity.

### Insert

- inserting an empty range is a no-op;
- inserting into an empty set stores the range;
- inserting before existing ranges preserves sorted order;
- inserting after existing ranges preserves sorted order;
- inserting adjacent ranges coalesces;
- inserting overlapping ranges coalesces;
- inserting a range spanning multiple stored ranges coalesces all affected ranges;
- inserting a disjoint range at full capacity returns `error.Full` and leaves the set unchanged;
- inserting an invalid range returns `error.InvalidRange` and leaves the set unchanged.

### Remove

- removing an empty range is a no-op;
- removing a disjoint range is a no-op;
- removing an exact stored range deletes it;
- removing a prefix shrinks a range;
- removing a suffix shrinks a range;
- removing the middle splits a range;
- removing across multiple ranges deletes and shrinks affected ranges;
- removing the middle at full capacity returns `error.Full` and leaves the set unchanged;
- removing an invalid range returns `error.InvalidRange` and leaves the set unchanged.

### Queries

- `contains` includes starts and excludes ends;
- `contains` returns false for gaps;
- `findContaining` returns the expected stored range or `null`;
- `containsRange` returns true for fully covered ranges;
- `containsRange` returns false for partial coverage or gaps;
- `containsRange` handles empty ranges at stored boundaries and in gaps;
- `overlaps` rejects adjacent ranges and empty ranges;
- `findIntersecting` returns the first intersecting stored range in ascending order;
- `asConstSlice` returns canonical sorted ranges.

### Invariants and invalidation

- `assertValid` succeeds after every public mutation in deterministic tests;
- direct construction of an invalid receiver is detected by `assertValid` where practical;
- slices from `asConstSlice` reflect immutable order and are not used after mutation.

### Model tests

Randomized operation sequences over a small domain such as `u8` must compare `RangeSet` against a simple reference model.

Required model operations:

- insert random valid ranges;
- remove random valid ranges;
- compare every point's membership after each operation;
- compare canonical exported ranges against ranges reconstructed from the model bitset;
- include empty ranges, adjacent ranges, overlapping ranges, full-capacity cases, and boundary ranges at `0` and max tested value.

### Compile-time behavior

Where practical:

```zig
comptime {
    const Set = zstdx.ranges.RangeSet.Static(u8, 4);
    const Range = Set.Range;

    var set = Set.init();
    try set.insert(try Range.fromBounds(1, 3));
    try set.insert(try Range.fromBounds(3, 5));

    std.debug.assert(set.len() == 1);
    std.debug.assert(set.contains(4));
    std.debug.assert(!set.contains(5));
}
```

## Open questions

None.
