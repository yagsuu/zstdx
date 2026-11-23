# `stdx.intrusive.Stack`

`stdx.intrusive.Stack(T, field)` maintains LIFO order through an embedded
`stdx.intrusive.List.SinglyLinkedNode` field. Below, `Stack` means the returned type.

## Membership and lifetime

`field` must identify an addressable `stdx.intrusive.List.SinglyLinkedNode`
in `T`. The [shared intrusive membership and lifetime rules](list.md#variants-and-membership)
apply to the selected node and receiving stack.

## Operations

`Stack.init()` and `.{}` create an empty stack with null `top`.
`Stack.peek()` borrows the most recently pushed object, or returns null when
empty. `Stack.constPeek()` provides a const pointer.

| Operation | Result | Cost |
| --- | --- | --- |
| `Stack.push(item)` | Places the object above the previous top. | O(1) |
| `Stack.pop()` | Removes and returns the most recently pushed object, or null unchanged when empty. | O(1) |
| `Stack.clear()` | Detaches every node and nulls `top`. | O(n) |

Removal detaches the selected node for reuse. Objects remain alive. Operations
preserve the addresses and LIFO order of remaining objects.

## Validation

`Stack.assertValid()` checks for reachable cycles in O(n) time.

## References

- [LIFO stack](../../../src/intrusive/stack.zig)
- [List node types](list.md)
