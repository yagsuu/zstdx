# CPU per-cpu storage

Status: Approved.

`stdx.cpu.PerCpu` is a fixed-size, cache-line-padded, typed array indexed
by caller-supplied CPU index. It is the storage substrate for per-CPU
state: MPSC/SPSC fan-out per producer core, per-CPU counters, per-CPU
freelists, per-CPU scratch regions for VMCS/HPET/APIC state, per-CPU
trace rings, and any other case where distinct logical CPUs each own a
slot.

`PerCpu` is layout, not semantics. It does not discover CPUs, does not
read the current CPU, does not enforce affinity, and does not order
accesses across slots. Consumers pair `PerCpu` with `arch.<arch>`
primitives (GS-base on x86_64) or a downstream topology layer to route
each CPU to its own slot; that routing is caller policy.

## Owned scope

This spec owns:

- `cpu.PerCpu.Static(T, N)`, comptime-fixed capacity with inline
  storage;
- `cpu.PerCpu.Bounded(T)`, caller-provided backing slice at runtime;
- per-slot cache-line padding via `stdx.mem.CachePad(T)`;
- unchecked accessors `get`, `getPtr` and bounds-checked accessors
  `at`, `atPtr`;
- slot iteration via `slots()` and `slotsConst()` returning
  `[]Padded` / `[]const Padded`;
- capacity and length queries;
- debug-only alignment invariant via `assertValid`;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- CPU discovery, CPU-count queries, or "get my own CPU" helpers;
- affinity policy, core pinning, or migration handling;
- topology decoding (that lives with `arch.<arch>.cpuid` when the arch
  spec approves it);
- atomic accessors — consumers who want per-CPU atomic state wrap
  `stdx.sync.AtomicCell(T)` inside `PerCpu.Static(AtomicCell(T), N)`;
- growth after construction — capacity is fixed; growth would invalidate
  index stability;
- sharded lookup keyed by `index mod capacity` (that is `HashMap` /
  `SlotMap` territory);
- dynamic register/unregister of CPU slots;
- cross-CPU synchronization primitives — `Signal`, `Once`, and
  seq-locks compose atop `PerCpu`, they are not owned here;
- strong `CpuIndex` newtypes — index is `usize` matching every other
  collection.

## Public namespace

`PerCpu` lives under `stdx.cpu`:

```zig
stdx.cpu.PerCpu
stdx.cpu.PerCpu.Static
stdx.cpu.PerCpu.Bounded
```

It is not root-promoted:

```zig
stdx.PerCpu // not exported
```

Source ownership:

```text
src/cpu.zig
src/cpu/per_cpu.zig
test/cpu/per_cpu_test.zig
```

`src/cpu.zig` re-exports:

```zig
pub const per_cpu = @import("cpu/per_cpu.zig");

pub const PerCpu = per_cpu.PerCpu;
```

`src/cpu.zig` is a thin facade. It contains no logic beyond re-exporting
and aliasing.

## Approved API

```zig
pub const PerCpu = struct {
    pub fn Static(comptime T: type, comptime N: usize) type;
    pub fn Bounded(comptime T: type) type;
};
```

Instantiating `Static(T, 0)` is a compile error. A zero-capacity per-CPU
array has no valid consumer; the check keeps the invariant explicit.

### `PerCpu.Static(T, N)` returned type

```zig
pub const Self = struct {
    storage: [N]Padded,

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
};
```

### `PerCpu.Bounded(T)` returned type

```zig
pub const Self = struct {
    slots_backing: []Padded,

    pub const Padded = stdx.mem.CachePad(T);
    pub const Error = error{OutOfBounds};

    pub fn init(backing: []Padded, default: T) Self;
    pub fn initFn(backing: []Padded, comptime make: fn (index: usize) T) Self;
    pub fn initEach(
        backing: []Padded,
        comptime fill: fn (index: usize, slot: *T) void,
    ) Self;
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
};
```

There is no root-level `PerCpu.Padded(T)` alias, no `PerCpu.Iterator`,
no `PerCpu.Atomic(T, N)` sibling, no `pin()`, no `getCurrent()`, and no
`slice() []T` that reinterprets slot storage as an unpadded slice.

## Semantics

### Padded slot type

Each slot's storage type is `stdx.mem.CachePad(T)`, defined by
`docs/specs/mem/cache.md`. `Padded.value` is the payload `T`; the
wrapper enforces alignment such that adjacent slots do not share a
cache line on any target zstdx supports.

`@sizeOf(Padded)` is at least `stdx.mem.CachePad(T)`'s cache-line size
and always a multiple of it. `@alignOf(Padded)` equals that size.

`get(i)` and `at(i)` return the payload in slot `i`. `getPtr(i)` and
`atPtr(i)` return a pointer to the payload in slot `i`. Iterating via
`slots()` yields the padded
slot; consumers access `slot.value` for the payload.

### Initialization

`Static.init(default)` fills every slot's `.value` with `default`.
Use it only when copying `default` into every slot is the intended
initialization. `Static.initFn(make)` calls `make(index)` once per slot and
stores the returned value in that slot. `Static.initEach(fill)` calls
`fill(index, slot_ptr)` once per slot with a pointer to that slot's payload;
it is the preferred shape when the payload has address-sensitive internal
state or when constructing a temporary default value would be misleading.
`Static.initUndefined()` leaves every slot's `.value` undefined; the caller
must write each slot before reading. All static initializers are infallible.

`Bounded.init(backing, default)` stores the backing slice and fills every
slot with `default`. `Bounded.initFn(backing, make)` stores the backing slice
and calls `make(index)` once per slot. `Bounded.initEach(backing, fill)`
stores the backing slice and calls `fill(index, slot_ptr)` once per slot.
`Bounded.initUndefined(backing)` stores the backing slice without writing.

`Bounded`'s `backing` slice must satisfy `Padded`'s alignment. Passing
a mis-aligned slice is a caller contract violation caught by
`assertValid` under `stdx.core.debug.checksEnabled(.build_mode)`.

Copying a `Static` after construction copies the payload storage.
Copying a `Bounded` after construction shares the backing slice; every
copy sees writes performed through any other copy.

### Access

`get(index)` returns `slots[index].value` unchecked. On out-of-bounds
input the behavior is Zig's array-bounds-check policy at the ambient
optimization mode: trap in Debug/ReleaseSafe, undefined in
ReleaseFast/ReleaseSmall. This matches `List.Static.get`.

`getPtr(index)` returns `&slots[index].value` unchecked with the same
policy.

`at(index)` and `atPtr(index)` return `error.OutOfBounds` when
`index >= capacity()` and the corresponding payload / pointer otherwise.
Both are infallible against valid indexes and no-mutation-on-error.

### Iteration

`slots()` returns `slots[0..capacity()]` as `[]Padded`. `slotsConst()`
returns the same with `const`. Idiomatic iteration:

```zig
for (perc.slots()) |*slot| {
    doSomething(&slot.value);
}
```

`slots()` respects the padded stride natively. There is no unpadded
`[]T` slice — Zig slices do not support custom element stride, and
providing an iterator that hides that would obscure the layout the
primitive exists to guarantee.

### Capacity and length

`capacity()` returns `N` on `Static` and `slots_backing.len` on
`Bounded`. `len()` returns the same value. Both are provided for
family-vocabulary consistency with `List.Static` / `Ring.Static`; a
`PerCpu` is always at full capacity in the "slots exist" sense.

### `assertValid`

`assertValid` checks:

- `@intFromPtr(&self.storage[0])` is aligned to `@alignOf(Padded)` for
  `Static`, and the backing slice pointer is aligned to `@alignOf(Padded)`
  for `Bounded`;
- when `capacity() >= 2`, the address difference between adjacent slots
  equals `@sizeOf(Padded)`.

Runs unconditionally when called. Consumers gate the call under
`stdx.core.debug.checksEnabled(.build_mode)` per `core/debug.md`
convention.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `Static.init` / `Static.initUndefined` | never | never | O(N) | value type | none | infallible |
| `Bounded.init` / `Bounded.initUndefined` | never | never | O(N) | value type | none | infallible |
| `capacity` / `len` | never | never | O(1) | reader | none | infallible |
| `get` / `getPtr` | never | never | O(1) | one writer per slot; readers concurrent per Zig atomics | none | infallible; UB on OOB in Release |
| `at` / `atPtr` | never | never | O(1) | one writer per slot; readers concurrent per Zig atomics | none | `error.OutOfBounds` |
| `slots` / `slotsConst` | never | never | O(1) | reader for slice header | none | infallible |
| `assertValid` | never | never | O(1) | reader | none | asserts on layout invariant |

`PerCpu` has no cross-slot concurrency contract. Ordering between slots
is entirely the caller's responsibility; typical use is that each CPU
owns its slot and only that CPU writes it, while other CPUs read via
`getPtr` and observe writes according to the payload type's own
ordering guarantees (atomic type, `AtomicCell(T)`, seqlock, etc.).

The primitive is safe from any execution context including NMI: no
allocation, no lock, no syscall, no target probing.

## std.Io lane

Serves both lanes:

1. Composes inside a downstream `std.Io` backend that maintains
   per-worker state.
2. Serves freestanding consumers (kernel, hypervisor, firmware) that
   own their own CPU indexing.

No `std.Io` equivalent. `std.Thread.getCpuCount()` reports a count, not
storage.

## Examples

Per-CPU counter, freestanding, non-atomic (each CPU writes only its own
slot):

```zig
const stdx = @import("stdx");

var counters = stdx.cpu.PerCpu.Static(u64, 64).init(0);

fn record(cpu: usize) void {
    counters.getPtr(cpu).* += 1;
}

fn total() u64 {
    var sum: u64 = 0;
    for (counters.slotsConst()) |slot| sum += slot.value;
    return sum;
}
```

Per-CPU atomic counter via composition with `AtomicCell`:

```zig
const AtomicU64 = stdx.sync.AtomicCell(u64);
var counters = stdx.cpu.PerCpu.Static(AtomicU64, 64).initFn(initCounter);

fn initCounter(_: usize) AtomicU64 {
    return .init(0);
}

fn record(cpu: usize) void {
    _ = counters.getPtr(cpu).*.fetchAddMonotonic(1);
}

fn snapshot(cpu: usize) u64 {
    return counters.get(cpu).loadAcquire();
}
```

Bounded per-CPU state with runtime capacity:

```zig
var backing: [16]stdx.cpu.PerCpu.Bounded(WorkerState).Padded = undefined;
var workers = stdx.cpu.PerCpu.Bounded(WorkerState).initEach(&backing, initWorker);

fn initWorker(cpu: usize, slot: *WorkerState) void {
    slot.* = WorkerState.init(cpu);
}

const state = workers.atPtr(cpu) catch return error.InvalidCpu;
state.startTask();
```

MPSC fan-out where each producer core has its own SPSC ring feeding a
central consumer:

```zig
const Ring = stdx.concurrent.spsc.Ring.Static(Task, 128);
var rings = stdx.cpu.PerCpu.Static(Ring, 64).initEach(initRing);

fn initRing(cpu: usize, slot: *Ring) void {
    _ = cpu;
    slot.* = Ring.init();
}

fn produce(cpu: usize, task: Task) !void {
    return rings.getPtr(cpu).tryPushBack(task);
}
```

## Required tests

Tests live in `test/cpu/per_cpu_test.zig`.

Required tests:

- Compile-only: `PerCpu.Static(u64, 0)` fails to instantiate with a
  legible message;
- Compile-only: `PerCpu.Static(u64, 4)` has
  `@sizeOf(...) == 4 * @sizeOf(PerCpu.Static(u64, 4).Padded)`;
- Compile-only: `PerCpu.Static(u64, 4).Padded` has alignment matching
  `stdx.mem.CachePad(u64)`;
- Compile-only: address of `perc.storage[1]` minus address of
  `perc.storage[0]` is a multiple of the padded stride;
- Runtime: `Static.init(0)` yields `get(i) == 0` for every `i`;
- Runtime: `Static.initFn(make)` calls `make` once for each slot in index
  order and stores each returned value in the matching slot;
- Runtime: `Static.initEach(fill)` calls `fill` once for each slot in index
  order with a pointer to that slot's payload;
- Runtime: `Static.getPtr(i).* = v` is observable through
  `Static.get(i) == v`;
- Runtime: `Static.at(N)` returns `error.OutOfBounds`; `Static.at(N-1)`
  returns the stored value;
- Runtime: `Static.atPtr(N)` returns `error.OutOfBounds`;
  `Static.atPtr(N-1)` returns a mutable pointer to the slot;
- Runtime: `Bounded.init(backing, 0)` and `Bounded.initUndefined(backing)`
  both use the caller's storage; writes through one `Bounded` are
  visible via another `Bounded` sharing the same backing slice;
- Runtime: `Bounded.initFn(backing, make)` and
  `Bounded.initEach(backing, fill)` initialize the caller's backing storage
  once per slot in index order;
- Runtime: `slots()` yields exactly `capacity()` elements;
  `slots()[i].value` equals `get(i)`;
- Runtime: `assertValid` traps under `checksEnabled(.build_mode)` when
  a `Bounded` is constructed with a hand-crafted mis-aligned backing
  slice;
- Model: `PerCpu.Static(u64, N)` with N threads each incrementing
  `getPtr(thread_id).*` produces a sum equal to `N * K`, demonstrating
  no false sharing across slots (checked by pointer-stride math, not
  by wall-clock timing);
- Model: `PerCpu.Static(AtomicCell(u64), N)` with N producers using
  `fetchAddMonotonic` on their own slot and a reader summing via
  `loadAcquire` observes the correct total when producers signal
  completion via a separate `AtomicCell(bool)` flag;
- Non-x86 build compiles the module.

Tests must not assume any particular thread scheduling; N-thread
stress tests use a large iteration count and the platform's default
scheduling, not a scheduler-controlled harness.

## Open questions

None.
