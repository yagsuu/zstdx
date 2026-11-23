# `stdx.ranges.RangeMap`

A sorted map from non-overlapping unsigned half-open
[ranges](../core/range.md) to values. In this page, `Map` means any concrete
variant below.

## Storage and lifetime

| Variant | Construction and storage |
| --- | --- |
| `RangeMap.Static(T, V, N)` | `Static.init()` creates an empty map with inline capacity `N`. `N` must be nonzero. |
| `RangeMap.Bounded(T, V)` | `Bounded.wrap(buffer)` creates an empty map over caller-owned `[]Map.Entry` storage. Zero capacity is valid and initially full. |
| `RangeMap.Unmanaged(T, V)` | `Unmanaged.init()` creates an empty, unallocated map. Allocation, release, and fallible mutation methods take an allocator. |
| `RangeMap.Managed(T, V)` | `Managed.init(allocator)` creates an empty map and retains its allocator for subsequent operations. |

Use unsigned integer endpoints and a nonzero-sized `V`.
`Map.Range` is `stdx.ranges.Range(T)`. `Map.Entry` contains `range` and `value`.
Initialized entries have valid, non-empty ranges in ascending start order.
Entries never overlap, but adjacent entries are valid and remain separate
unless explicitly coalesced.

Keep borrowed storage alive and at a stable address while the map or its views
are in use. Bounded copies share storage but track lengths independently: use
one mutable map per buffer. Keep inline values in place while views are in use.

Dynamic maps own their entry storage. Do not duplicate that ownership by
copying a live map. An ownership transfer must leave only one active owner.
Use the allocator that owns the storage for unmanaged operations, and keep the
allocator usable until storage is released. `Map.deinit()` releases dynamic
storage and leaves the map unusable until reinitialized.

Entry views and query pointers borrow map storage. Reacquire them after
mutation: entries can shift or change, and growth can
relocate storage. Clearing removes entries without erasing them. Releasing
storage invalidates all views.

Callers MUST synchronize shared mutable access and coordinate storage lifetime
with readers. Map operations do not wait or perform I/O themselves. Allocator
and equality-callback behavior is caller-controlled.

## Capacity and value ownership

Length, capacity, and remaining space count entries.
Dynamic maps grow as needed.
Dynamic `Map.initCapacity()` creates an empty map with at least the requested
capacity. `Map.ensureTotalCapacity()` reserves at least the requested capacity
without changing entries. It does nothing when capacity is sufficient.
Allocation failure returns `error.OutOfMemory` and leaves the map unchanged.

`Map.clearRetainingCapacity()` clears the count without releasing storage.
Dynamic `Map.clearAndFree()` releases storage and resets length and capacity
to zero, leaving an empty reusable map.

The map copies `V`. It never deinitializes values or releases resources owned
by values. A split copies the original value into both fragments. Assignment,
removal, clearing, coalescing, and deinitialization can discard values without
returning them. Callers manage resource ownership and cleanup.

## Insertion, assignment, and removal

| Operation | Result for non-empty input |
| --- | --- |
| `Map.insert(range, value)` | Inserts one entry if the range is disjoint from all stored entries. Overlap returns `error.Overlap`. Adjacency is allowed. |
| `Map.assign(range, value)` | Replaces all coverage inside the range with one entry exactly covering it. Outside fragments retain their previous values. Equal adjacent entries are not merged. |
| `Map.remove(range)` | Subtracts coverage, deleting, trimming, or splitting entries. A disjoint range succeeds without mutation. |

Each operation checks bounds first: inverted bounds return
`error.InvalidRange`. A valid empty range succeeds without storing a value,
changing entries, or allocating. `Map.insert()` checks overlap before capacity,
so `error.Overlap` takes precedence over `error.Full` or `error.OutOfMemory`.

Static and bounded mutations return `error.Full` if the final entry count
exceeds capacity. Dynamic mutations reserve the final entry count and return
`error.OutOfMemory` if growth fails. Assignment can require two additional
entries when it splits one entry around the replacement. Removal can require
one additional entry for a split. Every returned mutation error leaves entries
and capacity unchanged.

## Explicit coalescing

`Map.coalesceAdjacent(context, eql)` merges touching entries when
`eql(context, &left.value, &right.value)` returns true. It compares in ascending
order, retaining the left value and discarding the right without cleanup.
The retained value is used for subsequent comparisons. No other operation
compares values.

The callback receives read-only value pointers. It must not mutate or
re-enter mutation of the same map, invalidate its storage, or retain these
pointers for later use. Coalescing does not allocate or return an error.

## Queries

| Query | Result |
| --- | --- |
| `Map.contains(value)` | Half-open point membership. |
| `Map.get(value)` / `Map.findContaining(value)` | Borrowed value / entry pointer, or `null` for an unmapped point. |
| `Map.findIntersecting(range)` | First intersecting entry in ascending order, or `null`. |
| `Map.overlaps(range)` | Whether any entry intersects the range. |

`Map.containsRange(range)` requires continuous mapped coverage. Adjacent
entries provide coverage even when values differ. An empty range is contained
exactly when its point lies between an entry's start and end, including both
boundaries. An empty map contains no empty ranges. Empty ranges never overlap.

Range-taking queries require valid bounds.
`Map.assertValid()` checks the stored invariants.

## Cost

Accessors, clearing without release, and non-growing capacity reservation are
O(1). Point and intersection queries are O(log n). Non-empty
`Map.containsRange()` is O(log n + k) for `k` entries examined. Empty-range
containment is O(n). Insertion and invariant checks are O(n). Assignment,
removal, and coalescing are O(n²) in the worst case. Storage growth copies at
most O(n) entries, in addition to allocator work. Here `n` is the entry count.

## References

- [Range maps](../../../src/ranges/map.zig)
- [Range values](../core/range.md)
- [Range sets](set.md) merge adjacency automatically and do not store values.
