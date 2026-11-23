# `stdx.collections.List`

Fixed-capacity sequences with an initialized prefix and ordered insertion.

`List.*` denotes methods shared by `List.Static(T, N)` and `List.Bounded(T)`.

## Variants

| Contract | `List.Static(T, N)` | `List.Bounded(T)` |
| --- | --- | --- |
| Storage | Inline `[N]T` | Borrowed caller-provided `[]T` |
| Construction | `List.Static(T, N).init()` or `.{}` creates an empty list with undefined spare storage | `List.Bounded(T).wrap(buffer)` creates an empty list without changing the buffer |
| Capacity | Comptime `N > 0`, exposed as `item_capacity`. Zero is a compile error | Runtime `buffer.len`. Zero is valid and makes the list both empty and full |
| Copying | Independent inline storage | Shared backing storage, independent count |

`T` MUST be a runtime value type with `@sizeOf(T) > 0`. A zero-sized element
type is a compile error. Capacity remains fixed for the list's lifetime.

## State and ownership

A valid list satisfies `count <= List.capacity()`. Only `buffer[0..count]` contains
initialized list content. Spare storage may contain undefined bytes and must
not be read or exposed as initialized elements. Direct field mutation must
preserve these invariants.

The caller owns element resource lifetimes and synchronization. List operations
do not release element resources or synchronize concurrent access.

For `List.Bounded(T)`, the caller must keep the buffer alive for the list and all
returned views. Mutation through another alias must preserve list invariants.
Do not embed a bounded list that points at another field of the same movable outer struct.
Use `List.Static(T, N)` for embedded storage.

## Operations

### Capacity and access

Length, capacity, and remaining space count elements.

| Operation | Contract |
| --- | --- |
| `List.asSlice()` / `List.asSliceMut()` | Return read-only / mutable views of the initialized prefix, excluding spare storage. |
| `List.at(index)` / `List.atMut(index)` | Return const / mutable element pointers. `index >= count` returns `error.OutOfBounds`. |
| `List.clearRetainingCapacity()` | Sets `count` to zero without zeroing memory. Retains storage and capacity. |

### Append and insert

| Operation | Contract |
| --- | --- |
| `List.append(item)` | Appends one item. A full list returns `error.Full`. |
| `List.appendAssumeCapacity(item)` | Appends one item. The caller must provide remaining capacity. A full list violates a debug assertion. |
| `List.appendSlice(items)` | Appends all items in order. `items.len > List.remaining()` returns `error.Full`. Empty input always succeeds, including on full or zero-capacity lists. |
| `List.insert(index, item)` | Inserts at `index`, shifting following items right in order. `index > count` returns `error.OutOfBounds`, even when full. Otherwise a full list returns `error.Full`. |

### Removal

| Operation | Contract |
| --- | --- |
| `List.pop()` | Removes and returns the last item. Returns `null` when empty. |
| `List.orderedRemove(index)` | Removes and returns the selected item, shifting following items left in order. |
| `List.swapRemove(index)` | Removes and returns the selected item. The old last item fills the vacancy when necessary. Does not preserve order. |

`List.orderedRemove()` and `List.swapRemove()` return `error.OutOfBounds` when
`index >= count`. All error returns leave the list unchanged. Vacated slots
become spare storage. Iteration follows `List.asSlice()` order.

## Lifetime and invalidation

Views borrow storage and retain their original length after list mutations.
The backing storage must remain alive and, for `List.Static(T, N)`, the list
must remain at the same address.

| Operation | Invalidated indexes, pointers, and views |
| --- | --- |
| `List.append()`, `List.appendAssumeCapacity()`, `List.appendSlice()` | None in the previous initialized prefix |
| `List.insert()` | At and after the insertion index |
| `List.orderedRemove()` | At and after the removed index |
| `List.swapRemove()` | Removed index and old last index. All other element pointers and indexes remain valid |
| `List.pop()` | Old last element |
| `List.clearRetainingCapacity()` | All initialized-element indexes, pointers, and slices |

## Execution and assertions

All operations perform no allocation or waiting. Runtime operation bounds are:

| Operations | Bound |
| --- | --- |
| `List.appendSlice(items)` | O(items.len) |
| `List.insert()`, `List.orderedRemove()` | O(List.len()) |
| All other runtime operations | O(1) |

`List.assertValid()` checks `count <= List.capacity()`.

## References

- [List storage and sequence operations](../../../src/collections/list.zig)

