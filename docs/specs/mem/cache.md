# Memory cache-line alignment

Status: Approved.

`stdx.mem` owns two type-level factories that produce cache-line-aligned
wrappers around a payload type. They exist for callers that need to place
individually contended fields on separate cache lines without hand-writing the
`align(...)` + trailing-padding pair at every use site.

## What this spec is

This spec owns:

- `mem.CachePad`;
- `mem.CacheAlign`;
- payload type restrictions;
- alignment source;
- required tests.

## What this spec is not

- allocator alignment policy;
- the concrete numeric cache-line value;
- runtime cache-line probing;
- vector, DMA, or MMIO alignment;
- placement of specific fields inside downstream primitives (each such
  primitive owns whether it uses `CachePad`).

## Public namespace and source ownership

Cache-line alignment factories live under `stdx.mem`:

```zig
stdx.mem.CachePad
stdx.mem.CacheAlign
```

Source ownership:

```text
src/mem.zig
src/mem/cache.zig
```

`src/mem.zig` re-exports:

```zig
pub const cache = @import("mem/cache.zig");

pub const CachePad = cache.CachePad;
pub const CacheAlign = cache.CacheAlign;
```

## API

```zig
pub fn CachePad(comptime T: type) type;
pub fn CacheAlign(comptime T: type) type;
```

Each factory returns a struct type with a single public payload field named
`value: T` (and, for `CachePad`, a single trailing padding field named
`_pad`). No other public declaration is added to the returned type.

### `CachePad(T)` returned type

```zig
pub const Self = struct {
    value: T align(cache_line),
    _pad: [pad_bytes]u8 = [_]u8{0} ** pad_bytes,
};
```

The trailing padding field is named `_pad`. Downstream specs and tests
assert its presence, offset, and size against this exact name; renaming or
omitting `_pad` when `pad_bytes > 0` is a spec violation.

`cache_line` is `std.atomic.cache_line`. `pad_bytes` is the number of bytes
required so that `@sizeOf(Self)` is a whole multiple of `cache_line` and no
smaller wrapper would satisfy that. `pad_bytes` is zero when `@sizeOf(T)` is
already a whole multiple of `cache_line`.

### `CacheAlign(T)` returned type

```zig
pub const Self = struct {
    value: T align(cache_line),
};
```

There is no trailing padding. `@sizeOf(CacheAlign(T))` equals the natural
struct size of a single `T` field with the cache-line alignment attribute.

## Payload type contract

`T` must be a runtime value type accepted as an ordinary struct field with
`@sizeOf(T) > 0`. Zero-sized types and `void` are compile errors where
practical.

`T`'s natural alignment must be less than or equal to `cache_line`. A `T`
whose natural alignment already exceeds `cache_line` is a compile error; such
a type does not need a cache-line wrapper.

The wrappers do not alter `T`'s layout, do not reorder fields, do not add
methods to `T`, and do not participate in `T`'s equality or hashing.

## Alignment source

Both factories use `std.atomic.cache_line` as the alignment value. This spec
does not fix a numeric value and does not add a `stdx` re-export of that
constant. Downstream primitives that need the value read it from `std`
directly.

`std.atomic.cache_line` may vary by target. Wrapping the same `T` at two
different targets may produce different `pad_bytes`. That is intentional.

## Distinction between `CachePad` and `CacheAlign`

`CachePad(T)` guarantees both leading alignment and trailing padding, so that
two adjacent `CachePad(T)` values in memory occupy disjoint sets of cache
lines. This is the primitive used to prevent false sharing between two
independently contended fields inside the same struct.

`CacheAlign(T)` guarantees only leading alignment. Two adjacent
`CacheAlign(T)` values may share a cache line when `@sizeOf(T)` is smaller
than `cache_line`. `CacheAlign` is used when the caller wants a payload to
start at a cache-line boundary but does not need isolation from the next
field.

Callers that need false-sharing isolation must use `CachePad`. `CacheAlign` is
not a substitute.

## Value access

Callers read and write the payload through the `value` field:

```zig
_ = padded.value.fetchAdd(1, .monotonic);
```

There is no `get`, `set`, `ptr`, `payload`, `inner`, `as`, `deref`, or
iterator API. The wrappers are transparent field holders.

### Construction shape

`CachePad(T)` is a one-argument type factory, not a two-argument value
constructor. Downstream specs and callers construct instances by naming the
public `value` field:

```zig
var padded: stdx.mem.CachePad(std.atomic.Value(usize)) = .{
    .value = std.atomic.Value(usize).init(0),
};
```

The trailing `_pad` field takes its declared default (zero-initialized) and
MUST NOT be named at the construction site. Any spec that consumes
`CachePad` cites this construction shape rather than inventing an
`init(value)` helper.

`CachePad` and `CacheAlign` add no methods to the returned type. Every
public reader and writer for the payload goes through the `value` field.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `CachePad` | never | never | comptime | none | type factory | none |
| `CacheAlign` | never | never | comptime | none | type factory | none |

The factories perform no allocation, waiting, hidden global access, atomics,
or barriers. They compute an alignment and, for `CachePad`, a padding size at
comptime.

## Error behavior

- invalid `T` is a compile error;
- `T` whose natural alignment exceeds `cache_line` is a compile error;
- there is no runtime error set.

## Implementation constraints

Implementation must:

- return a plain `struct` type from both factories with `align(std.atomic.cache_line)` on the `value` field;
- for `CachePad`, size the trailing padding so that `@sizeOf(Self) % cache_line == 0`;
- for `CachePad`, omit the trailing padding array when the required padding is zero, or emit a zero-length array; either is acceptable as long as `@sizeOf(Self)` is a whole multiple of `cache_line`;
- name the trailing padding field `_pad` in `CachePad`'s returned type,
  matching the field name downstream specs assert against;
- expose no method, factory, or extra declaration on the returned type
  beyond the `value` and, for `CachePad`, `_pad` fields;
- reject invalid `T` at comptime with a clear message;
- add no runtime code;
- store no metadata beyond the payload field and, for `CachePad`, the padding array.

## Testing
Verification uses comptime layout assertions and runtime payload access for representative scalar, pointer-sized, and atomic payloads. The checks prove alignment, padding, array stride, field names, and atomic composition across target-defined cache-line sizes; compile-fail checks prove the payload restrictions.

Required for a small integer payload (`u32`), a pointer-sized payload
(`usize`), and an atomic payload (`std.atomic.Value(usize)`).

### Alignment

- `@alignOf(CachePad(T)) == std.atomic.cache_line`;
- `@alignOf(CacheAlign(T)) == std.atomic.cache_line`;
- `@offsetOf(CachePad(T), "value") == 0`;
- `@offsetOf(CacheAlign(T), "value") == 0`.
- `@offsetOf(CachePad(T), "_pad")` equals `@sizeOf(T)` rounded up to the
  next multiple of `@alignOf(T)` when the wrapper needs trailing padding;
  the `_pad` field is present in the type;

### `CachePad` sizing

- `@sizeOf(CachePad(T)) % std.atomic.cache_line == 0`;
- `@sizeOf(CachePad(T)) >= std.atomic.cache_line` for at least one payload
  with `@sizeOf(T) <= std.atomic.cache_line`;
- an array `[N]CachePad(T)` places each element at a distinct cache line:
  `(@intFromPtr(&arr[i + 1]) - @intFromPtr(&arr[i])) % std.atomic.cache_line == 0`.

### `CacheAlign` sizing

- `@sizeOf(CacheAlign(T))` equals the natural struct size of a single `T`
  field with `align(std.atomic.cache_line)` applied;
- when `@sizeOf(T) < std.atomic.cache_line`, two adjacent `CacheAlign(T)`
  values in an array may share a cache line; the test asserts that this is
  the observed behavior rather than treating it as isolation.

### Payload access

- writing through `value` and reading it back returns the written value for
  each payload type;
- for the atomic payload, `fetchAdd` composes with `.monotonic` ordering and
  observes prior writes.

### Compile-time and type tests

The test suite instantiates only supported payload types. Rejection of `void`, zero-sized struct payloads, and payload types whose natural alignment exceeds `std.atomic.cache_line` is a compile-time contract and is not exercised by a compile-fail test.
- comptime evaluation works:

```zig
comptime {
    std.debug.assert(@alignOf(stdx.mem.CachePad(u32)) == std.atomic.cache_line);
    std.debug.assert(@sizeOf(stdx.mem.CachePad(u32)) % std.atomic.cache_line == 0);
    std.debug.assert(@alignOf(stdx.mem.CacheAlign(u32)) == std.atomic.cache_line);
}
```
