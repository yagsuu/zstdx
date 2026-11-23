# `stdx.intrusive.List`

Intrusive lists maintain ordered chains through nodes embedded in caller-owned objects.

## Variants and membership

`stdx.intrusive.List.SinglyLinked(T, field)` uses an addressable
`stdx.intrusive.List.SinglyLinkedNode` field (`std.SinglyLinkedList.Node`).
`stdx.intrusive.List.DoublyLinked(T, field)` uses an addressable
`stdx.intrusive.List.DoublyLinkedNode` field (`std.DoublyLinkedList.Node`).
Below, `Singly` and `Doubly` mean the respective returned types, and `List`
means either returned type.

Initialize the selected node to `.{}` before first insertion. A detached singly
linked node has `next == null`. A detached doubly linked node has both `prev`
and `next` null. Insertions require a detached node that belongs to no chain.

The caller owns the objects and MUST keep linked objects alive at stable
addresses. Mutate selected links only through the receiving list. Independent
memberships require distinct node fields. Maintain one authoritative mutable
list value. Copying endpoints does not create independent membership.
Removal leaves objects alive and reusable. Operations do not allocate.
Callers synchronize conflicting access.

## Access and ordering

`List.init()` and `.{}` create an empty list with null `head` and `tail`.
`List.front()` and `List.back()` borrow the endpoint objects, or return null
when empty. `List.constFront()` and `List.constBack()` provide const pointers.

`List.next(item)` follows the selected successor link. `List.constNext(item)`
provides const traversal. `Doubly.previous(item)` and
`Doubly.constPrevious(item)` follow the predecessor link. A null link returns
null. Traverse only live objects in the expected chain or detached nodes.

| Operation | Result |
| --- | --- |
| `List.pushFront(item)` | Inserts before the old head. |
| `List.pushBack(item)` | Inserts after the old tail. |
| `List.insertAfter(anchor, item)` | Inserts immediately after a member of this list. |
| `Doubly.insertBefore(anchor, item)` | Inserts immediately before a member of this list. |
| `List.popFront()` | Removes and returns the head, or returns null unchanged when empty. |
| `Doubly.popBack()` | Removes and returns the tail, or returns null unchanged when empty. |
| `Singly.tryRemove(item)` | Searches for this object. Returns true after removal, or false with both list and object unchanged if absent. |
| `Doubly.remove(item)` | Removes an object that MUST belong to this list. |

Insertions and removals preserve the relative order and addresses of other
objects and update affected endpoints. Every successful removal detaches the
selected node, permitting reuse. These operations take O(1) time except
`Singly.tryRemove()`, which takes O(n).

`List.clear()` takes O(n) time, detaches every selected node, and nulls both
endpoints. Objects remain alive and can be inserted again.

## Validation

`List.assertValid()` checks endpoints, links, and reachable cycles in O(n) time.
`Doubly.assertValid()` also checks reciprocal links.

## References

- [Linked lists](../../../src/intrusive/list.zig)
- [Queue](queue.md) and [stack](stack.md), which use singly linked nodes.
