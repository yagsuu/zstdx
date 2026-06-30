# Tag allocator

Status: Approved.

`stdx.tags.TagAllocator` is a fixed-capacity allocator of small-integer tags. A
tag is a strongly typed identifier (`Tag(Domain, Int)`) for a hardware command
slot, queue entry, transaction id, or other protocol-defined fixed-width
identifier that consumers exchange with external devices or peers.

The allocator owns allocation state only. It does not own the resources tags
identify, does not perform allocation of backing memory in the `Bounded` form,
and does not enforce any protocol-level rule beyond tag uniqueness and
domain-tagged identity.

## Owned scope

This spec owns:

- the `stdx.tags` namespace and its public surface in this spec;
- `tags.Tag(Domain, Int)` strong tag value type;
- `tags.TagAllocator.Static(Domain, Int, capacity)`;
- `tags.TagAllocator.Bounded(Domain, Int)`;
- the `Int`/`Domain` parameterization rules;
- the lowest-free-index allocation order;
- single-tag allocation, reserve, free, and query operations;
- the error set covering exhaustion, bounds, double-allocate, and double-free;
- no-mutation-on-error behavior;
- zero-capacity behavior;
- `clearRetainingCapacity` semantics;
- `isValid`/`assertValid` invariants;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- `tags.CommandTracker` (TagAllocator plus parallel typed payload slab) — a
  separate spec, deferred until a concrete payload-bearing consumer exists;
- `tags.DynamicTagAllocator` (allocator-backed dynamic capacity) — a separate
  spec, deferred until at least one `mem` primitive establishes a `Dynamic`
  precedent compatible with first-slice constraints;
- contiguous range allocation (`allocRange`/`reserveRange`/`freeRange`);
- alternative allocation orders such as round-robin, randomized, or hint-based
  placement;
- generation counters, ABA protection, or stale-handle detection;
- queue-state metadata beyond raw allocation state (no payloads, no timestamps,
  no completion bits);
- atomic or concurrent tag allocation;
- protocol-specific tag semantics (NVMe CID reuse rules, AHCI slot ordering,
  SQ/CQ pairing);
- byte allocation, typed object construction, or destructors;
- DMA, IOMMU, MMIO, or device-notification policy;
- `std.mem.Allocator` views or interop;
- allocation statistics, tracing, or leak detection.

A tag domain that requires reordering, payload binding, retry semantics, or
completion tracking is the consumer's responsibility or the responsibility of a
later spec that explicitly owns those behaviors.

## Public namespace

`Tag` and `TagAllocator` live under `stdx.tags`:

```zig
stdx.tags.Tag
stdx.tags.TagAllocator
stdx.tags.TagAllocator.Static
stdx.tags.TagAllocator.Bounded
```

They are not root-promoted:

```zig
stdx.Tag           // not exported
stdx.TagAllocator  // not exported
```

## Source ownership

```text
src/tags.zig
src/tags/tag.zig
src/tags/allocator.zig
test/tags/tag_test.zig
test/tags/allocator_test.zig
```

`src/tags.zig` re-exports:

```zig
pub const tag = @import("tags/tag.zig");
pub const allocator = @import("tags/allocator.zig");

pub const Tag = tag.Tag;
pub const TagAllocator = allocator.TagAllocator;
```

`src/tags.zig` is a thin facade. It contains no logic beyond re-exporting and
aliasing.

## Approved API

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

### `Tag(Domain, Int)` returned type

```zig
pub const Self = enum(Int) {
    _,

    pub const Domain = Domain;
    pub const Int = Int;

    pub fn fromInt(value: Int) Self;
    pub fn raw(self: Self) Int;
};
```

`Domain` may be any Zig type; it is used solely as a type-identity phantom.
`Int` must be an unsigned integer type (`u1` through `u64` inclusive). Signed
integers, floats, bools, enums, pointers, and comptime integers without an
explicit `Int` are compile errors.

`Tag(A, u16)` and `Tag(B, u16)` are distinct types for distinct `Domain` types
even when `Int` matches. Comparison, conversion, and any other cross-domain
operation requires explicit `raw()` access and reconstruction.

`Tag(D, I).fromInt` is infallible. Every value of `Int` is a representable tag
value; this spec does not assert that the value is allocatable or that the
target allocator's capacity covers it.

### `Static(Domain, Int, capacity)` returned type

```zig
pub const Self = struct {
    words: [word_count]Word = [_]Word{0} ** word_count,
    allocated_count: usize = 0,

    pub const Domain = Domain;
    pub const Int = Int;
    pub const Tag = stdx.tags.Tag(Domain, Int);
    pub const tag_capacity: usize = capacity;

    pub const Word = u64;
    pub const word_bits = @bitSizeOf(Word);
    pub const word_count = capacity / word_bits +
        @intFromBool(capacity % word_bits != 0);

    pub const Error = error{
        OutOfTags,
        OutOfBounds,
        AlreadyAllocated,
        NotAllocated,
    };

    pub fn init() Self;

    pub fn capacity(self: *const Self) usize;
    pub fn allocated(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn isAllocated(self: *const Self, tag: Tag) bool;
    pub fn isFree(self: *const Self, tag: Tag) bool;

    pub fn allocOne(self: *Self) Error!Tag;
    pub fn reserveOne(self: *Self, tag: Tag) Error!void;
    pub fn freeOne(self: *Self, tag: Tag) Error!void;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn isValid(self: *const Self) bool;
    pub fn assertValid(self: *const Self) void;
};
```

`capacity` must satisfy `capacity <= std.math.maxInt(Int) + 1` at compile time.
A capacity that does not fit in `Int` is a compile error.

`capacity == 0` is supported; the allocator is permanently empty and full.

### `Bounded(Domain, Int)` returned type

```zig
pub const Self = struct {
    words: []Word,
    tag_capacity: usize,
    allocated_count: usize,

    pub const Domain = Domain;
    pub const Int = Int;
    pub const Tag = stdx.tags.Tag(Domain, Int);

    pub const Word = u64;
    pub const word_bits = @bitSizeOf(Word);

    pub const Error = error{
        OutOfTags,
        OutOfBounds,
        AlreadyAllocated,
        NotAllocated,
    };

    pub fn wrap(words: []Word, tag_capacity: usize) Error!Self;

    pub fn capacity(self: *const Self) usize;
    pub fn allocated(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn isAllocated(self: *const Self, tag: Tag) bool;
    pub fn isFree(self: *const Self, tag: Tag) bool;

    pub fn allocOne(self: *Self) Error!Tag;
    pub fn reserveOne(self: *Self, tag: Tag) Error!void;
    pub fn freeOne(self: *Self, tag: Tag) Error!void;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn isValid(self: *const Self) bool;
    pub fn assertValid(self: *const Self) void;
};
```

`Static` and `Bounded` have identical observable allocation semantics. They
differ only in storage ownership.

## Type and capacity contract

`Tag` is the only value type returned by allocation operations. It is the only
value type accepted by `reserveOne`, `freeOne`, `isAllocated`, and `isFree`.
`Tag` values from a different `Domain` or different `Int` width are different
types and cannot be passed without explicit `raw()` reconstruction.

For both variants, the capacity invariant is:

```zig
allocated() + remaining() == capacity()
```

For `Static`, `capacity()` returns the `capacity` type parameter. For
`Bounded`, `capacity()` returns the `tag_capacity` field set at `wrap`.

`Static` with `capacity == 0` and `Bounded.wrap(&.{}, 0)` are valid; the
allocator is empty and full simultaneously.

`Int` must accommodate every representable tag value. Because `tag_capacity`
units are addressed by indexes `0..tag_capacity`, the implementation never
emits a `Tag` whose raw value would not fit in `Int`. This is enforced by:

- compile-time checks in `Static` against `Int`'s range;
- runtime checks in `Bounded.wrap` that reject capacities larger than
  `std.math.maxInt(Int) + 1` with `error.OutOfBounds`.

## Storage model

`Static` owns inline `[word_count]Word` storage. A default struct literal and
`init()` both produce an empty allocator.

`Bounded.wrap(words, tag_capacity)` borrows `words`, clears every borrowed
word, and returns an empty allocator over the first `tag_capacity` tags. It
returns:

- `error.OutOfBounds` when `tag_capacity > words.len * word_bits`;
- `error.OutOfBounds` when `tag_capacity > std.math.maxInt(Int) + 1`.

For both variants, direct mutation of `words` must preserve the unused-bit
invariant and the allocated-count invariant.

## Unused-bit invariant

When `capacity()` is not a multiple of `word_bits`, the final logical word has
unused high bits. Those bits must be zero after every public operation.

Words beyond the logical capacity in a `Bounded` allocator are borrowed
storage, but their bits are not allocatable tags. `wrap` clears them. Public
operations must not expose them as allocated or free tags.

`assertValid()` asserts that unused high bits are zero and that
`tag_capacity <= words.len * word_bits` for `Bounded`.

`isValid()` returns whether the structural invariants hold.

## Query semantics

`capacity()` returns the fixed tag capacity.

`allocated()` returns the number of currently allocated tags.

`remaining()` returns `capacity() - allocated()`.

`isEmpty()` returns `allocated() == 0`.

`isFull()` returns `remaining() == 0`.

For zero-capacity allocators, `isEmpty()` and `isFull()` both return `true`.

`isAllocated(tag)` returns true only when `tag.raw() < capacity()` and the
underlying tag bit is set. It returns false for out-of-bounds tags.

`isFree(tag)` returns true only when `tag.raw() < capacity()` and the
underlying tag bit is clear. It returns false for out-of-bounds tags.

These query methods do not mutate the allocator and do not raise errors.

## Allocation semantics

`allocOne()` allocates and returns the lowest-index free tag.

If no free tag exists, it returns `error.OutOfTags` and does not mutate the
allocator.

The placement order is deterministic lowest-index first. This spec does not
approve round-robin, randomized, hint-based, or implementation-defined orders.

`allocOne` is O(word_count) in the worst case, dominated by a forward scan for
the first non-full word. Single-word capacities are O(1).

## Reserve semantics

`reserveOne(tag)` marks a caller-selected tag allocated.

It returns:

- `error.OutOfBounds` when `tag.raw() >= capacity()`;
- `error.AlreadyAllocated` when the tag is already allocated.

On error, it does not mutate the allocator.

## Free semantics

`freeOne(tag)` marks a caller-selected tag free.

It returns:

- `error.OutOfBounds` when `tag.raw() >= capacity()`;
- `error.NotAllocated` when the tag is already free.

On error, it does not mutate the allocator.

## Clearing

`clearRetainingCapacity()` clears every allocated tag. Capacity and backing
storage identity do not change. After the call:

- `allocated() == 0`;
- `remaining() == capacity()`;
- every previously valid `Tag` value referencing this allocator is logically
  invalidated (the allocator no longer treats it as allocated).

`clearRetainingCapacity()` is O(word_count). There is no `clearAndFree` and no
`deinit`; the allocator owns no heap allocation.

## Behavior contract

| Operation              | Allocation | Waiting | Bounds        | Invalidation                | Concurrency           | Ordering            |
| ---------------------- | ---------- | ------- | ------------- | --------------------------- | --------------------- | ------------------- |
| construction           | never      | never   | O(word_count) | none                        | caller-owned          | none                |
| `capacity`/`allocated`/`remaining`/`isEmpty`/`isFull` | never | never | O(1)/O(word_count) | none | caller-owned | none |
| `isAllocated`/`isFree` | never      | never   | O(1)          | none                        | caller-owned          | none                |
| `allocOne`             | never      | never   | O(word_count) | none                        | caller-owned          | lowest free index   |
| `reserveOne`           | never      | never   | O(1)          | target tag only             | caller-owned          | explicit index      |
| `freeOne`              | never      | never   | O(1)          | target tag only             | caller-owned          | explicit index      |
| `clearRetainingCapacity` | never    | never   | O(word_count) | every allocated tag         | caller-owned          | empty               |
| `isValid`/`assertValid`| never      | never   | O(word_count) | none                        | caller-owned          | none                |

The allocator performs no hidden allocation, waiting, sleeping, spinning,
blocking, syscalls, target probing, atomics, barriers, volatile access, or
hidden global access.

Concurrent mutation is outside the contract. Callers must externally
synchronize shared allocators. Immutable queries over immutable allocator
values require no synchronization beyond ordinary Zig aliasing rules.

A returned `Tag` is a logical identifier. Allocating or freeing other tags
does not move allocated tags. Freeing a tag invalidates the caller's claim to
that identifier; subsequent reuse may return the same raw value to a different
caller.

## Error behavior

```zig
error{
    OutOfTags,
    OutOfBounds,
    AlreadyAllocated,
    NotAllocated,
}
```

- `OutOfTags`: `allocOne` cannot find a free tag.
- `OutOfBounds`: `Bounded.wrap` received an invalid `tag_capacity`; or
  `reserveOne`/`freeOne` received a `tag` whose raw value is `>= capacity()`.
- `AlreadyAllocated`: `reserveOne` would mark an allocated tag.
- `NotAllocated`: `freeOne` would clear a free tag.

Every error-returning operation must leave the allocator unchanged on error.

`OutOfTags` is intentionally distinct from `mem.BitmapAllocator`'s
`OutOfMemory`. A consumer at the wire level knows about tags, not memory; the
error names match the contract.

## Debug assertion behavior

`assertValid()` checks:

- `allocated_count <= capacity()`;
- the set bit count of `words` equals `allocated_count`;
- unused high bits in the final logical word are zero;
- for `Bounded`, `tag_capacity <= words.len * word_bits` and
  `tag_capacity <= std.math.maxInt(Int) + 1`.

`isValid()` returns the boolean equivalent without asserting.

Operations do not call `assertValid()` unconditionally on hot paths.

## Implementation constraints

Implementations must:

- use `u64` words;
- support zero-capacity allocators;
- enforce `capacity <= std.math.maxInt(Int) + 1` at compile time for `Static`
  and at runtime in `Bounded.wrap`;
- compute `word_count` without unchecked overflow;
- keep unused high bits clear after every public operation;
- accept and return only `Tag(Domain, Int)` values from the allocator's own
  `Tag` type alias; cross-domain calls are compile errors;
- avoid hidden allocation, hidden globals, atomics, barriers, syscalls, and
  target probing;
- avoid public bit-scan wrappers around Zig builtins.

Implementations may share private helper code with
`stdx.bits.BitSet.Static` or `stdx.mem.BitmapAllocator` per those specs'
private-helper clauses, but `TagAllocator` owns its public semantics and its
own error set.

## Consumer requirements

A caller that maps tags to external resources owns that mapping and the
lifetime of those resources.

`freeOne` and `clearRetainingCapacity` do not call destructors, release
handles, unmap memory, notify devices, or zero resource contents.

Protocol-specific tag-reuse rules (e.g. NVMe CID reuse after completion,
descriptor visibility ordering) are not enforced. The allocator only tracks
allocation state.

## Examples

```zig
const stdx = @import("stdx");
const tags = stdx.tags;

// NVMe-style command id namespace.
const NvmeCid = struct {};
const NvmeCidAllocator = tags.TagAllocator.Static(NvmeCid, u16, 256);
var cids = NvmeCidAllocator.init();

const c0 = try cids.allocOne();      // c0.raw() == 0
const c1 = try cids.allocOne();      // c1.raw() == 1
try cids.reserveOne(NvmeCidAllocator.Tag.fromInt(64));
try cids.freeOne(c0);

// AHCI-style slot namespace, 5-bit wire width.
const AhciSlot = struct {};
const AhciSlotAllocator = tags.TagAllocator.Static(AhciSlot, u5, 32);
var slots = AhciSlotAllocator.init();
const s0 = try slots.allocOne();

// Cross-domain mixing is a compile error:
// _ = try cids.reserveOne(s0); // error: expected Tag(NvmeCid, u16),
//                              //   found Tag(AhciSlot, u5)
```

`Bounded` over caller-provided storage:

```zig
const Domain = struct {};
const T = tags.TagAllocator.Bounded(Domain, u16);
var backing: [4]u64 = [_]u64{0} ** 4;
var alloc = try T.wrap(&backing, 200);
const t = try alloc.allocOne();
try alloc.freeOne(t);
```

## Required tests

Required capacities:

- `Static(..., 0)`;
- `Static(..., 1)`;
- `Static(..., 64)`;
- `Static(..., 65)`;
- a non-word multiple such as `Static(..., 129)`;
- a width-bounded capacity such as `Static(D, u5, 32)`;
- `Bounded` with zero capacity;
- `Bounded` with a runtime capacity smaller than `words.len * word_bits`;
- `Bounded` with `tag_capacity > std.math.maxInt(Int) + 1` rejected.

### Tag type

- `Tag(D, u16).fromInt`/`raw` round-trip for `0`, a mid value, and
  `std.math.maxInt(u16)`;
- `Tag(A, u16)` and `Tag(B, u16)` are distinct types for distinct `Domain`
  arguments;
- `Tag(D, u16)` and `Tag(D, u32)` are distinct types for distinct `Int`
  arguments;
- declaring `Tag(D, i32)` or `Tag(D, f32)` is a compile error.

### Construction and capacity

- `Static.init()` is empty;
- a default `Static` struct literal is empty;
- `Bounded.wrap` clears borrowed words;
- `Bounded.wrap` rejects `tag_capacity > words.len * word_bits` with
  `error.OutOfBounds`;
- `Bounded.wrap` rejects `tag_capacity > std.math.maxInt(Int) + 1` with
  `error.OutOfBounds`;
- rejected `Bounded.wrap` leaves borrowed words unchanged;
- zero-capacity allocators are both empty and full;
- `allocated() + remaining() == capacity()` after construction;
- `Static(D, u8, 257)` is a compile error.

### Allocation

- `allocOne` returns ascending tag values from an empty allocator;
- `allocOne` returns the lowest free tag after partial frees;
- `allocOne` returns `error.OutOfTags` without mutation when full;
- the returned `Tag`'s `raw()` always satisfies `raw() < capacity()`;
- the returned `Tag` is the allocator's `Tag` type, not a bare `Int`.

### Reserve and free

- `reserveOne` succeeds for a free in-bounds tag;
- `reserveOne` rejects out-of-bounds tags with `error.OutOfBounds`;
- `reserveOne` rejects an allocated tag with `error.AlreadyAllocated`
  without mutation;
- `freeOne` succeeds for an allocated tag;
- `freeOne` rejects out-of-bounds tags with `error.OutOfBounds`;
- `freeOne` rejects a free tag with `error.NotAllocated` without mutation;
- `isAllocated` and `isFree` return false for out-of-bounds tags;
- after `freeOne(t)`, `allocOne` may return a tag with `t.raw()` again.

### Counts, clearing, invariants

- `allocated`, `remaining`, `isEmpty`, and `isFull` cover empty, partial,
  full, and zero-capacity states;
- `clearRetainingCapacity` clears all tags and preserves capacity;
- `assertValid` succeeds after every public mutation;
- unused high bits remain clear after allocation, reserve, free, and clear;
- corrupted unused high bits are detected by `assertValid` where practical.

### Type identity

- `TagAllocator.Bounded(A, u16)` and `TagAllocator.Bounded(B, u16)` are
  distinct types;
- `TagAllocator.Static(D, u16, 64)` and `TagAllocator.Static(D, u16, 128)`
  are distinct types;
- `TagAllocator.Static(D, u16, 64).Tag` equals
  `TagAllocator.Bounded(D, u16).Tag` (both are `Tag(D, u16)`).

### Model tests

A model test compares `Static` and `Bounded` behavior against a simple
bool-array tag allocator over randomized sequences of:

- `allocOne`;
- `reserveOne`;
- `freeOne`;
- `clearRetainingCapacity`.

The model must assert identical success/error results, allocated tag sets,
counts, and no-mutation-on-error behavior.

## Open questions

None.
