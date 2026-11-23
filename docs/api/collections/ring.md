# `stdx.collections.Ring`

Fixed-capacity FIFO buffers with optional eviction of the oldest element.
`Ring.*` denotes operations shared by both variants.

## Variants

| Variant | Construction and storage |
| --- | --- |
| `Ring.Static(T, N)` | `Ring.Static(T, N).init()` or `.{}` creates an empty ring with inline storage. `N > 0` is required at compile time. |
| `Ring.Bounded(T)` | `Ring.Bounded(T).wrap(buffer)` creates an empty ring borrowing `buffer`, without changing its contents. Capacity is `buffer.len`. Zero capacity is both empty and full. |

`T` must have nonzero size. Capacity need not be a power of two. Live elements
occupy `count` slots beginning at `head`, wrapping at capacity. Callers who modify
public fields MUST preserve `count <= capacity` and, for nonzero capacity,
`head < capacity`, with every live slot initialized.

Keep borrowed storage alive and in place while the ring or its element pointers
are in use. Bounded copies share storage but track head/count independently. Use
one mutable ring per buffer. Inline copies have independent storage. Keep inline
rings in place while their element pointers are in use.

## Operations

| Operation | Contract |
| --- | --- |
| `Ring.pushBack(item)` | Appends at the back. `error.Full` leaves the ring unchanged. |
| `Ring.pushBackAssumeCapacity(item)` | Appends at the back. Requires spare capacity. |
| `Ring.pushBackOverwriteOldest(item)` | Appends and returns `null` when not full. When full, replaces the oldest element and returns it. With zero capacity, returns `item` without mutation. |
| `Ring.popFront()` | Removes and returns the oldest element, or `null` when empty. |
| `Ring.front()` / `Ring.frontMut()` | Read-only/mutable pointer to the oldest element, or `null` when empty. |
| `Ring.back()` / `Ring.backMut()` | Read-only/mutable pointer to the newest element, or `null` when empty. |
| `Ring.clearRetainingCapacity()` | Empties the ring without overwriting storage, resetting `head`, or changing capacity. |
| `Ring.assertValid()` | Uses `std.debug.assert` to check count and head bounds. |

Counts and capacity use elements. Operations take O(1) time
without allocation or waiting. Callers synchronize conflicting access and manage
element resources. Removal, eviction, and clearing do not call destructors.

## Element pointers

Appending preserves pointers to existing elements. Popping invalidates the removed
element's pointer. Overwriting a full ring invalidates the evicted element's pointer.
Clearing invalidates all live-element pointers. Reacquire endpoint pointers when
the endpoint changes.

## References

- [Ring buffers](../../../src/collections/ring.zig)
