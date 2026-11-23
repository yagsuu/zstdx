# `stdx.tags.Tag` and `stdx.tags.TagAllocator`

`stdx.tags.TagAllocator` tracks allocation of strongly typed integer tags.
Callers own the resources and mappings identified by those tags.

`Tag.*` denotes operations on `Tag(Domain, Int)`. `Allocator.*` denotes shared
operations on `TagAllocator.Static` and `TagAllocator.Bounded`.
`Static.*` and `Bounded.*` denote variant-specific operations on those returned types.

## Tag values

`stdx.tags.Tag(Domain, Int)` is an enum backed by `Int`. `Domain` can be any
type. `Int` must be an unsigned integer with width from `u1` through `u64`.
Other integer types are compile errors. Distinct `(Domain, Int)` pairs produce
distinct tag types.

`Tag.from(value)` accepts every `Int` value and `Tag.raw()` returns that value.
Zero is valid. Allocator indices satisfy `tag.raw() < Allocator.capacity()`.

## Variants and backing storage

| Type | Construction and bounds |
|---|---|
| `stdx.tags.TagAllocator.Static(Domain, Int, count)` | `Static.init()` or default initialization creates an empty inline bitmap. `count` must be positive and at most `maxInt(Int) + 1`. Invalid counts are compile errors. Capacity must also fit the platform's `usize`-indexed storage. |
| `stdx.tags.TagAllocator.Bounded(Domain, Int)` | `Bounded.wrap(items, limit)` borrows `[]Bounded.Word`, where `Word` is `stdx.bits.Set(u64).Word`. Capacity is `limit`. |

Both variants expose the same `Domain`, `Int`, and `Tag` aliases for the same
type arguments. Their tags are interchangeable. Allocator instances do not
contribute to tag identity.

`Bounded.wrap()` first checks whether `limit <= maxInt(Int) + 1`, then checks
whether the backing has at least `ceil(limit / 64)` words. Either failure
returns `error.OutOfBounds` without changing the backing.

On success, `Bounded.wrap()` clears every supplied word, including surplus
words, and returns an empty allocator. Zero capacity is valid, with either
empty or nonempty backing. Keep the borrowed storage alive and stable during
use. Do not independently mutate or share the backing between active allocators.

Capacity is fixed. Operations do not allocate or free storage.

## Allocation and release

| Operation | Result |
|---|---|
| `Allocator.allocOne()` | Allocate the lowest-index free tag. Return `error.OutOfTags` when none is free. |
| `Allocator.reserveOne(tag)` | Check bounds first. Return `error.OutOfBounds` if outside capacity. Return `error.AlreadyAllocated` if already allocated. Otherwise allocate that exact tag. |
| `Allocator.freeOne(tag)` | Check bounds first. Return `error.OutOfBounds` if outside capacity. Return `error.NotAllocated` if already free. Otherwise release that exact tag. |

Returned errors leave allocation bits and count unchanged.

`Allocator.clearRetainingCapacity()` clears all supplied bitmap words and
resets the allocated count to zero. Capacity and borrowed-storage identity
remain unchanged.

Released tags can be reused. Tags have no generation or allocator identity, so
an old tag can query or release a newer allocation with the same value. Complete
resource-specific lifetime protocols before releasing tags or clearing.

## Queries and validity

Counts and capacity use tags. A zero-capacity allocator is both empty and full.

`Allocator.isAllocated(tag)` and `Allocator.isFree(tag)` both return false for
out-of-bounds tags. For an in-bounds tag, they report its allocation bit and
its complement, respectively.

`Allocator.isValid()` checks that storage covers capacity, the count equals
the number of allocated bits and does not exceed capacity, unused high bits
are zero, and surplus words are zero. For `Bounded`, it also checks that
capacity fits `Int`.

Callers MUST externally synchronize shared access whenever an operation can
mutate the allocator or its backing.

## Costs

Let `W = ceil(capacity / 64)` and `B` be the supplied backing word count
(`B = W` for `Static`).

| Operation | Time |
|---|---|
| Initialization, successful wrapping, clearing, `Allocator.isValid()` | O(B) |
| `Allocator.allocOne()` | O(W) worst case, apart from enabled bitmap diagnostics |
| Reservation, release, allocation-state queries | O(1), apart from enabled bitmap diagnostics |
| Capacity and count queries | O(1) |

When `stdx.core.debug.checksEnabled()` is true, bitmap diagnostics additionally
check unused high bits and surplus words during allocation, reservation,
release, and in-bounds allocation-state queries. These checks add O(B) worst-case
time. Storage is O(B).

## References

- [Tag values](../../../src/tags/tag.zig)
- [Tag allocation](../../../src/tags/allocator.zig)
