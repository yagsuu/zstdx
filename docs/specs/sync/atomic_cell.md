# Sync atomic cell

Status: Approved.

`stdx.sync.AtomicCell(T)` is a typed atomic value whose per-method names
encode the memory ordering. It is the shared substrate for lock-free state
words across `Signal.State`, `Once.State`, seqlocks, per-CPU counters, and
future reclamation state.

`AtomicCell` is a value, not a doorbell. It does not wake waiters and does
not participate in wait/wake protocols; primitives that need those
compositions layer on top.

## Owned scope

This spec owns:

- `sync.AtomicCell(T)`, the typed atomic value;
- the approved set of memory-ordering names attached to operations;
- compile-time gate on `T`: the set of value types this primitive supports;
- alignment and size guarantees relative to `std.atomic.Value(T)`;
- an escape hatch onto the underlying `std.atomic.Value(T)` for adoption
  and interop;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- wait/wake surface, park/unpark, or scheduler composition;
- cache-line padding — that is a per-consumer decision (`PerCPU`, MPSC
  slots);
- MMIO ordering — that is owned by `stdx.io.MMIO.Register`;
- architecture-specific fences — callers reach for
  `stdx.arch.x86_64.fence.*` directly when needed;
- hidden retry loops on `cmpxchgWeak` — callers write the loop;
- lock-free containers (stack, queue, deque) — those live in
  `stdx.concurrent`;
- floating-point atomics, `SeqCst` ordering, `Consume` ordering, or arbitrary
  `T` where the target lacks a native atomic width — deferred until a
  consumer justifies each.

## Public namespace

`AtomicCell` lives under `stdx.sync`:

```zig
stdx.sync.AtomicCell
```

Source ownership:

```text
src/sync.zig
src/sync/atomic_cell.zig
test/sync/atomic_cell_test.zig
```

`src/sync.zig` re-exports:

```zig
pub const atomic_cell = @import("sync/atomic_cell.zig");

pub const AtomicCell = atomic_cell.AtomicCell;
```

`src/sync.zig` is a thin facade. It contains no logic beyond re-exporting
and aliasing.

## API

```zig
pub fn AtomicCell(comptime T: type) type;
```

### `AtomicCell(T)` returned type

```zig
pub const Self = struct {
    raw: std.atomic.Value(T),

    pub fn init(value: T) Self;

    pub fn loadAcquire(self: *const Self) T;
    pub fn loadMonotonic(self: *const Self) T;

    pub fn storeRelease(self: *Self, value: T) void;
    pub fn storeMonotonic(self: *Self, value: T) void;

    pub fn swapAcqRel(self: *Self, value: T) T;
    pub fn swapAcquire(self: *Self, value: T) T;
    pub fn swapRelease(self: *Self, value: T) T;
    pub fn swapMonotonic(self: *Self, value: T) T;

    pub fn cmpxchgWeakAcqRel(self: *Self, expected: T, new: T) ?T;
    pub fn cmpxchgStrongAcqRel(self: *Self, expected: T, new: T) ?T;
    pub fn cmpxchgWeakAcquire(self: *Self, expected: T, new: T) ?T;
    pub fn cmpxchgStrongAcquire(self: *Self, expected: T, new: T) ?T;
    pub fn cmpxchgWeakRelease(self: *Self, expected: T, new: T) ?T;
    pub fn cmpxchgStrongRelease(self: *Self, expected: T, new: T) ?T;
    pub fn cmpxchgWeakMonotonic(self: *Self, expected: T, new: T) ?T;
    pub fn cmpxchgStrongMonotonic(self: *Self, expected: T, new: T) ?T;

    // Arithmetic operations — instantiated only when T is a supported integer.
    pub fn fetchAddAcqRel(self: *Self, delta: T) T;
    pub fn fetchAddAcquire(self: *Self, delta: T) T;
    pub fn fetchAddRelease(self: *Self, delta: T) T;
    pub fn fetchAddMonotonic(self: *Self, delta: T) T;
    pub fn fetchSubAcqRel(self: *Self, delta: T) T;
    pub fn fetchSubAcquire(self: *Self, delta: T) T;
    pub fn fetchSubRelease(self: *Self, delta: T) T;
    pub fn fetchSubMonotonic(self: *Self, delta: T) T;
    pub fn fetchAndAcqRel(self: *Self, mask: T) T;
    pub fn fetchAndAcquire(self: *Self, mask: T) T;
    pub fn fetchAndRelease(self: *Self, mask: T) T;
    pub fn fetchAndMonotonic(self: *Self, mask: T) T;
    pub fn fetchOrAcqRel(self: *Self, mask: T) T;
    pub fn fetchOrAcquire(self: *Self, mask: T) T;
    pub fn fetchOrRelease(self: *Self, mask: T) T;
    pub fn fetchOrMonotonic(self: *Self, mask: T) T;
    pub fn fetchXorAcqRel(self: *Self, mask: T) T;
    pub fn fetchXorAcquire(self: *Self, mask: T) T;
    pub fn fetchXorRelease(self: *Self, mask: T) T;
    pub fn fetchXorMonotonic(self: *Self, mask: T) T;

    pub fn fromStd(ptr: *std.atomic.Value(T)) *Self;
    pub fn fromStdConst(ptr: *const std.atomic.Value(T)) *const Self;
};
```

There is no `.acquire`/`.release` order-parameter form. The suffix on each
method is the entire ordering contract for that operation. Adding an
ordering parameter to a method in this spec is a public-API break.

There is no `SeqCst`, `Consume`, or `Unordered` variant. There is no
`fetchMax`, `fetchMin`, or `fetchNand`. There is no `waitForEq` or other
compose-with-backend method. There is no cache-line-padded variant.

## Supported `T`

`AtomicCell(T)` compiles when `T` is one of:

- an integer type (signed or unsigned) whose bit width is a supported
  atomic width on every target the library targets: `u8`, `i8`, `u16`,
  `i16`, `u32`, `i32`, `u64`, `i64`, `usize`, `isize`;
- `bool`;
- an `enum` whose backing integer satisfies the integer rule above;
- a pointer type `*T` or `?*T`;
- a `packed struct` whose backing integer satisfies the integer rule.

Any other `T` (including `f32`, `f64`, non-packed `struct`, `union`, and
integers of a width the target cannot atomicize) is a compile error at
instantiation. The instantiation error message names the disallowed type
category.

Arithmetic operations (`fetchAdd*`, `fetchSub*`, `fetchAnd*`, `fetchOr*`,
`fetchXor*`) are only instantiated when `T` is an integer type. Instantiating
them for `bool`, `enum`, pointer, or `packed struct` `T` is a compile error.

## Semantics

### Initialization

`init(value)` returns a cell holding `value`. It does not publish anything;
until a store or RMW with release-side ordering runs, the cell's initial
value is only visible to code that observes the cell after a
happens-before edge established elsewhere.

### Loads

`loadAcquire(self)` performs an acquire load. Every subsequent read on the
same thread that is data-dependent on the returned value observes the
release-paired writes from the last producer.

`loadMonotonic(self)` performs a monotonic (relaxed) load. It does not
establish a synchronizes-with edge and is intended for statistics reads,
sole-writer reader paths, and heuristics.

### Stores

`storeRelease(self, value)` performs a release store. Writes preceding the
store on the same thread are visible to threads that acquire-load the same
cell.

`storeMonotonic(self, value)` performs a monotonic store. It does not
establish a synchronizes-with edge.

### Swaps

`swapAcqRel(self, value)` performs an acquire-release exchange and returns
the previous value. `swapAcquire`, `swapRelease`, and `swapMonotonic` are
one-sided or unordered variants for callers who need only half the fence
or none at all.

### Compare-and-exchange

`cmpxchgWeakAcqRel(self, expected, new)` performs a weak compare-and-swap:
if the current value equals `expected`, replace it with `new` and return
`null`; otherwise leave the cell unchanged and return the currently
observed value. Weak CAS is allowed to fail spuriously; callers loop.

`cmpxchgStrongAcqRel` returns the same shape but does not fail spuriously.

The `Acquire`, `Release`, and `Monotonic` variants weaken the ordering of the
success path in the same way as `std.atomic.Value.cmpxchg*`. Failure ordering
never includes release semantics: `AcqRel` fails with acquire ordering,
`Acquire` fails with acquire ordering, `Release` fails with monotonic ordering,
and `Monotonic` fails with monotonic ordering.

### Arithmetic

`fetchAdd*(self, delta)` atomically adds `delta` to the cell and returns
the value observed before the add. The suffix selects the operation ordering:
`AcqRel`, `Acquire`, `Release`, or `Monotonic`. Overflow is defined by Zig's
usual arithmetic rules on `T`: signed overflow is UB in Debug/ReleaseSafe and
wraps in ReleaseFast/ReleaseSmall; unsigned wraps. Callers responsible for
saturation implement it via CAS loops.

`fetchSub*`, `fetchAnd*`, `fetchOr*`, `fetchXor*` follow the same pattern
against subtraction and bitwise operations with the same four ordering suffixes.

### Interop with `std.atomic.Value`

`AtomicCell(T)` is layout-compatible with `std.atomic.Value(T)`. The
struct contains exactly one field named `raw` of type
`std.atomic.Value(T)`; no padding, no extra field.

`fromStd(ptr)` and `fromStdConst(ptr)` return an `*AtomicCell(T)` /
`*const AtomicCell(T)` pointing at the same storage. The reinterpret is
zero cost. Callers who own a `std.atomic.Value(T)` (for example, inside
existing state that already migrated) can adopt `AtomicCell` methods
without moving the storage.

The `raw` field is public. Callers who need an escape hatch to an ordering
this spec does not name can operate on `cell.raw` directly. Doing so opts
out of this spec's ordering guarantees for that operation.

## Alignment and size

`@sizeOf(AtomicCell(T)) == @sizeOf(std.atomic.Value(T))`.

`@alignOf(AtomicCell(T)) == @alignOf(std.atomic.Value(T))`.

`AtomicCell(T)` performs no forced padding. Callers who need cache-line
isolation wrap `AtomicCell(T)` in a padded struct or use a higher-level
primitive (`PerCPU`, MPSC ring slot) that provides padding.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `init` | never | never | O(1) | value type | none | infallible |
| `loadAcquire` | never | never | O(1) | reader | acquire | infallible |
| `loadMonotonic` | never | never | O(1) | reader | monotonic | infallible |
| `storeRelease` | never | never | O(1) | writer | release | infallible |
| `storeMonotonic` | never | never | O(1) | writer | monotonic | infallible |
| `swapAcqRel` | never | never | O(1) | RMW | acq-rel | infallible |
| `swapAcquire` | never | never | O(1) | RMW | acquire | infallible |
| `swapRelease` | never | never | O(1) | RMW | release | infallible |
| `swapMonotonic` | never | never | O(1) | RMW | monotonic | infallible |
| `cmpxchgWeakAcqRel` | never | never | O(1) | RMW | acq-rel on success, acquire on failure | infallible |
| `cmpxchgStrongAcqRel` | never | never | O(1) | RMW | acq-rel on success, acquire on failure | infallible |
| `cmpxchgWeakAcquire` | never | never | O(1) | RMW | acquire on success and failure | infallible |
| `cmpxchgStrongAcquire` | never | never | O(1) | RMW | acquire on success and failure | infallible |
| `cmpxchgWeakRelease` | never | never | O(1) | RMW | release on success, monotonic on failure | infallible |
| `cmpxchgStrongRelease` | never | never | O(1) | RMW | release on success, monotonic on failure | infallible |
| `cmpxchgWeakMonotonic` | never | never | O(1) | RMW | monotonic | infallible |
| `cmpxchgStrongMonotonic` | never | never | O(1) | RMW | monotonic | infallible |
| `fetchAdd*`, `fetchSub*`, `fetchAnd*`, `fetchOr*`, `fetchXor*` AcqRel variants | never | never | O(1) | RMW | acq-rel | infallible; wrap per Zig arithmetic |
| `fetchAdd*`, `fetchSub*`, `fetchAnd*`, `fetchOr*`, `fetchXor*` Acquire variants | never | never | O(1) | RMW | acquire | infallible; wrap per Zig arithmetic |
| `fetchAdd*`, `fetchSub*`, `fetchAnd*`, `fetchOr*`, `fetchXor*` Release variants | never | never | O(1) | RMW | release | infallible; wrap per Zig arithmetic |
| `fetchAdd*`, `fetchSub*`, `fetchAnd*`, `fetchOr*`, `fetchXor*` Monotonic variants | never | never | O(1) | RMW | monotonic | infallible; wrap per Zig arithmetic |
| `fromStd` / `fromStdConst` | never | never | O(1) | value type | none | infallible |

`AtomicCell` is safe from any execution context including NMI. It performs
no allocation, no locking, no syscall, and no target probing.

## Debug assertion behavior

`AtomicCell` has no cross-field invariant and provides no `assertValid`.
The struct is a single atomic field; there is no invariant to check.

Consumers that embed `AtomicCell(T)` inside a larger struct may add
comptime alignment or size checks in the enclosing type. This spec does
not centralize such checks.

## std.Io lane

Not a `std.Io` primitive. `AtomicCell` is a memory-model primitive,
orthogonal to any runtime.

## Examples

Publishing a payload through a release store:

```zig
const stdx = @import("stdx");

var flag: stdx.sync.AtomicCell(bool) = .init(false);
var payload: u64 = undefined;

fn producer() void {
    payload = compute();
    flag.storeRelease(true);
}

fn consumer() void {
    while (!flag.loadAcquire()) {
        std.atomic.spinLoopHint();
    }
    use(payload);
}
```

Counter with monotonic increment and acquire-release publication of a
snapshot:

```zig
var counter: stdx.sync.AtomicCell(u64) = .init(0);
var snapshot_ready: stdx.sync.AtomicCell(bool) = .init(false);

fn record() void {
    _ = counter.fetchAddMonotonic(1);
}

fn publishSnapshot() void {
    snapshot_ready.storeRelease(true);
}
```

CAS loop for a monotone maximum:

```zig
var max_seen: stdx.sync.AtomicCell(u32) = .init(0);

fn observe(value: u32) void {
    var current = max_seen.loadMonotonic();
    while (value > current) {
        if (max_seen.cmpxchgWeakAcqRel(current, value)) |observed| {
            current = observed;
        } else {
            return;
        }
    }
}
```

Interop with an existing `std.atomic.Value`:

```zig
var std_cell: std.atomic.Value(u32) = .init(0);
const cell = stdx.sync.AtomicCell(u32).fromStd(&std_cell);
cell.storeRelease(7);
```

## Testing

Compile-time tests MUST verify the size and alignment equivalence with `std.atomic.Value(T)`, the supported and rejected `T` categories, and that arithmetic operations are available only for integer cells. These tests prove the representation and type-gating contracts.

Deterministic operation tests MUST verify initialization, each load and store ordering family, swaps, compare-and-exchange success and mismatch behavior, all arithmetic operation families, and `fromStd` aliasing. Mismatch tests MUST verify that compare-and-exchange leaves the cell unchanged. Weak-CAS tests MUST retry after every reported observed value. These tests prove returned values, state transitions, no-mutation-on-mismatch, and interoperation with the underlying storage.

Memory-model tests MUST publish a payload before a release store and read it after an acquire load that observes the publication. The reader MUST observe the payload. This test proves the required release/acquire synchronizes-with edge.

Stress tests MUST run concurrent monotonic read-modify-write operations and verify the exact final value. They exercise contention without asserting an ordering that monotonic operations do not provide. Cross-target compilation MUST include a non-x86 target.
