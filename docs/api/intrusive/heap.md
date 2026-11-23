# `stdx.intrusive.heap.Heap`

`stdx.intrusive.heap.Heap(T, field, less)` maintains priority order through
caller-owned objects with embedded `stdx.intrusive.heap.Node` fields.
Below, `Heap` means the returned type.

## Nodes and ownership

`T` must be a non-packed struct, and `field` must identify an addressable
`stdx.intrusive.heap.Node`. Invalid types, field names, and node types are
compile errors.

Initialize each selected node to `.{}` before first insertion. A detached node
has null `parent`, `left`, and `right` links and `linked == false`.
Every member has `linked == true`, including a singleton root.

The caller MUST keep attached objects alive at stable addresses and modify
selected node fields only through the receiving heap. Each selected node can
belong to only one heap. Distinct fields permit independent memberships.
Maintain one authoritative mutable heap value. Copying a non-empty heap does
not create independent membership. Heap operations do not allocate, move, or
destroy objects.

Externally synchronize concurrent access that includes heap mutation or changes
to comparator-visible fields.

## Comparison and priority changes

`less(lhs, rhs)` receives const object pointers and returns true when `lhs`
has higher priority than `rhs`. A `<` comparison gives a min-heap. `>` gives
a max-heap. Equal-priority removal order is unspecified.

The comparator MUST define a strict weak ordering, MUST NOT mutate objects,
and MUST NOT re-enter the heap. Keep the ordering relation unchanged while
objects are attached except for this sequence: change one object's
comparator-visible fields, then call `Heap.update(item)` before another heap
operation. Leave other objects' comparator-visible fields unchanged during
the sequence. Any state read by the comparator must remain valid for its calls.

## Operations

`Heap.init()` and `.{}` create an empty heap. The member count uses `usize`.
Insertion requires room for one more count value.
`Heap.peek()` borrows a const pointer to a highest-priority object.
`Heap.peekMut()` provides a mutable pointer. Both return null when empty.

| Operation | Preconditions and result |
| --- | --- |
| `Heap.insert(item)` | Requires a detached node. Attaches it, increments the count, and restores order. |
| `Heap.pop()` | Removes and returns a highest-priority object, or returns null unchanged when empty. |
| `Heap.remove(item)` | Requires membership in this heap. Removes that object. |
| `Heap.update(item)` | Requires membership in this heap. Restores order after a priority increase, decrease, or unchanged priority, preserving membership and count. |
| `Heap.clear()` | Detaches every node and leaves the heap empty without calling `less`. |

`Heap.pop()` and `Heap.remove()` decrement the count and restore order.
Both reset the removed node to `.{}`. `Heap.clear()` also resets selected nodes
to `.{}`. These detached nodes can be inserted again.

## Validation and costs

`Heap.assertValid()` checks tree shape, links, count, and priority order.
It invokes the comparator.

| Operations | Worst-case time |
| --- | --- |
| `Heap.init()`, `Heap.len()`, `Heap.isEmpty()`, `Heap.peek()`, `Heap.peekMut()` | O(1) |
| `Heap.insert()`, `Heap.pop()`, `Heap.remove()`, `Heap.update()` | O(log n) |
| `Heap.clear()`, `Heap.assertValid()` | O(n) |

Bounds exclude comparator execution time. Comparison counts satisfy the same
bounds. Operations use O(1) auxiliary storage without recursion. Construction,
count and empty checks, inspection, and clearing do not invoke the comparator.

## References

- [Priority heap](../../../src/intrusive/heap.zig)
