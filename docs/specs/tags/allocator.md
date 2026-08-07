# Tag allocator

Status: Approved.

`stdx.tags.TagAllocator` manages a fixed set of strongly typed, integer tag values. It records whether each tag is allocated. It does not own the resources identified by tags.

## What this spec is

This specification defines:

- the `stdx.tags` public namespace;
- `Tag(Domain, Int)` tag identity and conversion;
- fixed-capacity `TagAllocator.Static` and borrowed-storage `TagAllocator.Bounded` allocators;
- capacity, allocation, reservation, release, query, clearing, and validity contracts;
- error and no-mutation-on-error behavior;
- tag invalidation and caller synchronization requirements; and
- required contract verification.

## What this spec is not

This specification does not define:

- ownership, destruction, or lifetime of resources identified by tags;
- protocol-specific reuse, completion, queue-pairing, or visibility rules;
- payload storage, timestamps, completion state, statistics, tracing, or leak detection;
- range allocation or allocation orders other than lowest-free-index order;
- generation counters, ABA protection, or stale-handle detection;
- dynamic capacity, `std.mem.Allocator` interoperation, byte allocation, or typed-object construction;
- atomic or concurrent allocation, scheduling, waiting, or callback policy; or
- DMA, IOMMU, MMIO, and device-notification policy.

A caller that maps a tag to a resource owns the mapping and the resource lifetime.

## Terminology

- **tag:** A `Tag(Domain, Int)` value. Its raw value identifies an index in an allocator when the raw value is less than the allocator capacity.
- **allocated tag:** An in-bounds tag whose allocation bit is set.
- **free tag:** An in-bounds tag whose allocation bit is clear.
- **logical word:** A `u64` bitmap word that contains one or more tag bits. A final logical word can contain unused high bits.
- **stale tag:** A tag value for which the caller no longer has an allocation claim because the caller released the tag or cleared its allocator. The allocator cannot distinguish a stale tag from a current tag with the same raw value.

## Public namespace and source ownership

The public import paths are:

```zig
stdx.tags.Tag
stdx.tags.TagAllocator
stdx.tags.TagAllocator.Static
stdx.tags.TagAllocator.Bounded
```

The implementation and tests are in:

```text
src/tags.zig
src/tags/tag.zig
src/tags/allocator.zig
test/tags/tag_test.zig
test/tags/allocator_test.zig
```

`src/tags.zig` is a thin facade. It may import, re-export, and alias this public surface, but it MUST NOT implement allocator logic.

## Cross-spec relationships

`TagAllocator` composes with consumers that associate tags with protocol resources. Those consumers own resource lifetime and protocol reuse rules. `TagAllocator` does not depend on, or define public behavior for, another allocator specification.

## Data structures and representation

`Tag(Domain, Int)` is an enum with `Int` as its integer representation. `Domain` is a phantom type used only for type identity.

`Static` owns an inline bitmap of `u64` words. `Bounded` borrows a caller-provided `[]u64` bitmap. The representation of a tag allocator, apart from the public associated constants and methods below, is not a public layout guarantee.

For either variant, bit `n` represents raw tag value `n`. A final logical word has unused high bits when the capacity is not a multiple of 64. Those bits are not tags.

## Global invariants

Every public operation MUST preserve these invariants:

- `allocated() + remaining() == capacity()`.
- `allocated()` equals the number of set bits in the logical bitmap region.
- A tag is in bounds exactly when `tag.raw() < capacity()`.
- Every unused high bit in the final logical word is zero.
- `allocOne()` returns only in-bounds tags.
- `Static` and `Bounded` use the same allocation semantics for the same domain, integer type, capacity, and allocation state.
- `Bounded` MUST treat words after the logical bitmap region as non-tag storage. Its public operations MUST NOT allocate or query tags in those words.

## API

```zig
pub fn Tag(comptime Domain: type, comptime Int: type) type;

pub const TagAllocator = struct {
    pub fn Static(
        comptime Domain: type,
        comptime Int: type,
        comptime capacity: comptime_int,
    ) type;

    pub fn Bounded(
        comptime Domain: type,
        comptime Int: type,
    ) type;
};
```

### `Tag(Domain, Int)`

```zig
pub const Domain = Domain;
pub const Int = Int;

pub fn fromInt(value: Int) Self;
pub fn raw(self: Self) Int;
```

`Domain` can be any Zig type. `Int` MUST be an unsigned integer type with a width from `u1` through `u64`. An invalid `Int` argument is a compile error.

Distinct `(Domain, Int)` pairs produce distinct `Tag` types. A caller MUST use `raw()` and `fromInt()` to move a raw value between distinct tag types. A tag value does not imply that the tag is in bounds or allocated by any allocator.

`fromInt` is infallible. Every `Int` value is representable by the returned `Tag` type.

### `TagAllocator.Static(Domain, Int, capacity)`

```zig
pub const Domain = Domain;
pub const Int = Int;
pub const Tag = stdx.tags.Tag(Domain, Int);
pub const tag_capacity: usize;
pub const Word = u64;
pub const word_bits: usize;
pub const word_count: usize;

pub const AllocError = error{OutOfTags};
pub const ReserveError = error{ OutOfBounds, AlreadyAllocated };
pub const FreeError = error{ OutOfBounds, NotAllocated };
pub const Error = AllocError || ReserveError || FreeError;

pub fn init() Self;
pub fn capacity(self: *const Self) usize;
pub fn allocated(self: *const Self) usize;
pub fn remaining(self: *const Self) usize;
pub fn isEmpty(self: *const Self) bool;
pub fn isFull(self: *const Self) bool;
pub fn isAllocated(self: *const Self, tag: Tag) bool;
pub fn isFree(self: *const Self, tag: Tag) bool;
pub fn allocOne(self: *Self) AllocError!Tag;
pub fn reserveOne(self: *Self, tag: Tag) ReserveError!void;
pub fn freeOne(self: *Self, tag: Tag) FreeError!void;
pub fn clearRetainingCapacity(self: *Self) void;
pub fn isValid(self: *const Self) bool;
pub fn assertValid(self: *const Self) void;
```

`capacity` MUST satisfy `1 <= capacity <= std.math.maxInt(Int) + 1`. A value outside this range is a compile error. `tag_capacity` equals `capacity`. `word_bits` is `@bitSizeOf(Word)`. `word_count` is the number of `Word` values required to represent `capacity` tags.

`init()` and a default `Static` struct literal produce an empty allocator.

### `TagAllocator.Bounded(Domain, Int)`

```zig
pub const Domain = Domain;
pub const Int = Int;
pub const Tag = stdx.tags.Tag(Domain, Int);
pub const Word = u64;
pub const word_bits: usize;

pub const WrapError = error{OutOfBounds};
pub const AllocError = error{OutOfTags};
pub const ReserveError = error{ OutOfBounds, AlreadyAllocated };
pub const FreeError = error{ OutOfBounds, NotAllocated };
pub const Error = WrapError || AllocError || ReserveError || FreeError;

pub fn wrap(words: []Word, tag_capacity: usize) WrapError!Self;
pub fn capacity(self: *const Self) usize;
pub fn allocated(self: *const Self) usize;
pub fn remaining(self: *const Self) usize;
pub fn isEmpty(self: *const Self) bool;
pub fn isFull(self: *const Self) bool;
pub fn isAllocated(self: *const Self, tag: Tag) bool;
pub fn isFree(self: *const Self, tag: Tag) bool;
pub fn allocOne(self: *Self) AllocError!Tag;
pub fn reserveOne(self: *Self, tag: Tag) ReserveError!void;
pub fn freeOne(self: *Self, tag: Tag) FreeError!void;
pub fn clearRetainingCapacity(self: *Self) void;
pub fn isValid(self: *const Self) bool;
pub fn assertValid(self: *const Self) void;
```

`wrap(words, tag_capacity)` borrows `words`. The caller MUST keep the borrowed storage valid for the lifetime of the returned allocator.

`wrap` returns `error.OutOfBounds` without modifying `words` when either condition is true:

- `tag_capacity > words.len * word_bits`; or
- `tag_capacity > std.math.maxInt(Int) + 1`.

Otherwise, `wrap` clears every word in `words` and returns an empty allocator with capacity `tag_capacity`. A bounded allocator with `tag_capacity == 0` is valid.

## Queries

`capacity()` returns the fixed tag capacity. `allocated()` returns the number of allocated tags. `remaining()` returns `capacity() - allocated()`. `isEmpty()` returns `allocated() == 0`. `isFull()` returns `remaining() == 0`.

A zero-capacity `Bounded` allocator is both empty and full.

`isAllocated(tag)` returns true only when `tag` is in bounds and allocated. `isFree(tag)` returns true only when `tag` is in bounds and free. Both methods return false for an out-of-bounds tag. Query methods do not mutate the allocator and do not return errors.

## Allocation

### `allocOne`

`allocOne()` MUST allocate and return the lowest-index free tag. If no free tag exists, it MUST return `error.OutOfTags` and MUST NOT mutate the allocator.

A successful call sets the returned tag allocation bit and increments `allocated()` by one. The tag remains allocated until `freeOne` or `clearRetainingCapacity` changes its state.

### `reserveOne`

`reserveOne(tag)` MUST mark an in-bounds free `tag` as allocated and increment `allocated()` by one. It returns:

- `error.OutOfBounds` when `tag.raw() >= capacity()`; and
- `error.AlreadyAllocated` when `tag` is allocated.

On either error, `reserveOne` MUST NOT mutate the allocator.

### `freeOne`

`freeOne(tag)` MUST mark an in-bounds allocated `tag` as free and decrement `allocated()` by one. It returns:

- `error.OutOfBounds` when `tag.raw() >= capacity()`; and
- `error.NotAllocated` when `tag` is free.

On either error, `freeOne` MUST NOT mutate the allocator. `freeOne` invalidates the caller's allocation claim for `tag`. The allocator can subsequently allocate the same raw value to another caller.

### `clearRetainingCapacity`

`clearRetainingCapacity()` MUST clear all allocation bits and set `allocated()` to zero. It MUST preserve the allocator capacity and, for `Bounded`, the identity of the borrowed storage.

The operation invalidates every current allocation claim. It does not destroy resources, release handles, unmap memory, notify devices, or clear resource contents.

## Validity checks

`isValid()` returns true exactly when all global invariants hold. `assertValid()` asserts the same condition.

For `Bounded`, validity also requires that the capacity fits in `Int`, the logical word count does not exceed `words.len`, and every word after the logical bitmap region is zero. `assertValid()` is a diagnostic operation. Allocator operations do not unconditionally invoke it.

## Concurrency, allocation, and progress

The allocator performs no hidden memory allocation, freeing, waiting, sleeping, spinning, blocking, callback invocation, syscall, scheduler operation, target probe, atomic operation, barrier, volatile access, or hidden global access.

Concurrent access to a mutable allocator is outside this contract. Callers MUST externally synchronize every shared allocator when any concurrent operation can mutate it. Read-only queries of an immutable allocator require no synchronization beyond ordinary Zig aliasing rules.

`allocOne()` is O(`word_count`) in the worst case and O(1) for a single logical word. `reserveOne`, `freeOne`, `isAllocated`, and `isFree` are O(1). `clearRetainingCapacity`, `isValid`, and `assertValid` are O(`word_count`).

## Implementation constraints

An implementation MUST:

- use `u64` bitmap words;
- enforce the stated capacity bounds at compile time for `Static` and at runtime for `Bounded.wrap`;
- avoid unchecked overflow when it computes the logical word count;
- keep unused high bits clear after every public operation;
- accept and return only the allocator `Tag` alias; and
- preserve the no-allocation and no-concurrency-effects contract.

The implementation MAY share private helpers with `stdx.bits.BitSet.Static` or `stdx.mem.alloc.BitmapAllocator`. It MUST retain the `TagAllocator` public surface and error set defined here.

## Testing

Tests MUST verify the observable contract for both allocator variants. They MUST compare allocation state, returned tags, counts, errors, and backing storage before and after each operation where the contract requires no mutation.

Construction and capacity tests MUST verify `Static` initialization and default construction, `Bounded.wrap` storage clearing, capacity bounds, exact maximum capacity for an `Int` width, and the valid zero-capacity `Bounded` state. Rejected `Bounded.wrap` calls MUST prove that borrowed words remain unchanged. These tests prove capacity ownership and failure atomicity.

Tag-identity tests MUST verify raw-value round trips at zero, a non-boundary value, and the maximum `Int` value; distinct `Domain` and `Int` arguments; and compile-time rejection of invalid integer types. Compile-time checks MUST also verify that allocator operations accept only their allocator `Tag` type. These tests prove type-safe tag identity independently of allocation membership.

Allocation tests MUST use capacities of 1, 64, 65, a non-word multiple, and an `Int`-width maximum. They MUST prove ascending initial allocation, lowest-free reuse after partial release, exhaustion without mutation, and the in-bounds return condition. Reserve and release tests MUST prove each success transition, each specified error, query behavior for out-of-bounds tags, no mutation on error, and reuse after release. These tests prove the allocation state machine and error contract.

Invariant tests MUST cover empty, partially allocated, full, and zero-capacity states. They MUST verify `allocated() + remaining() == capacity()`, clearing behavior, unused-high-bit preservation, and detection of corrupted bitmap state by `assertValid()`. These tests prove count consistency and bitmap boundaries.

A deterministic randomized model test MUST compare `Static` and `Bounded` allocators with a simple boolean-array model over `allocOne`, `reserveOne`, `freeOne`, and `clearRetainingCapacity`. After every operation, the test MUST compare success or error result, allocated tag set, counts, and no-mutation-on-error behavior. The model test proves that both storage variants preserve the same state-machine contract across mixed sequences.
