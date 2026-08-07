# Buddy block arithmetic

Status: Approved.

`stdx.algo.alloc.buddy` provides value-only block and order arithmetic for buddy allocators.

## What this spec is

This spec defines:

- `Error` and `Block`;
- block size and order derivation;
- containment, sibling, parent, split, and coalescing arithmetic;
- allocation, waiting, concurrency, lifetime, and complexity behavior;
- required verification methods.

## What this spec is not

This spec does not define:

- free-list or bitmap state;
- allocation or release policy;
- allocator exhaustion;
- unit meaning;
- synchronization or memory ordering;
- placement selection over free ranges.

## Public namespace and source ownership

Public declarations:

```zig
stdx.algo.alloc.buddy.Error
stdx.algo.alloc.buddy.Block
stdx.algo.alloc.buddy.blockSize
stdx.algo.alloc.buddy.orderForLen
stdx.algo.alloc.buddy.contains
stdx.algo.alloc.buddy.buddyOf
stdx.algo.alloc.buddy.parentOf
stdx.algo.alloc.buddy.split
stdx.algo.alloc.buddy.canCoalesce
```

Source files:

```text
src/algo.zig
src/algo/alloc.zig
src/algo/alloc/buddy.zig
```

Required test file:

```text
test/algo/alloc/buddy_test.zig
```

## Data structures and representation

```zig
pub const Error = error{
    InvalidRequest,
    Overflow,
};

pub const Block = struct {
    start: usize,
    order: u8,
};
```

For a valid block, `blockSize(block.order)` and `block.start + blockSize(block.order)` MUST be representable in `usize`. `block.start` MUST be aligned to `blockSize(block.order)`.

The caller MUST provide a valid block to an operation that requires block geometry. The implementation MAY assert this precondition in checked modes.

## Global invariants

- Every operation MUST use value arguments only.
- Every operation MUST preserve its arguments.
- No operation MAY own or mutate allocator state.
- No operation MAY allocate, free, wait, access hidden mutable state, issue syscalls, perform atomic or volatile access, or issue barriers.

## API

```zig
pub fn blockSize(order: u8) Error!usize;
pub fn orderForLen(len: usize) Error!u8;
pub fn contains(block: Block, index: usize) Error!bool;
pub fn buddyOf(block: Block) Error!Block;
pub fn parentOf(block: Block) Error!Block;
pub fn split(block: Block) Error![2]Block;
pub fn canCoalesce(left: Block, right: Block) bool;
```

## Operation contracts

`blockSize(order)` MUST return `1 << order` when that value is representable in `usize`. It MUST return `error.Overflow` otherwise.

`orderForLen(len)` MUST return the smallest order whose block size is at least `len`. It MUST return `error.InvalidRequest` when `len == 0` and `error.Overflow` when no representable order can contain `len`.

`contains(block, index)` MUST return whether `index` is in `[block.start, block.start + blockSize(block.order))`. It MUST return `error.Overflow` when the block end is not representable.

`buddyOf(block)` MUST return the adjacent same-order block whose start is:

```zig
block.start ^ blockSize(block.order)
```

`parentOf(block)` MUST return the containing block at `block.order + 1`. It MUST return `error.Overflow` when the parent order, size, or end is not representable.

`split(block)` MUST return two blocks at `block.order - 1` with these starts:

```text
left.start  == block.start
right.start == block.start + blockSize(block.order - 1)
```

`split(block)` MUST return `error.InvalidRequest` when `block.order == 0`. It MUST return `error.Overflow` when the right child start is not representable.

`canCoalesce(left, right)` MUST return true exactly when both blocks have the same order and are buddy siblings. It MUST return false for different orders, non-siblings, or unrepresentable block sizes.

### Concurrency effects

Concurrent calls are valid because all arguments and results are values and no operation accesses shared state.

### Complexity and progress

Every operation MUST complete in O(1) time and O(1) additional space. No operation MAY wait.

## Implementation constraints

The implementation MUST use checked arithmetic for block ends, parent ends, and child starts.

The implementation MUST NOT wrap allocator-owned state or duplicate allocator policy.

## Testing

Public-API tests MUST compare returned values and documented errors. This method verifies the contract without depending on allocator state or private helpers.

Boundary tests MUST exercise order zero, the highest representable order, an unrepresentable order, zero length, exact power-of-two lengths, rounded-up lengths, and an unrepresentable length. These cases verify size and order boundaries.

Geometry tests MUST verify half-open containment, involutive sibling lookup, common-parent lookup, exact split geometry, and sibling versus non-sibling coalescing. These relationships prove the buddy arithmetic invariants.
