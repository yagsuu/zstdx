# Range map

Status: Approved.

`stdx.ranges.RangeMap` is a fixed-capacity sorted map from unsigned half-open ranges to caller-defined values. It stores `stdx.core.Range(T)` plus `V` entries, rejects overlapping inserts, supports overwrite-style assignment and range removal with splitting, and leaves value equality/coalescing policy explicit.

## Owned scope

This spec owns:

- `ranges.RangeMap` family namespace;
- `RangeMap.Static(T, V, N)` inline fixed-capacity storage;
- `RangeMap.Bounded(T, V)` caller-storage-backed fixed-capacity storage;
- sorted, non-empty, non-overlapping range-to-value entries;
- overlap-rejecting insertion;
- overwrite-style range assignment;
- range removal with head/tail splitting;
- explicit adjacent-entry coalescing with caller-supplied equality;
- point and range lookup queries;
- deterministic iteration order through a const slice;
- capacity, invalidation, and full-capacity behavior;
- required tests.

This spec does not own:

- automatic coalescing by default;
- hidden value equality, hashing, comparison, or destructors;
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

`RangeMap` lives under `stdx.ranges`:

```zig
stdx.ranges.RangeMap
```

It is not root-promoted:

```zig
stdx.RangeMap // not exported
```

Source ownership:

```text
src/ranges.zig
src/ranges/map.zig
test/ranges/map_test.zig
```

`src/ranges.zig` re-exports:

```zig
pub const map = @import("ranges/map.zig");

pub const RangeMap = map.RangeMap;
```

The package root may export the `ranges` namespace when `src/ranges.zig` lands, as governed by `docs/specs/root-exports.md`.

## Approved API

```zig
pub const RangeMap = struct {
    pub fn Static(comptime T: type, comptime V: type, comptime capacity_entries: usize) type;
    pub fn Bounded(comptime T: type, comptime V: type) type;
};
```

`T` must be an unsigned integer type. Other key-domain types are compile errors because `RangeMap` stores `stdx.core.Range(T)`.

`V` must be a runtime value type with `@sizeOf(V) > 0`. Zero-sized value types are compile errors where practical.

### `Static` returned type

```zig
pub const Self = struct {
    buffer: [capacity_entries]Entry = undefined,
    count: usize = 0,

    pub const Range = stdx.core.Range(T);

    pub const Entry = struct {
        range: Range,
        value: V,
    };

    pub const Error = error{ Full, InvalidRange, Overlap };
    pub const UpdateError = error{ Full, InvalidRange };
    pub const entry_capacity = capacity_entries;

    pub fn init() Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn asConstSlice(self: *const Self) []const Entry;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn insert(self: *Self, range: Range, value: V) Error!void;
    pub fn assign(self: *Self, range: Range, value: V) UpdateError!void;
    pub fn remove(self: *Self, range: Range) UpdateError!void;

    pub fn coalesceAdjacent(
        self: *Self,
        context: anytype,
        comptime eql: stdx.core.Eql(@TypeOf(context), V),
    ) void;

    pub fn contains(self: *const Self, value: T) bool;
    pub fn get(self: *const Self, value: T) ?*const V;

    pub fn containsRange(self: *const Self, range: Range) bool;
    pub fn overlaps(self: *const Self, range: Range) bool;

    pub fn findContaining(self: *const Self, value: T) ?*const Entry;
    pub fn findIntersecting(self: *const Self, range: Range) ?*const Entry;

    pub fn assertValid(self: *const Self) void;
};
```

### `Bounded` returned type

```zig
pub const Self = struct {
    buffer: []Entry,
    count: usize = 0,

    pub const Range = stdx.core.Range(T);

    pub const Entry = struct {
        range: Range,
        value: V,
    };

    pub const Error = error{ Full, InvalidRange, Overlap };
    pub const UpdateError = error{ Full, InvalidRange };

    pub fn wrap(buffer: []Entry) Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn asConstSlice(self: *const Self) []const Entry;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn insert(self: *Self, range: Range, value: V) Error!void;
    pub fn assign(self: *Self, range: Range, value: V) UpdateError!void;
    pub fn remove(self: *Self, range: Range) UpdateError!void;

    pub fn coalesceAdjacent(
        self: *Self,
        context: anytype,
        comptime eql: stdx.core.Eql(@TypeOf(context), V),
    ) void;

    pub fn contains(self: *const Self, value: T) bool;
    pub fn get(self: *const Self, value: T) ?*const V;

    pub fn containsRange(self: *const Self, range: Range) bool;
    pub fn overlaps(self: *const Self, range: Range) bool;

    pub fn findContaining(self: *const Self, value: T) ?*const Entry;
    pub fn findIntersecting(self: *const Self, range: Range) ?*const Entry;

    pub fn assertValid(self: *const Self) void;
};
```

`Static` and `Bounded` have identical observable map semantics. They differ only in storage ownership.

## Type and capacity contract

A `RangeMap` entry stores a `stdx.core.Range(T)` and one `V` value.

A valid map satisfies:

```zig
count <= capacity()
```

For every stored entry:

```zig
entry.range.isValid()
!entry.range.isEmpty()
```

Stored entries are sorted and non-overlapping. For adjacent stored entries:

```zig
items[i].range.end <= items[i + 1].range.start
```

Equality is allowed. Adjacent entries are valid and are not coalesced unless the caller explicitly requests coalescing.

`capacity_entries == 0` and `Bounded.wrap(buffer[0..0])` are valid. A zero-capacity map is empty and full.

## Value ownership and lifetime

`RangeMap` stores `V` by value. It copies `V` into entries during `insert` and `assign`.

`RangeMap` never calls destructors, deinitializers, close functions, release hooks, or callbacks for stored values. If `V` contains pointers, handles, descriptors, or owned resources, the caller owns those resource lifetimes.

When entries are removed, overwritten, shifted, or coalesced, removed `V` values become ordinary overwritten/dropped Zig values. Callers must not store resource-owning values unless that drop behavior is acceptable or externally managed.

## Ownership and lifetime

`RangeMap.Static(T, V, N)` owns inline entry storage. Moving or copying the map value moves or copies the storage and current entries.

`RangeMap.Bounded(T, V)` borrows caller-owned `[]Entry` storage. The caller must keep the buffer alive for the lifetime of the map and any slices or pointers returned by `asConstSlice`, `get`, `findContaining`, or `findIntersecting`.

Copying a bounded map copies the slice pointer and `count`; it does not copy the backing storage. Divergent mutable copies over the same buffer are outside this primitive's contract. Use one authoritative mutable map value for each backing buffer.

Do not store a `RangeMap.Bounded` field that points at another field in the same outer struct. Moving the outer struct can leave the slice pointer referring to the old address. Use `RangeMap.Static` for embedded storage.

## Construction and clearing

`Static.init()` is equivalent to `.{}`. It creates an empty map with uninitialized spare storage.

`Bounded.wrap(buffer)` returns an empty map backed by `buffer`. `buffer.len` is the runtime entry capacity.

`clearRetainingCapacity()` sets `count` to zero. It does not zero spare storage, release resources, deinitialize values, or change capacity.

There is no `deinit` or `clearAndFree`; neither variant owns heap allocation.

## Capacity operations

`len()` returns the number of stored entries.

`capacity()` returns the maximum stored entry count.

`remaining()` returns `capacity() - len()`.

`isEmpty()` returns `len() == 0`.

`isFull()` returns `len() == capacity()`.

These operations do not inspect spare storage.

## Slice and pointer exposure

`asConstSlice()` returns the initialized entry prefix sorted by ascending `range.start`.

`get(value)` returns a pointer to the value in the entry containing `value`, or `null`.

`findContaining(value)` returns a pointer to the entry containing `value`, or `null`.

`findIntersecting(range)` returns a pointer to the first intersecting entry in ascending order, or `null`.

Returned pointers and slices are invalidated by any mutation that can change entries, including `insert`, `assign`, `remove`, `coalesceAdjacent`, and `clearRetainingCapacity`. Moving a static map invalidates pointers and slices into the old value. Mutating a bounded map can invalidate pointers and slices into its borrowed buffer.

There is no mutable pointer or mutable slice exposure. Direct mutable access would allow callers to break sorted and non-overlap invariants and would bypass explicit value replacement semantics.

## Insert semantics

`insert(range, value)` adds one new mapping and rejects overlap.

If `range.isValid()` is false, `insert` returns `error.InvalidRange` and leaves the map unchanged.

If `range.isEmpty()` is true, `insert` succeeds and leaves the map unchanged. The `value` argument is not stored.

If `range` overlaps any existing entry, `insert` returns `error.Overlap` and leaves the map unchanged.

Adjacent ranges are allowed and are not coalesced:

```text
{[10, 20)=A} insert [20, 30)=A => {[10, 20)=A, [20, 30)=A}
```

If the map is full and insertion would need one more entry, `insert` returns `error.Full` and leaves the map unchanged.

Error precedence:

1. invalid range;
2. empty range no-op success;
3. overlap;
4. full capacity.

## Assign semantics

`assign(range, value)` overlays one mapping across `range`.

If `range.isValid()` is false, `assign` returns `error.InvalidRange` and leaves the map unchanged.

If `range.isEmpty()` is true, `assign` succeeds and leaves the map unchanged. The `value` argument is not stored.

Assignment removes or trims every entry intersecting `range`, preserves head and tail fragments outside `range`, and inserts one entry exactly covering `range` with `value`.

Examples:

```text
{} assign [10, 20)=A
=> {[10, 20)=A}

{[0, 10)=A, [20, 30)=B} assign [5, 25)=C
=> {[0, 5)=A, [5, 25)=C, [25, 30)=B}

{[0, 100)=A} assign [25, 75)=B
=> {[0, 25)=A, [25, 75)=B, [75, 100)=A}
```

Assignment does not automatically coalesce adjacent equal values. Call `coalesceAdjacent` when that policy is wanted.

If the final entry count would exceed capacity, `assign` returns `error.Full` and leaves the map unchanged.

Assignment must compute capacity requirements before mutation when expansion is possible. A failed assignment must preserve the previous map exactly.

## Remove semantics

`remove(range)` deletes every mapping over `range`.

If `range.isValid()` is false, `remove` returns `error.InvalidRange` and leaves the map unchanged.

If `range.isEmpty()` is true, `remove` succeeds and leaves the map unchanged.

Removing a disjoint range succeeds and leaves the map unchanged.

Removal may delete, shrink, or split entries.

Examples:

```text
{[10, 30)=A} remove [15, 20)
=> {[10, 15)=A, [20, 30)=A}

{[10, 30)=A} remove [0, 20)
=> {[20, 30)=A}

{[10, 30)=A} remove [30, 40)
=> {[10, 30)=A}
```

A middle removal can split one entry into two entries. If that split needs one extra slot and the map is full, `remove` returns `error.Full` and leaves the map unchanged.

Removal must check capacity before mutation when splitting is required. A failed remove must preserve the previous map exactly.

There is no `error.NotFound`; removing a disjoint range is a successful no-op.

## Explicit coalescing

`coalesceAdjacent(context, eql)` merges adjacent entries when their values compare equal with the caller-supplied equality callback.

It is equivalent to scanning entries in ascending order and merging neighbors where:

```zig
left.range.end == right.range.start and eql(context, &left.value, &right.value)
```

The merged entry uses:

```zig
range = [left.range.start, right.range.end)
value = left.value
```

The right value is removed as an ordinary stored value; `RangeMap` does not deinitialize it.

`coalesceAdjacent` never allocates, never fails, and never increases `len()`.

`context` is borrowed only for the duration of the call and is not stored. The callback is comptime-known, following `stdx.core.Eql` conventions.

## Query semantics

Query methods that take a `Range` require a valid input range. Passing an invalid range to a query method is a programmer error and may assert.

`contains(value)` returns true when some entry's range contains `value`.

`get(value)` returns the value pointer for the entry containing `value`, or `null`.

`findContaining(value)` returns the entry containing `value`, or `null`.

`containsRange(range)` returns true when every value in `range` is mapped by one or more entries with no gaps. Adjacent entries count as continuous coverage even when their values differ.

For empty `range`, `containsRange` follows the `core.Range(T)` boundary convention: an empty range is contained when its boundary value lies inside a mapped entry or on a mapped entry boundary. An empty range in a gap is not contained.

`overlaps(range)` returns true when `range` has a non-empty intersection with any entry. Empty ranges never overlap.

`findIntersecting(range)` returns the first stored entry, in ascending order, that has a non-empty intersection with `range`, or `null` when there is no intersection.

## Ordering

Stored entries are always exposed in ascending `range.start` order.

Operations must produce deterministic ordering independent of insertion or assignment order.

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
| `clearRetainingCapacity` | never | never | O(1) | invalidates pointers/slices | caller-owned value | none |
| `insert` | never | never | O(n) | invalidates pointers/slices | caller-owned value | preserves ascending order |
| `assign` | never | never | O(n) | invalidates pointers/slices | caller-owned value | preserves ascending order |
| `remove` | never | never | O(n) | invalidates pointers/slices | caller-owned value | preserves ascending order |
| `coalesceAdjacent` | never | never | O(n) | invalidates pointers/slices | caller-owned value | preserves ascending order |
| `contains` | never | never | O(log n) | none | caller-owned value | none |
| `get` | never | never | O(log n) | returned pointer invalidated by mutation/move | caller-owned value | none |
| `containsRange` | never | never | O(log n + k) | none | caller-owned value | none |
| `overlaps` | never | never | O(log n) | none | caller-owned value | none |
| `findContaining` | never | never | O(log n) | returned pointer invalidated by mutation/move | caller-owned value | none |
| `findIntersecting` | never | never | O(log n) | returned pointer invalidated by mutation/move | caller-owned value | ascending first hit |
| `assertValid` | never | never | O(n) | none | caller-owned value | checks ascending order |

`k` is the number of adjacent entries traversed while checking continuous coverage.

These operations perform no allocation, waiting, sleeping, spinning, hidden global access, atomics, barriers, syscalls, target probing, or architecture probing.

Concurrent mutation is outside the contract. Callers must externally synchronize shared mutable access. Immutable reads through an immutable map require no synchronization beyond ordinary Zig aliasing rules.

## Error behavior

- invalid `T` is a compile error;
- zero-sized `V` is a compile error where practical;
- `insert`, `assign`, and `remove` return `error.InvalidRange` for invalid input ranges;
- `insert` returns `error.Overlap` when the input range overlaps an existing entry;
- `insert` returns `error.Full` when a disjoint insertion needs an extra slot and capacity is full;
- `assign` returns `error.Full` when the final map would exceed capacity;
- `remove` returns `error.Full` when a split needs an extra slot and capacity is full;
- failed mutators leave the map unchanged;
- query misses return `false` or `null`;
- query methods may assert on invalid input ranges;
- methods that require a valid receiver may assert when internal invariants are broken.

## Debug assertion behavior

`assertValid()` checks:

- `count <= capacity()`;
- all stored ranges are valid;
- no stored range is empty;
- entries are sorted by ascending `range.start`;
- entries do not overlap;
- adjacent entries are allowed;
- spare storage is not inspected.

Explicit `assertValid()` calls always perform the check.

Automatic invariant checks inside operations, if implemented, must be gated through `stdx.core.debug.checksEnabled` when the operation exposes a `SafetyMode` option. This spec does not require `RangeMap` operations to expose a `SafetyMode` option.

Assertions document programmer errors and internal invariant failures. Malformed external ranges passed to mutators must return `error.InvalidRange`.

## Implementation constraints

Implementation must:

- use `stdx.core.Range(T)` as the stored range value;
- reject non-unsigned `T` where practical through `Range(T)`;
- reject zero-sized `V` where practical;
- keep initialized entries in `buffer[0..count]`;
- leave `buffer[count..]` as spare storage;
- never expose mutable entry or value storage;
- preserve sorted non-overlap invariants after every successful mutation;
- allow adjacent entries;
- avoid automatic value equality or coalescing except through `coalesceAdjacent`;
- leave the map unchanged on `error.Full`, `error.InvalidRange`, and `error.Overlap`;
- precheck capacity before any mutation that may need more slots;
- use overlap-safe moves when shifting stored entries;
- copy values directly and never deinitialize them;
- avoid loops proportional to the value domain size;
- use loops proportional only to stored entry count;
- avoid hidden globals, allocation, atomics, fences, volatile operations, target probes, architecture probes, and I/O.

Implementation may use binary search for query start points and linear compaction/expansion for mutation.

## Usage

Overlap-rejecting map:

```zig
const RangeMap = stdx.ranges.RangeMap;
const MemoryKind = enum { usable_ram, reserved };

var map = RangeMap.Static(u64, MemoryKind, 8).init();
const Range = @TypeOf(map).Range;

try map.insert(try Range.fromBounds(0, 0xA0000), .usable_ram);
try map.insert(try Range.fromBounds(0xA0000, 0x100000), .reserved);

if (map.get(0x8000)) |kind| {
    _ = kind.*;
}
```

Overwrite assignment:

```zig
const Attr = enum { free, used };
var map = RangeMap.Static(u64, Attr, 8).init();
const Range = @TypeOf(map).Range;

try map.assign(try Range.fromBounds(0, 100), .free);
try map.assign(try Range.fromBounds(40, 60), .used);

// Entries: [0,40)=free, [40,60)=used, [60,100)=free.
```

Explicit coalescing:

```zig
fn eqlAttr(_: void, lhs: *const Attr, rhs: *const Attr) bool {
    return lhs.* == rhs.*;
}

map.coalesceAdjacent({}, eqlAttr);
```

Policy remains caller-owned:

```zig
// Not RangeMap-owned policy:
// - EfiMemoryType
// - MMIO handler dispatch
// - resource IDs
// - map key bumping
// - allocation fit strategy
```

## Required tests

Required for:

- `RangeMap.Static(u8, V, N)` with small capacity for split/full and model tests;
- `RangeMap.Static(u64, V, N)` for normal wide ranges;
- `RangeMap.Bounded(u64, V)` with caller-owned backing storage;
- zero-capacity `Static` and `Bounded` maps.

### Construction and capacity

- static init creates an empty map;
- bounded init creates an empty map over caller storage;
- zero capacity is valid, empty, and full;
- `len`, `capacity`, `remaining`, `isEmpty`, and `isFull` report correct values;
- `clearRetainingCapacity` empties without changing capacity.

### Insert

- inserting an empty range is a no-op;
- inserting into an empty map stores the entry;
- inserting before existing entries preserves sorted order;
- inserting after existing entries preserves sorted order;
- inserting adjacent ranges succeeds and does not coalesce;
- inserting overlapping ranges returns `error.Overlap` and leaves the map unchanged;
- inserting into a full map returns `error.Full` and leaves the map unchanged;
- inserting an invalid range returns `error.InvalidRange` and leaves the map unchanged.

### Assign

- assigning an empty range is a no-op;
- assigning into an empty map stores the entry;
- assigning into a gap stores the entry;
- assigning over one entry preserves head and tail fragments;
- assigning across multiple entries deletes and trims affected entries;
- assigning does not automatically coalesce adjacent equal values;
- assigning when the final entry count would exceed capacity returns `error.Full` and leaves the map unchanged;
- assigning an invalid range returns `error.InvalidRange` and leaves the map unchanged.

### Remove

- removing an empty range is a no-op;
- removing a disjoint range is a no-op;
- removing an exact entry deletes it;
- removing a prefix shrinks an entry;
- removing a suffix shrinks an entry;
- removing the middle splits an entry;
- removing across multiple entries deletes and shrinks affected entries;
- removing the middle at full capacity returns `error.Full` and leaves the map unchanged;
- removing an invalid range returns `error.InvalidRange` and leaves the map unchanged.

### Queries

- `contains` includes starts and excludes ends;
- `contains` returns false for gaps;
- `get` returns the expected value pointer or `null`;
- `findContaining` returns the expected entry or `null`;
- `containsRange` returns true for coverage inside one entry;
- `containsRange` returns true across adjacent entries with no gap;
- `containsRange` returns false across gaps;
- `containsRange` handles empty ranges at mapped boundaries and in gaps;
- `overlaps` rejects adjacent ranges and empty ranges;
- `findIntersecting` returns the first intersecting entry in ascending order;
- `asConstSlice` returns entries sorted by range start.

### Coalescing

- adjacent equal values are not coalesced by `insert`;
- adjacent equal values are not coalesced by `assign`;
- `coalesceAdjacent` merges adjacent entries when the callback returns true;
- `coalesceAdjacent` does not merge adjacent entries when the callback returns false;
- `coalesceAdjacent` does not merge separated equal values across a gap;
- coalescing preserves the left value for the merged entry;
- coalescing reduces or preserves entry count.

### Invariants and invalidation

- `assertValid` succeeds after every public mutation in deterministic tests;
- direct construction of an invalid receiver is detected by `assertValid` where practical;
- pointers from `get`, `findContaining`, and `findIntersecting` are not used after mutation;
- slices from `asConstSlice` reflect immutable order and are not used after mutation.

### Model tests

Randomized operation sequences over a small domain such as `u8` must compare `RangeMap` against a simple reference model.

Required model operations:

- insert random valid ranges with small enum values;
- assign random valid ranges;
- remove random valid ranges;
- occasionally coalesce adjacent equal values with an explicit equality callback;
- compare every point's optional value after each operation;
- compare exported entry list against entries reconstructed from the model array;
- include empty ranges, adjacent ranges, overlapping ranges, gaps, full-capacity cases, and boundary ranges at `0` and max tested value.

### Compile-time behavior

Where practical:

```zig
comptime {
    const Map = stdx.ranges.RangeMap.Static(u8, enum { a, b }, 4);
    const Range = Map.Range;

    var map = Map.init();
    try map.insert(try Range.fromBounds(1, 3), .a);
    try map.assign(try Range.fromBounds(2, 5), .b);

    std.debug.assert(map.contains(4));
    std.debug.assert(map.get(1).?.* == .a);
    std.debug.assert(map.get(2).?.* == .b);
    std.debug.assert(!map.contains(5));
}
```

## Open questions

None.
