# `stdx.intrusive.Queue`

`stdx.intrusive.Queue(T, field)` maintains FIFO order through an embedded
`stdx.intrusive.List.SinglyLinkedNode` field. Below, `Queue` means the returned type.

## Membership and lifetime

`field` must identify an addressable `stdx.intrusive.List.SinglyLinkedNode`
in `T`. The [shared intrusive membership and lifetime rules](list.md#variants-and-membership)
apply to the selected node and receiving queue.

## Operations

`Queue.init()` and `.{}` create an empty queue with null `head` and `tail`.
`Queue.front()` borrows the oldest object and `Queue.back()` borrows the newest.
Both return null when empty. `Queue.constFront()` and `Queue.constBack()`
provide const pointers.

| Operation | Result | Cost |
| --- | --- | --- |
| `Queue.pushBack(item)` | Appends after the newest object. | O(1) |
| `Queue.popFront()` | Removes and returns the oldest object, or null unchanged when empty. Removing the final object nulls both endpoints. | O(1) |
| `Queue.clear()` | Detaches every node and nulls both endpoints. | O(n) |

Removal detaches the selected node for reuse. Objects remain alive. Operations
preserve the addresses and FIFO order of remaining objects.

## Validation

`Queue.assertValid()` checks endpoints, links, and reachable cycles in O(n) time.

## References

- [FIFO queue](../../../src/intrusive/queue.zig)
- [List node types](list.md)
