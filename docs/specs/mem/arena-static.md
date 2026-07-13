# Memory arena static

Status: Approved.

`stdx.mem.Arena.Static(N)` is an inline fixed-capacity bump arena. It owns
`[N]u8` storage, never allocates beyond that storage, and shares the same
allocation, mark/restore, and reset semantics as `Arena.Bounded`.

## Owned scope

This spec owns:

- `mem.Arena.Static(N)`;
- inline `[N]u8` storage;
- bump allocation that matches `Arena.Bounded`;
- mark/restore/reset lifecycle for inline-storage arenas;
- pointer-stability rules unique to inline storage;
- allocator-view interop;
- required tests.

This spec does not own:

- `mem.Arena.Bounded` (owned by `docs/specs/mem/arena-bounded.md`);
- growable arenas;
- heap fallback or page allocation;
- per-allocation free, compaction, or transfer of ownership;
- thread-safe allocation;
- leak detection, poisoning, or high-water stats.

## Public namespace

`Arena.Static` lives under `stdx.mem`:

```zig
stdx.mem.Arena
stdx.mem.Arena.Static
```

It is not root-promoted:

```zig
stdx.Arena // not exported
```

Source ownership is shared with `Arena.Bounded`:

```text
src/mem.zig
src/mem/arena.zig
test/mem/arena_test.zig
```

## Approved API

```zig
pub const Arena = struct {
    pub const Bounded = …; // see arena-bounded.md

    pub fn Static(comptime capacity_bytes: usize) type {
        return struct {
            buffer: [capacity_bytes]u8 = undefined,
            index: usize = 0,

            const Self = @This();

            pub const ArenaAllocationError = error{ OutOfMemory, Overflow };
            pub const ArenaError = error{ OutOfMemory, InvalidAlignment, Overflow };
            pub const AllocationError = ArenaAllocationError;
            pub const Error = ArenaError;

            pub const Mark = struct {
                index: usize,
            };

            pub const byte_capacity = capacity_bytes;

            pub fn init() Self;

            pub fn assertValid(self: *const Self) void;
            pub fn isValid(self: *const Self) bool;

            pub fn capacity(self: *const Self) usize;
            pub fn used(self: *const Self) usize;
            pub fn remaining(self: *const Self) usize;
            pub fn remainingBytes(self: *Self) []u8;

            pub fn mark(self: *const Self) Mark;
            pub fn restore(self: *Self, checkpoint: Mark) void;
            pub fn reset(self: *Self) void;

            pub fn allocBytes(self: *Self, len: usize) AllocationError![]u8;
            pub fn allocAlignedBytes(
                self: *Self,
                len: usize,
                alignment: usize,
            ) Error![]u8;

            pub fn alloc(self: *Self, comptime T: type) AllocationError!*T;
            pub fn allocSlice(self: *Self, comptime T: type, len: usize) AllocationError![]T;

            pub fn allocator(self: *Self) std.mem.Allocator;
        };
    }
};
```

`Static(N).Mark` is private to a single arena instance. Passing a mark from
a different arena to `restore` is a programmer error. Structural type
equality may permit such cross-arena calls at compile time depending on Zig
anonymous-struct deduplication; runtime assertions catch out-of-range marks
inside `restore`.

`Static(0)` is valid. Every non-zero allocation against `Static(0)`
returns `error.OutOfMemory`. Zero-length byte allocations succeed
without advancing.

## Invariant

A valid `Static(N)` value satisfies:

```zig
self.index <= byte_capacity
```

`init()` returns `.{ .buffer = undefined, .index = 0 }`.

`assertValid` asserts the invariant. `isValid` returns the invariant result.
Operations other than `isValid` and `assertValid` do not run the invariant
check unconditionally.

## Semantics shared with `Arena.Bounded`

All capacity, allocation, mark/restore, reset, and allocator-view semantics
match `Arena.Bounded`. Differences are limited to:

- backing storage is inline rather than borrowed;
- `init()` replaces `wrap(...)`;
- the arena value owns `[N]u8` and must not move while any live allocation
  refers into it.

`allocBytes`, `allocAlignedBytes`, `alloc(T)`, and `allocSlice` use the same
algorithms, error set, and `index`-unchanged-on-error contract as
`Arena.Bounded`.

## Pointer stability and movement

Inline storage lives inside the arena value. The following rules apply:

- the arena value must not move (struct copy, pass-by-value return, function
  argument copy) while any allocation returned from it is still in use;
- copying the arena duplicates the buffer and the current `index`; allocations
  from the copy do not alias the original;
- functions taking ownership of an arena that already has live allocations are
  a programmer error;
- checkpointing uses `mark` and `restore`, not value-copy branching.

Allocations returned by an active arena remain valid until `restore` to an
earlier mark or `reset`, just as in `Arena.Bounded`.

## Allocator view

`allocator()` returns a `std.mem.Allocator` view backed by the same `Static`
state. It uses the same internal VTable shape as `Arena.Bounded`. Allocation,
exhaustion, alignment, and frees-are-no-ops behavior match `Arena.Bounded`.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `init` | none | never | O(1) | none | caller-owned value | none |
| position helpers | none | never | O(1) | none | caller-owned value | none |
| `allocBytes` | inline buffer | never | O(1) | arena index | caller-owned value | byte order only |
| `allocAlignedBytes` | inline buffer | never | O(1) | arena index | caller-owned value | byte order only |
| `alloc(T)` | inline buffer | never | O(1) | arena index | caller-owned value | byte order only |
| `allocSlice` | inline buffer | never | O(1) | arena index | caller-owned value | byte order only |
| `allocator` | inline buffer | never | allocator call | arena index | caller-owned value | byte order only |
| `mark` | none | never | O(1) | none | caller-owned value | none |
| `restore` | none | never | O(1) | later allocations | caller-owned value | none |
| `reset` | none | never | O(1) | all allocations | caller-owned value | none |

These operations perform no heap allocation, waiting, hidden global access,
atomics, barriers, volatile access, target probing, syscalls, locks, or I/O.

## Error behavior

Matches `Arena.Bounded`:

- `allocAlignedBytes` returns `error.InvalidAlignment` for invalid alignment;
- alignment rounding overflow returns `error.Overflow`;
- typed byte-count overflow returns `error.Overflow`;
- insufficient remaining capacity returns `error.OutOfMemory`;
- invalid `T` categories owned by this spec are compile errors where practical;
- invalid marks and corrupted arena state are programmer errors.

All error returns leave `index` unchanged.

## Implementation constraints

Implementation must:

- share the implementation body with `Arena.Bounded` where the algorithm is
  identical, using private helpers over `(buffer: []u8, index: *usize)`;
- never spill inline storage into heap memory;
- never reach into `Bounded`'s storage from `Static`, and vice versa;
- reject `Static(N).Mark` passed to `Bounded.restore` as a compile error where
  practical;
- avoid unconditional invariant scans on hot paths.

## Usage

Inline scratch arena for a parser:

```zig
var arena = stdx.mem.Arena.Static(4096).init();

const tables = try arena.allocSlice(Table, table_count);
```

Speculative parsing rollback:

```zig
var arena = stdx.mem.Arena.Static(8192).init();

const checkpoint = arena.mark();
parseCandidate(&arena) catch |err| {
    arena.restore(checkpoint);
    return err;
};
```

Interop with `std.mem.Allocator`:

```zig
var arena = stdx.mem.Arena.Static(8192).init();

var list = std.ArrayListUnmanaged(u32){};
try list.append(arena.allocator(), 42);
```

Zero-capacity edge case:

```zig
var arena = stdx.mem.Arena.Static(0).init();

try std.testing.expectError(error.OutOfMemory, arena.allocBytes(1));
```

## Planned use

- inline scratch arenas for parse pipelines that prefer no caller-side
  `[N]u8` declaration;
- compile-time-sized arenas for boot-phase or early-firmware scratch where
  the total budget is known statically;
- compile-time-sized arenas for parser fixtures and unit tests.

## Required tests

### Construction and capacity

- `init()` starts with `used() == 0`;
- `capacity()` equals `byte_capacity`;
- `remaining()` equals `byte_capacity` at initialization;
- `Static(0).init()` is valid and reports `capacity() == 0`.

### Byte allocations

- `allocBytes(0)` succeeds and does not advance;
- `allocBytes(n)` returns the next `n` bytes and advances by `n`;
- `allocAlignedBytes` inserts padding as needed;
- invalid alignment returns `error.InvalidAlignment` and leaves `index` unchanged;
- exhaustion returns `error.OutOfMemory` and leaves `index` unchanged;
- `Static(0)` returns `error.OutOfMemory` for any non-zero allocation.

### Typed allocations

- `alloc(u8)`, `alloc(u32)`, and a layout-boundary extern struct succeed;
- returned pointers satisfy `@alignOf(T)`;
- `allocSlice(T, len)` returns `len` elements in contiguous inline storage;
- typed byte-count overflow returns `error.Overflow`;
- zero-sized `T` fails to compile where the compile-fail harness supports it.

### Lifecycle

- `mark` captures the current `index`;
- `restore` returns `index` to the mark and allows reused bytes to be overwritten;
- `reset` returns `index` to zero;
- allocations before a mark keep stable addresses across later allocations.

### Allocator view

- allocator-backed append consumes arena capacity;
- allocator exhaustion returns `error.OutOfMemory`;
- allocator failure leaves arena state unchanged.

### Variant separation

Required when supported by the compile-fail test harness:

- passing a mark from another arena to `restore` is a programmer error,
  caught by the in-range assertion when the index does not match the
  receiving arena's state.

## Open questions

None.
