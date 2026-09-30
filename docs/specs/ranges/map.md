# Range map

Status: Approved.

`stdx.ranges.RangeMap` maps non-overlapping half-open unsigned ranges to values. `Static` and `Bounded` have fixed capacity. `Unmanaged` and `Managed` grow with an allocator.

## Public namespace

`RangeMap` is available as `stdx.ranges.RangeMap`.

## Cross-spec relationships

This specification depends on `docs/specs/core/range.md` for `stdx.core.Range(T)` and its half-open range semantics. `RangeMap` accepts `Range(T)`. It does not accept `InclusiveRange(T)`.

## Data structures and representation

`T` MUST be an unsigned integer type. `V` MUST have nonzero size. Other `T` values and zero-sized `V` values are compile errors.

Each entry contains a `Range(T)` and a `V`. `Static(T, V, N)` requires `N > 0` at compile time. `Static` stores entries inline. `Bounded` borrows caller-provided `[]Entry` storage. `Unmanaged` owns allocator-provided storage. `Managed` owns an `Unmanaged` map and its allocator.

`RangeMap` copies `V` into entries. It MUST NOT deinitialize, release, or implicitly compare stored `V` values. The caller owns every resource in `V`.

## Global invariants

Initialized entries are in ascending `range.start` order. Every initialized range is valid and non-empty. Adjacent entries do not overlap; adjacency is valid. `len() <= capacity()` always holds.

A bounded caller MUST keep its buffer alive for the map lifetime and for each returned pointer or slice. A bounded caller MUST use one mutable map per buffer. A bounded map MUST NOT borrow a field of its movable outer struct.

An unmanaged or managed caller MUST NOT copy a map after it owns storage. The caller MUST deinitialize each dynamic map exactly once.

A successful mutation invalidates every pointer and slice returned by this map. `ensureTotalCapacity` invalidates them only when it grows storage. `clearAndFree` and `deinit` invalidate them. Moving a static map invalidates pointers and slices into the old value.

Except for a supplied `eql` callback, `RangeMap` does not wait, perform I/O, access hidden globals, or synchronize access. Only dynamic `initCapacity`, `deinit`, `clearAndFree`, growing `ensureTotalCapacity`, and dynamic mutations invoke an allocator. Only `coalesceAdjacent` invokes `eql`. Callers MUST synchronize concurrent mutable access and coordinate map lifetime with every reader.

## API

```zig
pub const RangeMap = struct {
    pub fn Static(comptime T: type, comptime V: type, comptime capacity_entries: usize) type;
    pub fn Bounded(comptime T: type, comptime V: type) type;
    pub fn Unmanaged(comptime T: type, comptime V: type) type;
    pub fn Managed(comptime T: type, comptime V: type) type;
};
```

Every returned type declares:

```zig
pub const Range = stdx.core.Range(T);
pub const Entry = struct { range: Range, value: V };

pub fn len(self: *const Self) usize;
pub fn capacity(self: *const Self) usize;
pub fn remaining(self: *const Self) usize;
pub fn isEmpty(self: *const Self) bool;
pub fn isFull(self: *const Self) bool;
pub fn asConstSlice(self: *const Self) []const Entry;
pub fn clearRetainingCapacity(self: *Self) void;
pub fn coalesceAdjacent(self: *Self, context: anytype, comptime eql: stdx.core.Eql(@TypeOf(context), V)) void;
pub fn contains(self: *const Self, value: T) bool;
pub fn get(self: *const Self, value: T) ?*const V;
pub fn containsRange(self: *const Self, range: Range) bool;
pub fn overlaps(self: *const Self, range: Range) bool;
pub fn findContaining(self: *const Self, value: T) ?*const Entry;
pub fn findIntersecting(self: *const Self, range: Range) ?*const Entry;
pub fn assertValid(self: *const Self) void;
```

`Static` also declares:

```zig
pub const entry_capacity = capacity_entries;
pub const Error = error{ Full, InvalidRange, Overlap };
pub const UpdateError = error{ Full, InvalidRange };

pub fn init() Self;
pub fn insert(self: *Self, range: Range, value: V) Error!void;
pub fn assign(self: *Self, range: Range, value: V) UpdateError!void;
pub fn remove(self: *Self, range: Range) UpdateError!void;
```

`Bounded` also declares:

```zig
pub const Error = error{ Full, InvalidRange, Overlap };
pub const UpdateError = error{ Full, InvalidRange };

pub fn wrap(buffer: []Entry) Self;
pub fn insert(self: *Self, range: Range, value: V) Error!void;
pub fn assign(self: *Self, range: Range, value: V) UpdateError!void;
pub fn remove(self: *Self, range: Range) UpdateError!void;
```

`Unmanaged` also declares:

```zig
pub const Error = error{ OutOfMemory, InvalidRange, Overlap };
pub const UpdateError = error{ OutOfMemory, InvalidRange };

pub fn init() Self;
pub fn initCapacity(allocator: std.mem.Allocator, capacity_entries: usize) std.mem.Allocator.Error!Self;
pub fn deinit(self: *Self, allocator: std.mem.Allocator) void;
pub fn clearAndFree(self: *Self, allocator: std.mem.Allocator) void;
pub fn ensureTotalCapacity(self: *Self, allocator: std.mem.Allocator, capacity_entries: usize) std.mem.Allocator.Error!void;
pub fn insert(self: *Self, allocator: std.mem.Allocator, range: Range, value: V) Error!void;
pub fn assign(self: *Self, allocator: std.mem.Allocator, range: Range, value: V) UpdateError!void;
pub fn remove(self: *Self, allocator: std.mem.Allocator, range: Range) UpdateError!void;
```

`Managed` also declares:

```zig
pub const Error = error{ OutOfMemory, InvalidRange, Overlap };
pub const UpdateError = error{ OutOfMemory, InvalidRange };

pub fn init(allocator: std.mem.Allocator) Self;
pub fn initCapacity(allocator: std.mem.Allocator, capacity_entries: usize) std.mem.Allocator.Error!Self;
pub fn deinit(self: *Self) void;
pub fn clearAndFree(self: *Self) void;
pub fn ensureTotalCapacity(self: *Self, capacity_entries: usize) std.mem.Allocator.Error!void;
pub fn insert(self: *Self, range: Range, value: V) Error!void;
pub fn assign(self: *Self, range: Range, value: V) UpdateError!void;
pub fn remove(self: *Self, range: Range) UpdateError!void;
```

### Construction and lifetime

`Static.init()` and `Unmanaged.init()` create empty maps with zero initialized entries. `Bounded.wrap(buffer)` creates an empty map with `buffer.len` capacity. A zero-length bounded buffer is valid and initially full. `Managed.init(allocator)` creates an empty map that stores `allocator`.

`initCapacity` creates an empty dynamic map with capacity at least `capacity_entries`. It can allocate and returns `error.OutOfMemory` if allocation fails.

`Unmanaged.deinit(allocator)` and `Managed.deinit()` release dynamic storage and invalidate the map. Neither operation deinitializes stored values.

### Capacity and clearing

`len`, `capacity`, `remaining`, `isEmpty`, and `isFull` report initialized-entry and allocated-capacity state. A dynamic map can grow after `isFull()` returns true.

`asConstSlice` returns initialized entries in ascending order. The API does not expose mutable entries or values.

`clearRetainingCapacity` sets `len()` to zero. It retains storage and does not deinitialize stored values. `clearAndFree` releases dynamic storage, sets `len()` and `capacity()` to zero, and does not deinitialize stored values.

`ensureTotalCapacity` ensures dynamic capacity at least `capacity_entries` without changing `len()`. It allocates only when current capacity is smaller. On `error.OutOfMemory`, the map is unchanged.

### `insert`

`insert(range, value)` stores one disjoint non-empty mapping. An empty range succeeds without storing `value`. Adjacent entries remain separate.

`insert` returns `error.InvalidRange` for an invalid range. It returns `error.Overlap` when `range` intersects a stored entry. A fixed map returns `error.Full` when a disjoint entry needs another slot. A dynamic map returns `error.OutOfMemory` when it cannot reserve another slot.

The error order is `InvalidRange`, empty-range success, `Overlap`, then `Full` or `OutOfMemory`. On every error, `insert` leaves the map unchanged.

### `assign`

`assign(range, value)` removes every intersection with `range`, retains outside fragments, and inserts one entry exactly covering `range`. It does not coalesce equal adjacent entries. An empty range succeeds without storing `value`.

`assign` returns `error.InvalidRange` for an invalid range. A fixed map returns `error.Full` when the final entry count exceeds capacity. A dynamic map returns `error.OutOfMemory` when it cannot reserve the final entry count. On every error, `assign` leaves the map unchanged.

### `remove`

`remove(range)` deletes every covered mapping and can delete, trim, or split entries. An empty or disjoint range succeeds without mutation. There is no `error.NotFound`.

`remove` returns `error.InvalidRange` for an invalid range. A fixed map returns `error.Full` when a split needs another slot. A dynamic map returns `error.OutOfMemory` when it cannot reserve the final entry count. On every error, `remove` leaves the map unchanged.

### `coalesceAdjacent`

`coalesceAdjacent(context, eql)` examines adjacent entries in ascending order. It merges adjacent entries only when `eql(context, &left.value, &right.value)` returns true. The merged entry spans both ranges and retains the left value. The right value is dropped without deinitialization.

`coalesceAdjacent` can call `eql` once for each adjacent pair. It does not return an error.

### Queries

The caller MUST pass a valid range to `containsRange`, `overlaps`, and `findIntersecting`.

`contains`, `get`, and `findContaining` test point membership. `containsRange` requires continuous mapped coverage; adjacent entries provide coverage even when their values differ. An empty range is contained only at an entry point or boundary. `overlaps` returns false for an empty range. `findIntersecting` returns the first intersecting entry in ascending order, or `null`.

`get`, `findContaining`, and `findIntersecting` return pointers into map storage.

### Complexity

Construction, accessors, `asConstSlice`, and non-growing `ensureTotalCapacity` are O(1). `insert`, `assign`, `remove`, `coalesceAdjacent`, and `assertValid` are O(n). A growing dynamic operation is O(n). Point and intersection queries are O(log n). `containsRange` is O(log n + k), where `k` is the number of adjacent entries examined.

## Implementation constraints

The implementation MUST preserve the global invariants after each successful operation. It MUST determine required capacity before a fallible mutation. It MUST preserve map state when capacity acquisition fails. It MUST use overlap-safe moves and work proportional to the entry count, not the value-domain size.

The implementation MUST NOT expose mutable map storage, implicitly compare `V`, deinitialize `V`, use atomics, fences, volatile operations, target probes, or I/O.

## Testing

Tests MUST cover construction, capacity, clearing, release, ordering, value preservation, explicit coalescing, and zero-capacity bounded storage.

Tests MUST cover range starts and ends, empty ranges, adjacency, overlap rejection, assignment fragments, removal splits, gaps, and all public errors. Each fallible mutation test MUST verify that an error leaves entries unchanged.

Tests MUST verify allocator ownership, capacity reservation, and `error.OutOfMemory` for dynamic insert, assign, and split-producing remove. Dynamic allocation tests MUST use `std.testing.checkAllAllocationFailures`.

Randomized insert, assign, remove, and coalescing sequences MUST compare point values and exported entries with a reference model. Tests MUST verify `assertValid` after representative successful mutation sequences. Compile-time tests MUST cover supported static mutation.
