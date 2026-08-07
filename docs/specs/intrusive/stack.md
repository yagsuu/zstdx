# Intrusive stack

Status: Approved.

`stdx.intrusive.Stack(T, field)` is a caller-node-backed LIFO stack. It stores stack membership in a `stdx.intrusive.List.SinglyLinkedNode` field embedded in each caller-owned object.

## What this spec is

This specification defines `intrusive.Stack(T, field)`, its LIFO top and mutation operations, its node-membership rules, and the required verification.

## What this spec is not

This specification does not define `intrusive.List`, `intrusive.Queue`, `intrusive.Deque`, or `intrusive.FreeList`; a `StackNode` type; removal from the stack interior; capacity or full-stack policy; allocation policy for parent objects; synchronization; or ABI, wire, or packed-layout guarantees for parent objects.

## Terminology

- **selected node**: The `List.SinglyLinkedNode` field named by `field`.
- **detached**: A selected node whose `next` field is `null`.
- **stacked**: A parent object reachable from `top` through selected-node `next` links.

## Public namespace and source ownership

The public path is `stdx.intrusive.Stack`. `src/intrusive.zig` re-exports `Stack` from `src/intrusive/stack.zig`. Required tests are in `test/intrusive/stack_test.zig`.

## Cross-spec relationships

`Stack` depends on `intrusive.List.SinglyLinkedNode` for its selected node. The stack does not own list operations or another intrusive primitive's membership chain. A parent object MAY participate in independent intrusive chains only when each chain uses a distinct embedded node field.

## Data structures and representation

The returned value has a `top` endpoint pointer that identifies the most recently pushed object. The stack stores no count, backing storage, or parent object.

## Global invariants

- No cycle is reachable from `top` in a valid stack.
- The stack owns only its top pointer and topology. The caller owns every parent object and MUST keep a stacked object alive until the object is detached and until all borrowed pointers to it are no longer used.
- The stack MUST NOT allocate, free, move, copy, destroy, zero, poison, or otherwise manage parent objects.
- The caller MUST NOT move a stacked parent object. The caller MUST NOT mutate a selected node while it is stacked except through this stack.
- The caller MUST use one authoritative mutable `Stack` value for each membership chain. Copying a stack copies the top pointer, not membership; divergent mutable copies are outside this contract.
- All public operations are non-thread-safe. Concurrent access requires caller-owned external synchronization.

## API

```zig
pub fn Stack(comptime T: type, comptime node_field: []const u8) type;

pub const Self = struct {
    top: ?*T = null,

    pub fn init() Self;
    pub fn isEmpty(self: *const Self) bool;

    pub fn peek(self: *Self) ?*T;
    pub fn constPeek(self: *const Self) ?*const T;

    pub fn push(self: *Self, item: *T) void;
    pub fn pop(self: *Self) ?*T;
    pub fn clear(self: *Self) void;
    pub fn assertValid(self: *const Self) void;
};
```

There is no `len`, `capacity`, `remaining`, `isFull`, `front`, `back`, `next`, `enqueue`, `dequeue`, `remove`, `popAll`, iterator, or backing-storage API.

## Type and node-field contract

`Stack(T, field)` requires `field` to name an addressable `List.SinglyLinkedNode` field in `T`. Invalid field names, wrong node types, non-addressable fields, and incompatible packed layouts MUST produce compile errors.

Before its first insertion, the caller MUST initialize the selected node to `.{}`. Before `push(item)`, the caller MUST ensure that `item`'s selected node is detached. The caller MUST NOT insert a selected node that is stacked by this or another intrusive object. A violation is a programmer error; the implementation MAY assert it and does not provide runtime owner tracking.

## Operations

### Construction and access

`init()` and `.{}` create an empty stack with `top = null`. `isEmpty()` returns `top == null`.

`peek()` returns a borrowed pointer to the most recently pushed object, or `null` when the stack is empty. `constPeek()` returns the read-only equivalent. Access operations do not mutate the stack. Returned pointers borrow caller-owned parent objects and remain subject to the caller's lifetime obligations.

### `push`

The caller MUST provide a detached selected node. `push(item)` links `item` before the current top and sets `top` to `item`. It preserves LIFO order and runs in O(1) time.

### `pop`

`pop()` returns `null` without mutation when the stack is empty. Otherwise, it removes and returns the most recently pushed object and advances `top`. Before return, it MUST detach the removed object's selected node. Remaining objects retain their addresses and LIFO order. The operation runs in O(1) time.

### `clear`

`clear()` traverses the stack from newest to oldest, detaches every selected node, and sets `top` to `null`. It does not destroy, free, move, zero, or poison parent objects. `clear()` runs in O(n) time for `n` stacked objects. There is no O(1) reset operation, `clearRetainingCapacity`, `clearAndFree`, or `deinit`.

### `assertValid`

`assertValid()` verifies that no cycle is reachable from `top`. It runs in O(n) time and does not mutate the stack. It does not prove exclusive node ownership, detect every double insertion, or make wrong-stack use safe.

## Implementation constraints

The implementation MAY reuse internal list helpers, but the public type MUST NOT expose an inner `List.SinglyLinked` value. The implementation MUST NOT maintain a count. `clear()` MUST detach every selected node; it MUST NOT only set `top = null`. Every operation performs no heap allocation, waiting, hidden global access, atomics, barriers, volatile access, target probing, syscalls, locks, callbacks, or I/O.

## Testing

Tests MUST construct empty, one-item, and multi-item stacks and verify `init()` equivalence, null results for empty access and removal, LIFO top observations, LIFO removal order, and the transition from one item to empty. These tests prove the observable top and ordering contract at its empty and singleton boundaries.

Tests MUST execute each mutating operation (`push`, `pop`, and `clear`) and call `assertValid()` after each successful mutation. Tests MUST verify that `pop` and `clear` detach selected nodes and that detached nodes can be inserted again. These invariant tests prove that mutations preserve the acyclic-topology requirement while restoring detached membership.

Tests MUST verify independent membership through distinct embedded node fields and stable parent-object addresses. When the test harness supports expected compile failures, it MUST reject an incompatible node field. A corruption test MAY inject a reachable cycle when the harness supports assertion capture. These mutation and corruption methods verify the invariant the checker claims to detect; they do not claim exclusive-ownership detection.
