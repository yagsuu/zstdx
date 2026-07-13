# Memory arena bounded

Status: Approved.

`stdx.mem.Arena.Bounded` is a caller-buffer-backed scratch arena for bounded
construction phases, parsers, boot-time setup, and tests that need predictable
allocation without a heap fallback.

It borrows a `[]u8`, bumps forward, and may expose a narrow `std.mem.Allocator`
view for interop. The stdx contract is the arena contract, not the full policy
surface of `std.heap.FixedBufferAllocator`.

## Owned scope

This spec owns:

- `mem.Arena.Bounded`;
- allocation from caller-owned byte storage;
- byte and typed allocation helpers;
- reset and mark/restore lifecycle;
- exhaustion, alignment, and overflow behavior;
- allocator-view interop;
- no-hidden-allocation and no-waiting behavior;
- required tests.

This spec does not own:

- `mem.Arena.Static` (owned by `docs/specs/mem/arena-static.md`);
- growable arenas;
- heap fallback or page allocation;
- individual free, compaction, or ownership transfer;
- thread-safe allocation;
- leak detection, poisoning, high-water stats, or allocation tracing;
- firmware, ACPI, VM, filesystem, or protocol policy;
- object initialization or destructors.

## Public namespace

`Arena.Bounded` lives under `stdx.mem`:

```zig
stdx.mem.Arena
stdx.mem.Arena.Bounded
```

It is not root-promoted:

```zig
stdx.Arena // not exported
```

Source ownership:

```text
src/mem.zig
src/mem/arena.zig
test/mem/arena_test.zig
```

`src/mem.zig` re-exports:

```zig
pub const arena = @import("mem/arena.zig");

pub const Arena = arena.Arena;
```

## Approved API

```zig
pub const Arena = struct {
    pub const Bounded = struct {
        buffer: []u8,
        index: usize = 0,

        pub const ArenaAllocationError = error{ OutOfMemory, Overflow };
        pub const ArenaError = error{ OutOfMemory, InvalidAlignment, Overflow };
        pub const AllocationError = ArenaAllocationError;
        pub const Error = ArenaError;

        pub const Mark = struct {
            index: usize,
        };

        pub fn wrap(buffer: []u8) Bounded;

        pub fn assertValid(self: Bounded) void;
        pub fn isValid(self: Bounded) bool;

        pub fn capacity(self: Bounded) usize;
        pub fn used(self: Bounded) usize;
        pub fn remaining(self: Bounded) usize;
        pub fn remainingBytes(self: Bounded) []u8;

        pub fn mark(self: Bounded) Mark;
        pub fn restore(self: *Bounded, checkpoint: Mark) void;
        pub fn reset(self: *Bounded) void;

        pub fn allocBytes(self: *Bounded, len: usize) AllocationError![]u8;
        pub fn allocAlignedBytes(
            self: *Bounded,
            len: usize,
            alignment: usize,
        ) Error![]u8;

        pub fn alloc(self: *Bounded, comptime T: type) AllocationError!*T;
        pub fn allocSlice(self: *Bounded, comptime T: type, len: usize) AllocationError![]T;

        pub fn allocator(self: *Bounded) std.mem.Allocator;
    };

    pub fn Static(comptime capacity_bytes: usize) type;
};
```

`Mark` values are private to their owning arena. Passing a mark from one
arena to another arena's `restore` is a programmer error. Structural type
equality may permit such cross-arena calls at compile time depending on Zig
anonymous-struct deduplication; runtime assertions catch out-of-range marks
inside `restore`.

## Invariant

A valid `Bounded` satisfies:

```zig
arena.index <= arena.buffer.len
```

`wrap(buffer)` returns `.{ .buffer = buffer, .index = 0 }`.

`assertValid` asserts the invariant. `isValid` returns the invariant result.
Operations other than `isValid` and `assertValid` do not run the invariant
check unconditionally.

## Capacity and remaining bytes

`capacity()` returns `buffer.len`.

`used()` returns `index`.

`remaining()` returns `buffer.len - index`.

`remainingBytes()` returns `buffer[index..]`.

These operations do not allocate, reserve, grow, compact, or reset storage.

## Byte allocation semantics

`allocBytes(len)` is equivalent to `allocAlignedBytes(len, 1)`.

`allocAlignedBytes(len, alignment)` validates `alignment`, advances `index`
so the returned window starts on an address that is a multiple of
`alignment`, and returns the selected byte window. It advances `index`
only after all checks succeed.

The alignment is computed against the absolute address of
`arena.buffer.ptr + arena.index`, not against `arena.index` alone, so the
returned pointer always satisfies `alignment` regardless of the backing
buffer's own alignment.

Required behavior:

```zig
const absolute = @intFromPtr(arena.buffer.ptr) + arena.index;
const aligned = try stdx.mem.alignUp(usize, absolute, alignment);
const padding = aligned - absolute;
const start = try std.math.add(usize, arena.index, padding);
const end = try std.math.add(usize, start, len);
if (end > arena.buffer.len) return error.OutOfMemory;
return arena.buffer[start..end];
```

The implementation must leave `index` unchanged on `error.InvalidAlignment`,
`error.Overflow`, and `error.OutOfMemory`.

`len == 0` succeeds and does not advance. Empty allocations may return any empty
slice with the correct element alignment when the return type requires one.

## Typed allocation semantics

`alloc(T)` returns one uninitialized `T` stored in arena memory aligned to
`@alignOf(T)`.

`allocSlice(T, len)` returns `len` uninitialized `T` values stored contiguously
in arena memory aligned to `@alignOf(T)`.

Typed helpers must reject zero-sized `T` at compile time where practical. Invalid
or unsupported `T` categories beyond zero-sized types are not rejected by this
spec; the arena allocates storage and does not validate object semantics.

The byte count for typed allocation must use checked arithmetic:

```zig
const byte_count = try std.math.mul(usize, @sizeOf(T), len);
```

A typed allocation error leaves `index` unchanged.

## Reset and marks

`mark()` returns the current allocation position.

`restore(mark)` sets `index` back to `mark.index` and invalidates every allocation
made after that mark. Passing a mark from another arena, a future arena state, or
a manually corrupted mark is a programmer error.

`reset()` sets `index` to zero and invalidates every allocation from the arena.

`restore` and `reset` do not clear, zero, poison, or free bytes. Reused bytes keep
their previous contents until overwritten by the caller.

## Allocator view

`allocator()` returns a `std.mem.Allocator` view backed by the same arena state.
It is for interop with APIs that already accept `std.mem.Allocator`.

The allocator view must allocate only from `buffer`, use the same alignment and
exhaustion rules, and leave `index` unchanged on allocation failure.

The allocator view must not make individual frees part of the stdx contract.
`free`, `resize`, or `remap` behavior may satisfy std allocator requirements, but
callers must not rely on them for reusable capacity. Precise lifecycle control
uses `mark`, `restore`, and `reset`.

`Arena.Bounded` must not be a public alias for `std.heap.FixedBufferAllocator`.
The stdx type owns its public semantics even if implementation code shares
internal algorithms with std.

## Ownership and lifetime

`Bounded` borrows `buffer`. It never owns or frees memory.

The caller must keep the backing byte slice alive and mutable for the lifetime of
the arena and every allocation returned from it.

Subsequent allocations do not move earlier allocations. `restore` invalidates
allocations after the mark. `reset` invalidates all allocations.

Copying an arena value duplicates allocation state over the same backing buffer.
Do not allocate from both copies. Checkpointing uses `mark` and `restore`, not
value-copy branching.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `wrap` | none | never | O(1) | none | caller-owned buffer | none |
| position helpers | none | never | O(1) | none | caller-owned buffer | none |
| `allocBytes` | caller buffer | never | O(1) | arena index | caller-owned buffer | byte order only |
| `allocAlignedBytes` | caller buffer | never | O(1) | arena index | caller-owned buffer | byte order only |
| `alloc(T)` | caller buffer | never | O(1) | arena index | caller-owned buffer | byte order only |
| `allocSlice` | caller buffer | never | O(1) | arena index | caller-owned buffer | byte order only |
| `allocator` | caller buffer | never | allocator call | arena index | caller-owned buffer | byte order only |
| `mark` | none | never | O(1) | none | caller-owned buffer | none |
| `restore` | none | never | O(1) | later allocations | caller-owned buffer | none |
| `reset` | none | never | O(1) | all allocations | caller-owned buffer | none |

These operations perform no heap allocation, waiting, hidden global access,
atomics, barriers, volatile access, target probing, syscalls, locks, or I/O.

## Error behavior

- `allocAlignedBytes` returns `error.InvalidAlignment` for invalid alignment;
- alignment rounding overflow returns `error.Overflow`;
- typed byte-count overflow returns `error.Overflow`;
- insufficient remaining capacity returns `error.OutOfMemory`;
- invalid `T` categories owned by this spec are compile errors where practical;
- invalid marks and corrupted arena state are programmer errors.

All error returns leave `index` unchanged.

## Implementation constraints

Implementation must:

- store only the caller buffer and current index in the arena value;
- reuse or exactly match `stdx.mem.alignUp` alignment validity and overflow
  behavior;
- use checked addition and multiplication for allocation sizes;
- avoid unchecked `index + padding + len` arithmetic;
- avoid heap fallback and hidden global allocators;
- avoid per-allocation metadata in the backing buffer;
- avoid target-specific branches;
- avoid unconditional invariant scans on hot paths;
- compile for freestanding targets when `std.mem.Allocator` support is available.

## Usage

Build a temporary table list:

```zig
var scratch: [4096]u8 = undefined;
var arena = stdx.mem.Arena.Bounded.wrap(&scratch);

const tables = try arena.allocSlice(Table, table_count);
```

Rollback speculative parsing:

```zig
const mark = arena.mark();
parseCandidate(&arena) catch |err| {
    arena.restore(mark);
    return err;
};
```

Interop with allocator-taking code:

```zig
var scratch: [8192]u8 = undefined;
var arena = stdx.mem.Arena.Bounded.wrap(&scratch);

var list = std.ArrayListUnmanaged(u32){};
try list.append(arena.allocator(), 42);
```

## Planned use

- parse/build scratch for lowering pipelines, digest staging, and bounded
  host-test fixtures without hot-path heap allocation;
- early-phase scratch construction over fixed byte buffers before a heap
  policy is available;
- caller-owned scratch for table indexing and diagnostic buffers that return
  borrowed views into caller storage.

## Required tests

### Construction and capacity

- `wrap` starts with `used() == 0`;
- `capacity()` equals `buffer.len`;
- `remaining()` equals `buffer.len` at initialization;
- `remainingBytes()` returns the full buffer at initialization;
- zero-capacity arenas are valid.

### Byte allocations

- `allocBytes(0)` succeeds and does not advance;
- `allocBytes(n)` returns the next `n` bytes and advances by `n`;
- `allocAlignedBytes` inserts padding as needed;
- alignment `1` is a no-op;
- invalid alignment returns `error.InvalidAlignment` and leaves `index` unchanged;
- capacity exhaustion returns `error.OutOfMemory` and leaves `index` unchanged;
- offset arithmetic overflow returns `error.Overflow` where practical to trigger.

### Typed allocations

- `alloc(u8)`, `alloc(u32)`, and a layout-boundary extern struct succeed;
- returned pointers satisfy `@alignOf(T)`;
- `allocSlice(T, len)` returns `len` elements in contiguous storage;
- typed byte-count overflow returns `error.Overflow` where practical to trigger;
- zero-sized `T` fails to compile where the compile-fail harness supports it.

### Lifecycle

- `mark` captures the current `index`;
- `restore` returns `index` to the mark and allows reused bytes to be overwritten;
- `reset` returns `index` to zero;
- allocations before a mark keep stable addresses across later allocations;
- allocations after a mark are documented invalid after `restore`.

### Allocator view

- allocator-backed append consumes arena capacity;
- allocator exhaustion returns `error.OutOfMemory`;
- allocator allocation failure leaves arena state unchanged;
- tests use real byte buffers and real std containers, not mocks.

### Debug and compile-time behavior

Required when supported by the compile-fail test harness:

- `assertValid` succeeds after every public mutation sequence;
- `assertValid` catches a manually corrupted `index`;
- invalid mark restore is caught as a programmer error;
- invalid typed allocation categories owned by this spec fail at compile time;
- a mark from a different arena is caught at runtime by the in-range
  assertion inside `restore` when the index does not match.

## Open questions

None.
