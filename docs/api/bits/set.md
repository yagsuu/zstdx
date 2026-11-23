# `stdx.bits.Set`

Fixed-capacity sets of integer indexes. `Set.*` below denotes shared methods on
`stdx.bits.Set(T).Static(limit)` and `stdx.bits.Set(T).Bounded`.

`T` MUST be a positive-width unsigned integer type. Other types, including `u0`,
are compile errors. `Set(T).Word` is [`Word(T)`](word.md).
Valid indexes are in `0..Set.capacity()`. Capacity never changes.
Storage is not a stable wire or ABI layout.

## Variants and construction

| Contract | `Set(T).Static(limit)` | `Set(T).Bounded` |
| --- | --- | --- |
| Storage | Inline `[Word.wordsFor(limit)]Word` | Borrowed caller-provided `[]Word`, with runtime `limit` |
| Empty construction | `Set(T).Static(limit).init()` or `.{}` zeroes inline storage | `Set(T).Bounded.wrap(items, limit)` zeroes the supplied slice on success |
| Full construction | `Set(T).Static(limit).full()` sets all valid bits and clears padding | Use `Set(T).Bounded.wrap()` followed by `Set.setAll()` |
| Capacity | Comptime `limit > 0`. Zero is a compile error | Runtime `limit`. Zero is valid |
| Moving and copying | Movement invalidates views into previous storage. Copies have independent inline storage | Copies share storage. Movement does not move the borrowed words |

`Set(T).Bounded.wrap(items, limit)` returns `error.OutOfBounds` without changing
storage when `Word.wordsFor(limit) > items.len`.

Zero-capacity bounded sets are both empty and full.

## Storage and invariants

Let `n = Word.wordsFor(Set.capacity())`. At least `n` storage words must exist.
Unused high bits in the last used word MUST be zero. All words after the used
prefix MUST also be zero, including for zero capacity. Direct field or alias
mutation MUST preserve these invariants.

`Set.words()` returns a read-only view of exactly the `n` used words, including
the final word's zero padding. It excludes excess borrowed words.
The final word uses all bits for a nonzero exact-width capacity. Otherwise only
the lowest `capacity % Word.width` bits are valid.

The caller MUST keep borrowed storage alive throughout use, including all
returned views. Inline storage must remain at the same address while views are
in use. Ordinary set mutations do not invalidate storage or views. Views observe
subsequent mutations. The caller MUST externally synchronize conflicting access,
including access through copies and aliases. Operations establish no memory
ordering.

## Operations

### Whole-set and single-index operations

| Operation | Contract |
| --- | --- |
| `Set.clearRetainingCapacity()` | Clears the entire storage, including excess borrowed words, without changing capacity. |
| `Set.setAll()` | Sets every valid bit, clears final-word padding, and clears excess borrowed words. |
| `Set.isEmpty()` / `Set.isFull()` | Test whether no valid bits / all valid bits are set. |
| `Set.count()` | Returns the number of valid set bits. |
| `Set.isSet(index)` | Returns membership. Returns false for `index >= capacity`. |
| `Set.set(index)` / `Set.unset(index)` | Set / clear only the selected bit. Return its prior value. |
| `Set.assign(index, value)` | Assigns only the selected bit. Returns its prior value. |
| `Set.toggle(index)` | Inverts only the selected bit. Returns its new value. |
| `Set.firstSet()` / `Set.firstUnset()` | Return the lowest valid set / unset index, or `null` if none exists. Padding is never an unset candidate. |
| `Set.popFirstSet()` | Returns and clears the lowest set index. Returns `null` without mutation when empty. Repeated calls remove bits in ascending order. |

The four single-index mutations return `error.OutOfBounds` for
`index >= capacity`, without changing storage. Bounds errors precede invariant
checks. When `debug.checksEnabled()` is true, `Set.isSet()` checks invariants
before its out-of-range false result.

### Set algebra

Operands must have the same variant and `T`. Static operands must have the same
comptime capacity. Bounded operands MUST have equal runtime capacities. When
`debug.checksEnabled()` is true, a mismatch asserts before invariant checks.
Different borrowed storage lengths are valid if both satisfy the invariants.

| Operation | Contract |
| --- | --- |
| `Set.eql(other)` | Tests equal valid-bit membership. |
| `Set.containsAll(other)` | Tests whether every member of `other` belongs to `self`. |
| `Set.containsAny(other)` | Tests whether the sets share any member. |
| `Set.unionWith(other)` | Replaces `self` with `self ∪ other`. |
| `Set.intersectWith(other)` | Replaces `self` with `self ∩ other`. |
| `Set.differenceWith(other)` | Replaces `self` with `self - other`. |

## Assertions and cost

`Set.assertValid()` checks storage length, padding, and excess words.
When `debug.checksEnabled()` is true, queries, scans, valid-index mutations, and
algebra also check these invariants. Algebra checks both operands.
Clearing and `Set.setAll()` restore zero-bit invariants and require sufficient storage.

All operations are allocation-free and non-waiting. With `n` used words and `m`
total storage words, bounds outside invariant checking are:

| Operations | Time |
| --- | --- |
| `Set.capacity()`, `Set.words()`, single-index queries and mutations | O(1) |
| `Set.isEmpty()`, `Set.isFull()`, `Set.count()`, scans, algebra | O(n) |
| Construction, `Set.clearRetainingCapacity()`, `Set.setAll()`, `Set.assertValid()` | O(m). Failed `Set(T).Bounded.wrap()` takes O(1) |

Automatic invariant checks can add O(m) work per checked operand.

## References

- [Inline and borrowed bit sets](../../../src/bits/set.zig)
- [Word values and capacity conversion](word.md)
