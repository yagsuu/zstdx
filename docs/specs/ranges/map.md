# Range map

Status: Approved.

`stdx.ranges.RangeMap` is a fixed-capacity sorted map from unsigned half-open ranges to caller-defined values. It rejects overlapping insertion, supports overwrite assignment and removal, and coalesces values only on explicit request.

## What this spec is

This specification defines `stdx.ranges.RangeMap`, its inline and caller-storage-backed variants, sorted non-overlapping entries, mutation and query behavior, value lifetime, capacity and invalidation, and required tests.

## What this spec is not

This specification does not define automatic value equality, hashing, destructors, address or pointer semantics, allocation policy, memory classification, heap allocation, tree-based storage, or concurrency.

## Public namespace and source ownership

The public import path is `stdx.ranges.RangeMap`. The implementation and contract tests are `src/ranges.zig`, `src/ranges/map.zig`, and `test/ranges/map_test.zig`. `src/ranges.zig` re-exports `RangeMap` from `ranges/map.zig`.

## API

```zig
pub const RangeMap = struct {
    pub fn Static(comptime T: type, comptime V: type, comptime capacity_entries: usize) type;
    pub fn Bounded(comptime T: type, comptime V: type) type;
};

// Static also declares: pub const entry_capacity = capacity_entries;
// Both returned types declare:
pub const Self = struct {
    pub const Range = stdx.core.Range(T);
    pub const Entry = struct { range: Range, value: V };
    pub const Error = error{ Full, InvalidRange, Overlap };
    pub const UpdateError = error{ Full, InvalidRange };

    pub fn init() Self; // Static only
    pub fn wrap(buffer: []Entry) Self; // Bounded only
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
    pub fn coalesceAdjacent(self: *Self, context: anytype, comptime eql: stdx.core.Eql(@TypeOf(context), V)) void;
    pub fn contains(self: *const Self, value: T) bool;
    pub fn get(self: *const Self, value: T) ?*const V;
    pub fn containsRange(self: *const Self, range: Range) bool;
    pub fn overlaps(self: *const Self, range: Range) bool;
    pub fn findContaining(self: *const Self, value: T) ?*const Entry;
    pub fn findIntersecting(self: *const Self, range: Range) ?*const Entry;
    pub fn assertValid(self: *const Self) void;
};
```

## Data structures and representation

`T` MUST be an unsigned integer type; other types are compile errors. `V` MUST have `@sizeOf(V) > 0`; zero-sized types are compile errors. `Static(T, V, N)` requires `N > 0` at compile time. `Bounded.wrap(buffer[0..0])` creates a valid zero-capacity map that is empty and full.

`Static` owns inline entry storage. `Bounded` borrows caller-owned `[]Entry` storage. The caller MUST keep a bounded buffer alive for the map lifetime and for every slice or pointer returned by `asConstSlice`, `get`, `findContaining`, or `findIntersecting`. Copying a bounded map copies its slice pointer and count, not its storage; the caller MUST use one authoritative mutable map per backing buffer. A bounded map MUST NOT point to a field in the same movable outer struct.

`RangeMap` copies `V` into entries and never calls a destructor, deinitializer, release hook, or callback for a stored value. The caller owns all resource lifetimes in `V`; removed, overwritten, shifted, or coalesced values are ordinary dropped Zig values.

## Global invariants

`count <= capacity()` MUST hold. Each initialized entry in `buffer[0..count]` MUST have a valid, non-empty range. Adjacent initialized entries MUST satisfy `items[i].range.end <= items[i + 1].range.start`; therefore entries are sorted and non-overlapping. Adjacent entries are valid and are not automatically coalesced. `buffer[count..]` is spare storage.

## Construction, capacity, and invalidation

`Static.init()` is equivalent to `.{}`. `Bounded.wrap(buffer)` creates an empty map with `buffer.len` capacity. `clearRetainingCapacity()` sets `count` to zero and does not zero spare storage, release resources, deinitialize values, or change capacity. Neither variant owns heap allocation.

`len`, `capacity`, `remaining`, `isEmpty`, and `isFull` return the corresponding count or capacity state and do not inspect spare storage.

`asConstSlice()` returns initialized entries in ascending `range.start` order. `get`, `findContaining`, and `findIntersecting` return pointers into stored entries. Any successful mutation invalidates returned pointers and slices. Moving a static map invalidates pointers and slices into the old value. A bounded-map mutation can invalidate pointers and slices into its borrowed buffer. The API does not expose mutable entries or values.

## `insert`

`insert(range, value)` adds one mapping. An invalid range returns `error.InvalidRange`; an empty range succeeds without storing `value`. An overlapping range returns `error.Overlap`. Adjacent ranges are valid and remain separate. A disjoint insertion that needs another slot when full returns `error.Full`.

The error precedence is invalid range, empty-range success, overlap, then full capacity. On each error, `insert` MUST leave the map unchanged.

## `assign`

`assign(range, value)` removes or trims every intersecting entry, retains head and tail fragments outside `range`, and inserts one entry exactly covering `range` with `value`. It does not automatically coalesce equal adjacent values.

An invalid range returns `error.InvalidRange`; an empty range succeeds without storing `value`. If the final entry count exceeds capacity, `assign` returns `error.Full`. On error, `assign` MUST leave the map unchanged and MUST determine capacity before mutation.

## `remove`

`remove(range)` deletes every mapping over `range` and can delete, trim, or split entries. An invalid range returns `error.InvalidRange`; an empty or disjoint range succeeds without mutation. If a split requires one more slot when the map is full, `remove` returns `error.Full`. On error, `remove` MUST leave the map unchanged and MUST check split capacity before mutation. There is no `error.NotFound`.

## `coalesceAdjacent`

`coalesceAdjacent(context, eql)` scans ascending entries and merges adjacent entries only when `eql(context, &left.value, &right.value)` returns true. The merged entry has `[left.range.start, right.range.end)` and the left value. The right value is dropped without deinitialization.

`context` is borrowed only for the call; `eql` is comptime-known. `coalesceAdjacent` never allocates, fails, or increases `len()`.

## Queries and ordering

Range-taking queries require a valid range. An invalid query range is a programmer error and may assert. `contains`, `get`, and `findContaining` test point membership. `containsRange` requires complete mapped coverage; adjacent entries provide continuous coverage even when their values differ. An empty range is contained only when its point is in an entry or on an entry boundary. `overlaps` requires a non-empty intersection; empty ranges never overlap. `findIntersecting` returns the first intersecting entry in ascending order or `null`.

Every operation preserves ascending deterministic entry order, independent of insertion or assignment order.

## Complexity and execution

Construction, capacity accessors, and `asConstSlice` are O(1). `insert`, `assign`, `remove`, `coalesceAdjacent`, and `assertValid` are O(n). Point and intersection queries are O(log n); `containsRange` is O(log n + k), where `k` is the number of adjacent entries examined. No operation allocates, waits, sleeps, spins, accesses hidden globals, uses atomics or barriers, performs I/O, or probes the target. Concurrent mutation is outside this contract; callers MUST synchronize shared mutable access.

## Implementation constraints

The implementation MUST store `stdx.core.Range(T)` and `V` entries in `buffer[0..count]`, preserve the global invariants after every successful mutation, use overlap-safe moves, and use work proportional to stored entry count rather than value-domain size. It MUST NOT expose mutable storage, implicitly compare values, deinitialize values, or use allocation, callbacks except `coalesceAdjacent`'s supplied `eql`, hidden globals, atomics, fences, volatile operations, probes, or I/O.

## Testing

Tests MUST exercise both storage variants, capacity accessors, clearing, value preservation, explicit coalescing, and zero-capacity bounded storage. Boundary tests MUST cover half-open starts and ends, empty ranges, adjacency, overlap rejection, assignment fragments, removal splits, gaps, callback true and false cases, and `error.Full`, `error.InvalidRange`, and `error.Overlap` with exact no-mutation-on-error snapshots. These tests prove the observable mutation, value, error-precedence, and entry-order contracts.

Randomized insert, assign, remove, and explicit coalescing sequences over a small domain MUST compare point values after each operation with a reference optional-value array and compare exported entries with entries reconstructed from that model. The sequence MUST include boundaries at `0` and the maximum tested value, empty, adjacent, overlapping, gap, and full-capacity cases. This model detects interaction errors among assignment, removal, insertion, and coalescing that individual boundary cases cannot expose.

Tests MUST verify `assertValid` after successful mutations and must not dereference returned pointers or slices after mutation or move. Compile-time tests MUST demonstrate supported compile-time mutation.
