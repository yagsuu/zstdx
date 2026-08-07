# Range set

Status: Approved.

`stdx.ranges.RangeSet` is a fixed-capacity set of unsigned half-open ranges. It stores canonical `stdx.core.Range(T)` values and supports union insertion, subtraction removal, and range queries.

## What this spec is

This specification defines `stdx.ranges.RangeSet`, its inline and caller-storage-backed variants, canonical range storage, mutation and query behavior, capacity and lifetime rules, and required tests.

## What this spec is not

This specification does not define range-associated values (`stdx.ranges.RangeMap` owns them), address or pointer semantics, allocation policy, memory classification, heap allocation, tree-based storage, or concurrency.

## Public namespace and source ownership

The public import path is `stdx.ranges.RangeSet`. The implementation and contract tests are `src/ranges.zig`, `src/ranges/set.zig`, and `test/ranges/set_test.zig`. `src/ranges.zig` re-exports `RangeSet` from `ranges/set.zig`.

## API

```zig
pub const RangeSet = struct {
    pub fn Static(comptime T: type, comptime capacity_ranges: usize) type;
    pub fn Bounded(comptime T: type) type;
};

// Static also declares: pub const range_capacity = capacity_ranges;
// Both returned types declare:
pub const Self = struct {
    pub const Range = stdx.core.Range(T);
    pub const Error = error{ Full, InvalidRange };

    pub fn init() Self; // Static only
    pub fn wrap(buffer: []Range) Self; // Bounded only
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

## Data structures and representation

`T` MUST be an unsigned integer type; other types are compile errors. `Static(T, N)` requires `N > 0` at compile time. `Bounded.wrap(buffer[0..0])` creates a valid zero-capacity set that is empty and full.

`Static` owns inline storage. `Bounded` borrows caller-owned `[]Range` storage. The caller MUST keep a bounded buffer alive for the set lifetime and for every slice from `asConstSlice`. Copying a bounded set copies its slice pointer and count, not its storage; the caller MUST use one authoritative mutable set per backing buffer. A bounded set MUST NOT point to a field in the same movable outer struct.

## Global invariants

`count <= capacity()` MUST hold. Each initialized range in `buffer[0..count]` MUST be valid and non-empty. Adjacent initialized ranges MUST satisfy `items[i].end < items[i + 1].start`; therefore they are sorted, non-overlapping, and non-adjacent. `buffer[count..]` is spare storage.

## Construction, capacity, and invalidation

`Static.init()` is equivalent to `.{}`. `Bounded.wrap(buffer)` creates an empty set with `buffer.len` capacity. `clearRetainingCapacity()` sets `count` to zero and does not zero spare storage, release resources, or change capacity. Neither variant owns heap allocation.

`len`, `capacity`, `remaining`, `isEmpty`, and `isFull` return the corresponding count or capacity state and do not inspect spare storage.

`asConstSlice()` returns initialized ranges in ascending `start` order. Any successful mutation invalidates that slice. Moving a static set invalidates slices into the old value. A bounded-set mutation can invalidate slices into its borrowed buffer. The API does not expose mutable range storage.

## `insert`

`insert(range)` adds every value in `range` and coalesces every stored range that overlaps or is adjacent to it. An invalid range returns `error.InvalidRange`; an empty range succeeds without mutation. If the final canonical range count exceeds capacity, `insert` returns `error.Full`. On error, `insert` MUST leave the set unchanged and MUST check capacity before a mutation that requires another slot.

## `remove`

`remove(range)` subtracts every value in `range` and can delete, trim, or split stored ranges. An invalid range returns `error.InvalidRange`; an empty or disjoint range succeeds without mutation. If a split requires one more slot when the set is full, `remove` returns `error.Full`. On error, `remove` MUST leave the set unchanged and MUST check split capacity before mutation.

## Queries and ordering

Range-taking queries require a valid range. An invalid query range is a programmer error and may assert. `contains` and `findContaining` test point membership. `containsRange` requires complete coverage by one canonical range; an empty range is contained only when its point is in a stored range or on a stored-range boundary. `overlaps` requires a non-empty intersection; empty ranges never overlap. `findIntersecting` returns the first intersecting range in ascending order or `null`.

Every operation preserves ascending deterministic range order, independent of insertion order.

## Complexity and execution

Construction, capacity accessors, and `asConstSlice` are O(1). `insert`, `remove`, and `assertValid` are O(n). Point and intersection queries are O(log n). No operation allocates, waits, sleeps, spins, accesses hidden globals, uses atomics or barriers, performs I/O, or probes the target. Concurrent mutation is outside this contract; callers MUST synchronize shared mutable access.

## Implementation constraints

The implementation MUST store `stdx.core.Range(T)` values in `buffer[0..count]`, preserve the global invariants after every successful mutation, use overlap-safe moves, and use work proportional to stored range count rather than value-domain size. It MUST NOT expose mutable storage or use allocation, callbacks, hidden globals, atomics, fences, volatile operations, probes, or I/O.

## Testing

Tests MUST exercise both storage variants, capacity accessors, clearing, and zero-capacity bounded storage. Boundary tests MUST cover half-open starts and ends, empty ranges, adjacency, overlap, disjoint removal, canonical coalescing, and split, including `error.Full` and `error.InvalidRange` with exact no-mutation-on-error snapshots. These tests prove the externally visible boundaries, error precedence, and canonical representation.

Randomized insert and remove sequences over a small domain MUST compare membership after each operation with a reference bitset and compare `asConstSlice()` with ranges reconstructed from that bitset. The sequence MUST include boundaries at `0` and the maximum tested value, empty, adjacent, overlapping, and full-capacity cases. This model detects errors in composition of mutations that individual boundary cases cannot expose.

Tests MUST verify `assertValid` after successful mutations and must not dereference a slice after mutation or move. Compile-time tests MUST demonstrate supported compile-time mutation.
