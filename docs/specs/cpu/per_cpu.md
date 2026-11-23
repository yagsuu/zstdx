# `stdx.cpu.PerCpu`

`stdx.cpu.PerCpu` provides fixed-capacity, cache-line-padded storage indexed by a
caller-supplied CPU index.

In this contract, `Static` means `stdx.cpu.PerCpu.Static(T, count)` and `Bounded`
means `stdx.cpu.PerCpu.Bounded(T)`. `Store` denotes either resulting type.

## Storage and construction

Both variants expose `Padded` as `stdx.layout.cache.CachePad(T)`. Each slot holds
its payload in `Padded.value`. `T` must have nonzero size, must not be `void`, and
must have natural alignment no greater than `std.atomic.cache_line`.

- **slot:** One `Padded` element and its `value` payload, selected by a `usize` CPU index.
- **payload:** The `T` value in a slot's public `Padded.value` field.
- **padded slot:** A `stdx.mem.CachePad(T)` value.

| Variant | Storage | Construction |
| --- | --- | --- |
| `Static` | Inline `[count]Padded`; `count` must be positive at compile time | `Static.init()`, `Static.initFn()`, `Static.initEach()`, `Static.initUndefined()` |
| `Bounded` | Borrowed `[]Padded`; empty storage is valid | `Bounded.wrap()`, `Bounded.wrapFn()`, `Bounded.wrapEach()`, `Bounded.wrapUndefined()` |

`PerCPU` depends on `docs/specs/mem/cache.md` for `stdx.mem.CachePad(T)`. That specification defines the padded-slot layout and the target-dependent `std.atomic.cache_line` alignment value.

Pointers supplied to `Static.initEach()` callbacks MUST NOT outlive the call,
because the initialized storage is returned by value. `Bounded.wrapEach()`
callback pointers refer to the caller's backing storage.

`Static.initUndefined()` leaves payloads undefined. `Bounded.wrapUndefined()`
retains the slice without writing its payloads. The caller MUST initialize each
undefined payload before reading it.

`Static(T, N)` contains inline `[N]Padded` storage. `Bounded(T)` stores a borrowed `[]Padded` slice. For both factories, `Padded` is exactly `stdx.mem.CachePad(T)` and its public `value` field is the payload.

Each padded slot has `@alignOf(Padded)` alignment. Adjacent slots have an address difference of exactly `@sizeOf(Padded)`. `@sizeOf(Padded)` is a multiple of the cache-line size defined by `stdx.mem.CachePad(T)`. Therefore, adjacent slots do not share a cache line on a supported target.

`Store.capacity()` returns `count` for `Static` and the backing-slice length for
`Bounded`. Valid indexes are in `0..Store.capacity()`.

`Store.get(index)` returns `*const T`; `Store.getMut(index)` returns `*T`.
The caller MUST supply a valid index. These operations assert bounds when
`stdx.core.debug.checksEnabled()` is true and remain subject to Zig's bounds-check
policy.

`Store.at(index)` returns `*const T`; `Store.atMut(index)` returns `*T`.
Both return `error.OutOfBounds` without mutation when the index is outside the
valid range, including every index for empty `Bounded` storage.

`Store.slots()` returns `[]const Padded`; `Store.slotsMut()` returns `[]Padded`.
These views cover every slot, preserve padded stride, and expose each payload
through `value`. Capacity, indexed access, and view creation take constant time.

## Lifetime and concurrency

Copying `Static` copies its inline payload storage. Its pointers and views remain
valid only while the originating storage is alive and unmoved. Copying `Bounded`
copies the slice and aliases the same payloads. Its pointers and views remain
valid while the backing storage is alive and unmoved, independently of the
wrapper's location. The caller MUST retain the backing storage for every use of
the wrapper or its aliases.

The caller selects every index and supplies the mapping from CPU identity to
storage. `PerCpu` performs no CPU discovery, topology validation, or automatic
current-CPU selection. Callers that require CPU-local access MUST keep their
execution context consistent with the selected index.

```zig
pub const Padded = stdx.mem.CachePad(T);
pub const Error = error{OutOfBounds};

pub const Padded = stdx.mem.CachePad(T);
The implementation MUST use `stdx.mem.CachePad(T)` as the `Padded` type for both factories. `Static` MUST store `[N]Padded` inline. `Bounded` MUST borrow the supplied `[]Padded` storage and MUST NOT copy, allocate, resize, or free it.