# `stdx.ranges.RangeSet`

A fixed-capacity union of unsigned half-open [ranges](../core/range.md).
In this page, `Set` means either concrete storage variant of `RangeSet(T)` below.

## Storage and lifetime

| Variant | Construction and storage |
| --- | --- |
| `RangeSet(T).Static(N)` | `RangeSet(T).Static(N).init()` creates an empty set with inline capacity `N`. `N` must be nonzero. |
| `RangeSet(T).Bounded` | `RangeSet(T).Bounded.init(buffer)` creates an empty set over caller-owned `[]RangeSet(T).Range` storage without changing buffer contents. A zero-length buffer is valid: the set is both empty and full. |

Use unsigned integer endpoints. `RangeSet(T).Range` is `stdx.ranges.Range(T)`.
Both variants use this family-owned type; neither re-exports it. Helpers that
accept `[]const RangeSet(T).Range` can inspect either variant's `Set.slice()` result.
Stored ranges are non-empty, sorted by start, non-overlapping, and non-adjacent.
`Set.slice()` returns a read-only view of initialized ranges.

Keep borrowed storage alive and at a stable address while the set or its views
are in use. Bounded copies share storage but track lengths independently: use
one mutable set per buffer. Keep inline values in place while views are in use.

Reacquire views after mutation. Ranges can shift or change and old slice lengths
can become stale. `Set.clearRetainingCapacity()` empties the set without erasing
storage or changing capacity.

Length, capacity, and remaining space count stored ranges.
Operations do not allocate or wait.
Callers MUST synchronize shared mutable access.

## Insertion and removal

| Operation | Result |
| --- | --- |
| `Set.insert(range)` | Adds the range and merges all overlapping or adjacent stored ranges. |
| `Set.remove(range)` | Subtracts the range. Stored ranges can be deleted, trimmed, or split into two. |

Both operations check validity first and return `error.InvalidRange` for
inverted bounds. A valid empty range succeeds without mutation, even when full.
Removing a disjoint range also succeeds without mutation.

`Set.insert()` returns `error.Full` only if the resulting canonical range count
exceeds capacity. A full set can therefore accept an insertion that merges
existing ranges. `Set.remove()` returns `error.Full` if a split needs another
slot in a full set. Each error leaves the set unchanged.

## Queries

| Query | Result |
| --- | --- |
| `Set.contains(value)` | Half-open point membership. |
| `Set.findContaining(value)` | Containing range by value, or `null`. |
| `Set.findIntersecting(range)` | First intersecting range in ascending order, or `null`. |
| `Set.overlaps(range)` | Whether any stored range intersects the input. |

`Set.containsRange(range)` requires complete coverage by one stored range.
An empty range is contained exactly when its point lies between a stored
range's start and end, including both boundaries. An empty set contains no
empty ranges. Empty ranges never overlap.

Range-taking queries require valid bounds.
`Set.assertValid()` checks the stored invariants.

## Cost

Construction, capacity accessors, clearing, and `Set.slice()` are O(1).
Insertion and invariant checks are O(n). Removal is O(n²) in the worst case.
Point and intersection queries are O(log n). `Set.containsRange()` is O(log n)
for non-empty input and O(n) for empty input, where `n` is the stored range count.

## References

- [Range sets](../../../src/ranges/set.zig)
- [Range values](../core/range.md)
- [Range maps](map.md) retain values and permit adjacent entries.
