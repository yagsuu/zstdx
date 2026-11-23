# `stdx.mem.alloc.SlabAllocator`

`SlabAllocator` provides fixed-capacity storage for individually acquired values of
one type. Each acquisition returns a stable, aligned `*T`.

## Variants and storage

| Variant | Construction | Storage and capacity |
| --- | --- | --- |
| `SlabAllocator.Static(T, count)` | `SlabAllocator.Static(T, count).init()` | Owns inline storage for `count` slots. Exposes `bound = count`. |
| `SlabAllocator.Bounded(T)` | `SlabAllocator.Bounded(T).wrap(items)` | Borrows a mutable `[]Slot`. Capacity is `items.len`. |

`T` must have nonzero size. `Static` requires `count > 0` at compile time.
`Bounded` accepts an empty slice. That pool is both empty and full.
Both variants start with zero live values.

Each variant exposes `Slot`, a tagged union with `free: ?*Slot` and `occupied: T`.
Size borrowed storage in units of `Slot`, including its tag, link, and padding.
Slot alignment provides at least `@alignOf(T)`.

## Acquire, release, and clear

Here, `Pool` denotes either returned variant type.

`Pool.acquire()` returns uninitialized storage for one `T`. Initialize the value
before reading it. Live acquisitions have distinct payload storage.
The pool reuses released slots in LIFO order before it uses untouched slots in
storage order. When no slot remains, `Pool.acquire()` returns `error.OutOfMemory`
without changing the pool.

`Pool.release(item)` requires an exact, currently live pointer returned by that
pool. It invalidates the acquisition and makes the slot available again.

`Pool.clearRetainingCapacity()` invalidates all acquisitions and restores the
full capacity. It leaves storage contents unspecified.
The caller MUST clean up resources owned by each value before release or clear.

When `stdx.core.debug.checksEnabled()` is true, acquisition fills payload bytes
with `0xCD`. Release fills them with `0xFD` before storing the free-list link.

## Ownership and lifetime

Keep a `Static` pool at a stable address after its first acquisition until it is
cleared or discarded: released slots can retain pointers into its inline storage.
For `Bounded`, keep the borrowed storage alive and at a stable address while the
pool uses it. Use one authoritative mutable pool per storage.

A live pointer remains valid until its release, clear, or the end of the backing
storage's lifetime. Acquiring or releasing other values does not invalidate it.
The caller must synchronize shared access that overlaps mutation.

## Queries and costs

Length counts live acquisitions. Capacity and remaining space count slots.

Construction, clear, and allocation metadata operations take O(1) time.
Checked payload fills cost O(`@sizeOf(T)`) per acquire or release.
`Pool.isValid()` takes O(capacity) worst-case time.
Operations do not allocate backing storage or wait.

## References

- [Object pools](../../../../../src/mem/alloc/slab/allocator.zig)
