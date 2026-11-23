# `stdx.cpu.PerCpu`

`stdx.cpu.PerCpu` provides fixed-capacity, cache-line-padded storage indexed by a
caller-supplied CPU index.

In this contract, `Static` means `stdx.cpu.PerCpu.Static(T, count)` and `Bounded`
means `stdx.cpu.PerCpu.Bounded(T)`. `Store` denotes either resulting type.

## Storage and construction

Both variants expose `Padded` as `stdx.layout.cache.CachePad(T)`. Each slot holds
its payload in `Padded.value`. `T` must have nonzero size, must not be `void`, and
must have natural alignment no greater than `std.atomic.cache_line`.

Slots have cache-line alignment and a stride of `@sizeOf(Padded)`, a multiple of
`std.atomic.cache_line`. Adjacent slots occupy disjoint cache lines according to
that target-defined size.

| Variant | Storage | Construction |
| --- | --- | --- |
| `Static` | Inline `[count]Padded`. `count` must be positive at compile time | `Static.init()`, `Static.initFn()`, `Static.initEach()`, `Static.initUndefined()` |
| `Bounded` | Borrowed `[]Padded`. Empty storage is valid | `Bounded.wrap()`, `Bounded.wrapFn()`, `Bounded.wrapEach()`, `Bounded.wrapUndefined()` |

`Static.init(value)` and `Bounded.wrap(items, value)` copy `value` into every
payload. `Static.initFn()` and `Bounded.wrapFn()` call `make(index)` once per slot
in ascending index order and store its result. `Static.initEach()` and
`Bounded.wrapEach()` call `fill(index, slot)` in the same order with a pointer to
each payload. Callbacks are comptime-selected functions and return no error.

Pointers supplied to `Static.initEach()` callbacks MUST NOT outlive the call,
because the initialized storage is returned by value. `Bounded.wrapEach()`
callback pointers refer to the caller's backing storage.

`Static.initUndefined()` leaves payloads undefined. `Bounded.wrapUndefined()`
retains the slice without writing its payloads. The caller MUST initialize each
undefined payload before reading it.

All constructors are infallible and run callbacks synchronously. `PerCpu`
performs no allocation or waiting. Callback effects follow the caller's contract.

## Access and bounds

`Store.capacity()` returns `count` for `Static` and the backing-slice length for
`Bounded`. Valid indexes are in `0..Store.capacity()`.

| Access | Bounds contract |
| --- | --- |
| `Store.get(index)` / `Store.getMut(index)` | Caller MUST supply a valid index. |
| `Store.at(index)` / `Store.atMut(index)` | Return `error.OutOfBounds` without mutation for invalid indexes, including every index in empty bounded storage. |

Each pair returns a const / mutable payload pointer.

`Store.slots()` returns `[]const Padded`. `Store.slotsMut()` returns `[]Padded`.
These views cover every slot, preserve padded stride, and expose each payload
through `value`. Capacity, indexed access, and view creation take constant time.

## Lifetime and concurrency

Copying `Static` copies its inline payload storage. Its pointers and views remain
valid only while the originating storage is alive and unmoved. Copying `Bounded`
copies the slice and aliases the same payloads. Its pointers and views remain
valid while the backing storage is alive and unmoved, independently of the
wrapper's location. The caller MUST retain the backing storage for every use of
the wrapper or its aliases.

Callers supply CPU indexes and MUST keep their execution context consistent with
the selected index when CPU-local access is required.
The caller MUST synchronize conflicting payload access.

## References

- [Per-CPU storage](../../../src/cpu/per_cpu.zig)
- [Cache-line wrappers](../layout/cache.md)
