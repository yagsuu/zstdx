# Intrusive stack

Status: Approved.

`zstdx.intrusive.Stack(T, field)` is a caller-node-backed LIFO stack. It never
allocates, never moves parent objects, and stores membership in an embedded
`zstdx.intrusive.List.SinglyLinkedNode` field owned by the caller's object.

## Owned scope

This spec owns:

- `intrusive.Stack(T, field)`;
- LIFO top semantics over caller-owned objects;
- stack use of `intrusive.List.SinglyLinkedNode` as the embedded node type;
- top access, push, pop, clearing, and topology validation;
- allocation, waiting, invalidation, concurrency, and ordering behavior;
- required tests.

This spec does not own:

- `intrusive.List`, `intrusive.Queue`, `intrusive.Deque`, or
  `intrusive.FreeList`;
- a distinct `StackNode` type;
- arbitrary removal or cancellation from the middle of a stack;
- bounded capacity, full-state behavior, overwrite-on-full behavior, or
  drop-oldest policy;
- scalar-value stacks, fixed rings, guest rings, or descriptor rings;
- parser, AST, rollback, device, firmware, allocator, slab, or object-pool
  policy;
- free-list poisoning, generation counters, handles, tombstones, or ownership
  tracking;
- managed or unmanaged heap allocation;
- worker wakeups, eventfds, locks, atomics, SPSC, MPSC, MPMC, or externally
  locked behavior;
- ABI, wire, or packed layout guarantees for parent objects.

## Public namespace

`Stack` lives under `zstdx.intrusive`:

```zig
zstdx.intrusive.Stack
```

It is not root-promoted. Callers use the intrusive namespace explicitly.

Source ownership:

```text
src/intrusive.zig
src/intrusive/stack.zig
test/intrusive/stack_test.zig
```

`src/intrusive.zig` re-exports:

```zig
pub const stack = @import("intrusive/stack.zig");

pub const Stack = stack.Stack;
```

`src/zstdx.zig` re-exports the namespace only:

```zig
pub const intrusive = @import("intrusive.zig");
```

There is no `zstdx.Stack`, `zstdx.StackNode`, or
`zstdx.intrusive.StackNode` alias.

## Approved API

```zig
pub fn Stack(comptime T: type, comptime node_field: []const u8) type;
```

Returned type:

```zig
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

There is no `len`, `capacity`, `remaining`, `isFull`, `first`, `last`,
`front`, `back`, `next`, `enqueue`, `dequeue`, `remove`, `pushAssumeCapacity`,
`popAll`, `asSlice`, or iterator API.

## Type and node-field contract

`Stack(T, field)` requires `field` to name an addressable field of type
`List.SinglyLinkedNode` within `T`.

Invalid field names, wrong node types, non-addressable fields, and incompatible
packed layouts are compile errors where practical.

The selected node field stores stack membership. Each independent intrusive
membership requires a distinct embedded node field.

Example:

```zig
const Frame = struct {
    id: u32,
    ready_node: zstdx.intrusive.List.SinglyLinkedNode = .{},
    free_node: zstdx.intrusive.List.SinglyLinkedNode = .{},
};

const ReadyStack = zstdx.intrusive.Stack(Frame, "ready_node");
const FreeStack = zstdx.intrusive.Stack(Frame, "free_node");

var ready = ReadyStack.init();
var free = FreeStack.init();
var frame: Frame = .{ .id = 1 };

ready.push(&frame);
free.push(&frame);
```

A node must be initialized to `.{}` before its first insertion. `push(item)`
requires the selected node to be detached. `pop()` and `clear()` detach nodes
before returning.

## Ownership and lifetime

The stack value owns only the top pointer and structural invariants. It does not
own, allocate, free, move, copy, or destroy parent objects.

The caller owns each parent object and must keep it alive while it is stacked and
while any pointer returned by the stack is used.

Moving a stack value does not move parent objects. Moving a parent object while
it is stacked is outside the contract because embedded node pointers in other
objects may still point at the old address.

Copying a stack value copies the top pointer, not membership. Divergent mutable
copies over the same nodes are outside this primitive's contract. Use one
authoritative mutable stack value for each intrusive membership chain.

External mutation of node fields while stacked is outside the contract unless
the mutation preserves every invariant owned by the stack.

## Construction

`init()` is equivalent to `.{}`. Both create an empty stack with `top = null`.

`isEmpty()` returns `top == null`.

There is no capacity. The stack can link only caller-owned objects that already
exist, so exhaustion policy belongs to the owner domain.

## Top access

`peek()` returns the most recently pushed object, or `null` when empty.

`constPeek()` returns the read-only equivalent.

Pointers borrow from the caller-owned parent objects, not from stack storage. The
stack does not move those objects.

## Push semantics

`push(item)` links `item` before the current top in O(1).

When the stack is empty, `push(item)` sets `top = item`.

When the stack is not empty, `push(item)` links `item` to the old top and sets
`top = item`.

`push(item)` requires `item`'s selected node to be detached before the call.
There is no full state, so `push(item)` has no error return.

## Pop semantics

`pop()` removes and returns the most recently pushed object. It returns `null`
when empty.

When the removed object was the only stacked object, the stack becomes empty.
When more objects remain, `top` advances to the next stacked object.

The removed object's selected node is detached before return.

## Clearing

`clear()` walks the stack from newest to oldest, detaches every stacked node, and
then sets `top = null`.

`clear()` does not destroy, zero, free, poison, or move parent objects.

There is no `clearRetainingCapacity` because intrusive stacks have no capacity
and own no backing storage. There is no `clearAndFree` or `deinit` because
intrusive stacks own no resources.

There is no O(1) reset operation. Dropping `top` without detaching nodes leaves
stale embedded links inside caller-owned objects and is outside this primitive's
contract.

## Invalidation and ordering

Intrusive stacks do not invalidate parent-object pointers by moving objects. They
only change stack membership and link-neighbor relationships.

`push(item)` changes the new item's successor relationship. It changes `top` to
point at `item`.

`pop()` invalidates the removed object's stack membership and its former neighbor
relationship. Remaining objects stay at the same addresses.

`clear()` invalidates every membership in the stack and detaches every node.

LIFO order is the reverse order of successful `push(item)` calls not yet removed.
`pop()` returns objects in LIFO order. There is no reordering.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `Stack` | never | never | comptime | none | type factory | none |
| `init` | never | never | O(1) | none | caller-owned value | empty |
| `isEmpty` | never | never | O(1) | none | caller-owned value | none |
| top access | never | never | O(1) | none | caller-owned value | LIFO top |
| `push` | never | never | O(1) | top endpoint | caller-owned value | adds newest |
| `pop` | never | never | O(1) | removed top | caller-owned value | removes newest |
| `clear` | never | never | O(n) | all memberships | caller-owned value | empty |
| `assertValid` | never | never | O(n) | none | caller-owned value | verifies topology |

These operations perform no heap allocation, waiting, hidden global access,
atomics, barriers, volatile access, target probing, syscalls, locks, or I/O.

## Error behavior

The public API has no error set.

- empty top access returns `null`;
- empty pops return `null`;
- invalid type and field combinations are compile errors where practical;
- double insert is a programmer error;
- using the same node field in another intrusive object while stacked is a
  programmer error;
- externally corrupted links are a programmer error.

Operations with programmer-error preconditions may assert those preconditions
when practical, but the spec does not require runtime owner tracking.

## Debug assertion behavior

`assertValid()` checks local topology reachable from this stack's top. It does
not prove node ownership, detect all double inserts, or make wrong-stack use
safe.

`assertValid()` checks where practical:

- no cycle is reachable from `top`;
- every reached link uses the selected embedded node field.

Mutating operations may call `assertValid()` before and after mutation when
`core.checksEnabled(opts.safety)` or an equivalent module safety option requires
runtime invariant checks.

## Implementation constraints

Stack may reuse internal intrusive-list helper code, but the returned public type
must not expose an inner `List.SinglyLinked` value. The public value exposes only
the top endpoint and stack operations.

Implementations must not maintain a count. A count would add a store to every
push and pop while providing no primitive-level capacity or exhaustion behavior.

`clear()` must detach every linked node. Implementations must not optimize clear
by only setting `top = null`.

## Examples

Free-object stack:

```zig
const Slot = struct {
    id: u16,
    free_node: zstdx.intrusive.List.SinglyLinkedNode = .{},
};

const FreeSlots = zstdx.intrusive.Stack(Slot, "free_node");

var free = FreeSlots.init();
var slot_a: Slot = .{ .id = 1 };
var slot_b: Slot = .{ .id = 2 };

free.push(&slot_a);
free.push(&slot_b);

const slot = free.pop() orelse return error.OutOfSlots;
consume(slot);
```

Parser work stack:

```zig
const Frame = struct {
    offset: usize,
    stack_node: zstdx.intrusive.List.SinglyLinkedNode = .{},
};

const Frames = zstdx.intrusive.Stack(Frame, "stack_node");

var frames = Frames.init();
var root: Frame = .{ .offset = 0 };

frames.push(&root);

while (frames.pop()) |frame| {
    parse(frame);
}
```

## Required tests

Construction tests:

- empty stack;
- `init()` equals default initialization;
- top access on an empty stack returns `null`;
- `pop()` on an empty stack returns `null`.

LIFO tests:

- push one item;
- push two items;
- `peek()` tracks the newest item after pushes;
- `pop()` returns items in reverse push order;
- `pop()` from a one-item stack clears `top`;
- `pop()` from a multi-item stack preserves remaining LIFO order.

Clearing tests:

- clear an empty stack;
- clear a one-item stack;
- clear a multi-item stack;
- cleared nodes are detached;
- reinsertion after clear succeeds.

Cross-cutting tests:

- stack uses `List.SinglyLinkedNode` fields;
- wrong field type fails to compile where practical;
- multi-membership through distinct embedded node fields;
- parent object addresses stay stable across stack operations;
- popped and cleared nodes are detached;
- `assertValid()` succeeds after every public mutation;
- structural corruption tests where practical for broken links and cycles.

## Open questions

None.
