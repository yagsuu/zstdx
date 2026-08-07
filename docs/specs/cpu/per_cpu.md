# CPU per-CPU storage

Status: Approved.

`stdx.cpu.PerCPU` provides fixed-capacity, cache-line-padded storage for one typed value per caller-selected CPU index.

## What this spec is

This spec owns `stdx.cpu.PerCPU`, its `Static` and `Bounded` type factories, padded slot representation, initialization, indexed access, padded-slot views, layout validation, and their required tests.

`Static(T, N)` owns inline storage for exactly `N` slots. `Bounded(T)` borrows a caller-provided slice of padded slots.

## What this spec is not

This spec does not own CPU discovery, CPU-count queries, current-CPU lookup, affinity, migration handling, topology decoding, CPU-slot registration, or index validation policy.

This spec does not provide atomic accessors or cross-CPU synchronization. Callers that require atomic payload access can use `stdx.sync.AtomicCell(T)` as `T`. This spec does not provide growth, sharded lookup, an unpadded `[]T` view, a `PerCPU.Atomic` type, `pin`, or `getCurrent`.

## Terminology

- **slot:** One `Padded` element and its `value` payload, selected by a `usize` CPU index.
- **payload:** The `T` value in a slot's public `Padded.value` field.
- **padded slot:** A `stdx.mem.CachePad(T)` value.

## Public namespace and source ownership

The public namespace is:

```zig
stdx.cpu.PerCPU
stdx.cpu.PerCPU.Static
stdx.cpu.PerCPU.Bounded
```

The owning files are:

```text
src/cpu.zig
src/cpu/per_cpu.zig
test/cpu/per_cpu_test.zig
```

`src/cpu.zig` is a thin facade. It re-exports `cpu/per_cpu.zig` as `per_cpu` and re-exports `per_cpu.PerCPU` as `PerCPU`. It contains no implementation logic.

## Cross-spec relationships

`PerCPU` depends on `docs/specs/mem/cache.md` for `stdx.mem.CachePad(T)`. That specification defines the padded-slot layout and the target-dependent `std.atomic.cache_line` alignment value.

`PerCPU` composes with synchronization primitives, including `stdx.sync.AtomicCell(T)`, but does not own their atomic ordering or synchronization contracts. Callers can combine `PerCPU` with architecture-specific current-CPU or topology mechanisms, but those mechanisms select indexes outside this contract.

## Data structures and representation

`Static(T, N)` contains inline `[N]Padded` storage. `Bounded(T)` stores a borrowed `[]Padded` slice. For both factories, `Padded` is exactly `stdx.mem.CachePad(T)` and its public `value` field is the payload.

Each padded slot has `@alignOf(Padded)` alignment. Adjacent slots have an address difference of exactly `@sizeOf(Padded)`. `@sizeOf(Padded)` is a multiple of the cache-line size defined by `stdx.mem.CachePad(T)`. Therefore, adjacent slots do not share a cache line on a supported target.

The cache-line size can vary by target. This specification does not define a numeric cache-line size, a CPU count, a CPU numbering scheme, or a mapping from hardware CPUs to indexes.

## Global invariants

- `Static(T, N)` accepts only `N > 0`; `Static(T, 0)` is a compile error.
- A `Static` instance has exactly `N` slots for its lifetime.
- A `Bounded` instance has exactly `backing.len` slots for the lifetime of its borrowed backing slice.
- `capacity()` and `len()` return the same value.
- Every valid index is in the half-open range `0..capacity()`.
- An initializer that writes payloads processes each slot once in ascending index order.
- `at` and `atPtr` do not mutate storage when they return `error.OutOfBounds`.
- `PerCPU` performs no CPU discovery, target probing, allocation, waiting, locking, system calls, scheduler calls, callbacks other than the initializer supplied by the caller, atomic operation, or memory barrier.

## API

```zig
pub const PerCPU = struct {
    pub fn Static(comptime T: type, comptime N: usize) type;
    pub fn Bounded(comptime T: type) type;
};
```

### `PerCPU.Static(T, N)`

`Static` returns a type with the following public declarations:

```zig
pub const Padded = stdx.mem.CachePad(T);
pub const Error = error{OutOfBounds};

pub fn init(default: T) Self;
pub fn initFn(comptime make: fn (index: usize) T) Self;
pub fn initEach(comptime fill: fn (index: usize, slot: *T) void) Self;
pub fn initUndefined() Self;

pub fn capacity(self: *const Self) usize;
pub fn len(self: *const Self) usize;

pub fn get(self: *const Self, index: usize) T;
pub fn getPtr(self: *Self, index: usize) *T;
pub fn at(self: *const Self, index: usize) Error!T;
pub fn atPtr(self: *Self, index: usize) Error!*T;

pub fn slots(self: *Self) []Padded;
pub fn slotsConst(self: *const Self) []const Padded;
pub fn assertValid(self: *const Self) void;
```

### `PerCPU.Bounded(T)`

`Bounded` returns a type with the following public declarations:

```zig
pub const Padded = stdx.mem.CachePad(T);
pub const Error = error{OutOfBounds};

pub fn init(backing: []Padded, default: T) Self;
pub fn initFn(backing: []Padded, comptime make: fn (index: usize) T) Self;
pub fn initEach(backing: []Padded, comptime fill: fn (index: usize, slot: *T) void) Self;
pub fn initUndefined(backing: []Padded) Self;

pub fn capacity(self: *const Self) usize;
pub fn len(self: *const Self) usize;

pub fn get(self: *const Self, index: usize) T;
pub fn getPtr(self: *Self, index: usize) *T;
pub fn at(self: *const Self, index: usize) Error!T;
pub fn atPtr(self: *Self, index: usize) Error!*T;

pub fn slots(self: *Self) []Padded;
pub fn slotsConst(self: *const Self) []const Padded;
pub fn assertValid(self: *const Self) void;
```

There is no root-level `PerCPU.Padded(T)` alias, iterator type, `slice() []T` method, atomic sibling type, CPU-pinning method, or current-CPU accessor.

### Initialization

`Static.init(default)` MUST copy `default` into every slot payload.

`Static.initFn(make)` MUST call `make(index)` once for each index in ascending order. `Static.initFn(make)` MUST store each returned value in that index's payload.

`Static.initEach(fill)` MUST call `fill(index, slot)` once for each index in ascending order. The `slot` argument MUST point to that index's payload.

`Static.initUndefined()` leaves every payload undefined. The caller MUST write a payload before reading it.

`Bounded.init`, `Bounded.initFn`, `Bounded.initEach`, and `Bounded.initUndefined` have the corresponding `Static` initialization behavior. Each `Bounded` initializer MUST retain the supplied backing slice. `Bounded.initUndefined(backing)` MUST not write the backing payloads.

All initializers are infallible. They allocate and wait never. `make` and `fill` are the only callbacks that an initializer invokes.

A `Bounded` caller MUST provide a `backing` slice aligned for `Padded`. The caller MUST keep the backing storage alive for every use of the returned `Bounded` value and all views and pointers derived from it. A zero-length `backing` slice is valid.

Copying a `Static` copies its payload storage. Copying a `Bounded` copies the borrowed slice; copies observe the same backing storage.

### Indexed access

The caller selects every `index`; `PerCPU` does not translate, validate against CPU topology, or associate an index with the current CPU.

`get(index)` returns the payload at `index`. `getPtr(index)` returns a mutable pointer to the payload at `index`. Both operations require `index < capacity()`. When the caller violates that precondition, their behavior follows the ambient Zig bounds-check policy: the operation traps in Debug and ReleaseSafe builds and has undefined behavior in ReleaseFast and ReleaseSmall builds.

`at(index)` returns the payload at `index` when `index < capacity()`. Otherwise, it returns `error.OutOfBounds` without mutation. `atPtr(index)` returns a mutable pointer to the payload at `index` when `index < capacity()`. Otherwise, it returns `error.OutOfBounds` without mutation.

The accessors allocate and wait never. They provide no synchronization or memory ordering. A caller MUST synchronize conflicting access to the same payload according to `T`'s contract and Zig's concurrency rules. Accesses to different slots are accesses to distinct padded-slot storage, but `PerCPU` does not establish ordering between them.

A pointer returned by `getPtr` or `atPtr`, and a slice returned by `slots` or `slotsConst`, remains valid only while its originating `PerCPU` storage remains alive and unmoved. For `Bounded`, validity also requires that the caller retain the backing storage. A subsequent payload write changes the value observed through all aliases to that payload.

### Padded-slot views

`slots()` returns every slot as a mutable `[]Padded`. `slotsConst()` returns the same slots as `[]const Padded`. The slices have length `capacity()`, preserve padded-slot stride, and expose payloads as `slot.value`.

The API provides no `[]T` view. The caller MUST access a payload in a padded-slot view through `value`.

### Capacity and validation

`capacity()` returns `N` for `Static` and the backing-slice length for `Bounded`. `len()` returns the same value. Both operations are `O(1)`, infallible, non-allocating, and non-waiting.

`assertValid()` asserts that the slot-storage base is aligned to `@alignOf(Padded)`. When at least two slots exist, it also asserts that the first two slots are exactly `@sizeOf(Padded)` bytes apart. `assertValid()` runs its assertions whenever the caller invokes it; the caller can gate the invocation with `stdx.core.debug.checksEnabled(.build_mode)`.

## Implementation constraints

The implementation MUST use `stdx.mem.CachePad(T)` as the `Padded` type for both factories. `Static` MUST store `[N]Padded` inline. `Bounded` MUST borrow the supplied `[]Padded` storage and MUST NOT copy, allocate, resize, or free it.

The implementation MUST call `make` and `fill` in ascending index order exactly once per slot. It MUST return `error.OutOfBounds` from checked accessors when `index >= capacity()` without modifying storage. It MUST preserve the padded representation when it returns a slot view or payload pointer.

The implementation MUST remain target-independent: it MUST NOT read CPU identity, probe target topology, require x86 instructions, or depend on a target-specific CPU-count facility.

## Testing

Tests in `test/cpu/per_cpu_test.zig` must verify the production contract rather than test names or private helpers.

Layout tests must instantiate legal `Static` shapes and verify that inline storage size, `Padded` alignment, and adjacent payload-pointer stride match `CachePad`. These checks prove that each slot has the required padded representation without relying on timing measurements. A compile-fail check must verify that `Static(u64, 0)` is rejected with a legible capacity error.

Initialization tests must verify that each initializer writes the required payloads, that callback initializers invoke their callback once per slot in ascending index order, and that undefined initialization is written before it is read. Equivalent tests for `Bounded` must verify that initialization uses the caller's storage and that copies sharing a backing slice observe each other's writes.

Access tests must verify the first valid index, the last valid index, and the exclusive `capacity()` boundary. They must verify that `at` and `atPtr` return `error.OutOfBounds` at and above that boundary without mutation, that checked pointers mutate the selected payload, and that padded-slot views have length `capacity()` and expose the same payloads as indexed access.

Validation tests must verify that `assertValid` succeeds for aligned `Static` and `Bounded` storage. A misaligned hand-constructed `Bounded` slice must demonstrate the violated alignment precondition; a test that executes the expected assertion trap must isolate that trap from the normal test process.

A concurrency model test may use one writer per distinct non-atomic slot and verify the final sum after all writers join. The test must verify padded stride structurally and must not use wall-clock timing to infer false-sharing behavior. A separate atomic-payload model test must use the payload type's documented synchronization operations and a completion edge before a reader sums the slots. Stress tests must not assume thread scheduling.

A target-independence compilation test must instantiate both factories without x86-specific behavior. This proves that the module has no architectural CPU-discovery dependency.
