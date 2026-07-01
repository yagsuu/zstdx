# Bytes access

Status: Approved.

`stdx.bytes` provides bounds-checked random-access load and store primitives
over caller-owned byte buffers. They are the foundation that stateful byte
walkers and builders compose on top of.

The primitives must:

- bounds-check every load and store before reading or writing a single byte;
- detect `offset + len` overflow as an out-of-bounds condition rather than
  silently wrapping the sum;
- compose typed loads with `stdx.bytes.loadUnaligned`;
- compose typed stores with `stdx.bytes.storeUnaligned`;
- never allocate;
- never wait, block, sleep, or spin;
- never access hidden globals;
- never use atomics, barriers, volatile, or syscalls.

## Owned scope

This spec owns:

- random-access typed load and store at a caller-supplied `usize` byte offset;
- random-access byte-slice load and tail extraction at a caller-supplied
  `usize` byte offset;
- random-access byte-slice store from a caller-supplied source slice;
- the shared bounds error mode used by `bytes` primitives;
- composition rules with `stdx.bytes.loadUnaligned` and
  `stdx.bytes.storeUnaligned`;
- no-allocation, no-waiting, and no-hidden-state behavior;
- required tests.

This spec does not own:

- sequential cursor state, position tracking, or checkpointing;
- byte builders, appenders, or growth policy;
- endian-specific method names such as `loadLeU32`;
- variable-length integers;
- bit readers or bit writers;
- pointer reinterpretation outside `bytes.loadUnaligned` and
  `bytes.storeUnaligned`;
- alignment policy;
- address arithmetic;
- volatile or MMIO access;
- atomic access or memory fences;
- domain-specific TLV, package, table, or device-path parsing;
- diagnostics;
- root exports.

## Public namespace

Access helpers live under `stdx.bytes`:

```zig
stdx.bytes.load
stdx.bytes.store
stdx.bytes.loadSlice
stdx.bytes.storeSlice
stdx.bytes.loadTail
```

They are not root-promoted:

```zig
stdx.load        // not exported
stdx.store       // not exported
stdx.loadSlice   // not exported
stdx.storeSlice  // not exported
stdx.loadTail    // not exported
```

Source ownership:

```text
src/bytes.zig
src/bytes/access.zig
test/bytes/access_test.zig
```

`src/bytes.zig` re-exports:

```zig
pub const access = @import("bytes/access.zig");

pub const load = access.load;
pub const store = access.store;
pub const loadSlice = access.loadSlice;
pub const storeSlice = access.storeSlice;
pub const loadTail = access.loadTail;
```

## Approved API

```zig
pub const Error = error{EndOfStream};

pub fn load(
    comptime T: type,
    bytes: []const u8,
    offset: usize,
) Error!T;

pub fn store(
    comptime T: type,
    bytes: []u8,
    offset: usize,
    value: T,
) Error!void;

pub fn loadSlice(
    bytes: []const u8,
    offset: usize,
    len: usize,
) Error![]const u8;

pub fn storeSlice(
    bytes: []u8,
    offset: usize,
    src: []const u8,
) Error!void;

pub fn loadTail(
    bytes: []const u8,
    offset: usize,
) Error![]const u8;
```

## Error mode

The error set is exactly:

```zig
pub const Error = error{EndOfStream};
```

`EndOfStream` is returned when the requested access does not fit within
`bytes`. It is the same error name used by `bytes.Cursor`, so downstream
`try` chains do not require error-set merging when mixing stateful and
random-access reads.

The implementation must not return `EndOfStream` on success and must not
return any other error variant. Programmer-error conditions are not reported
through this error set.

## Bounds semantics

For every operation, the implementation must compute the requested end without
unchecked `offset + len` arithmetic. It may use checked addition or it may
compare the requested length against `bytes.len - offset` after a separate
`offset <= bytes.len` check.

The implementation must not read or write any byte of `bytes` when the bounds
check fails.

A zero-length access at `offset == bytes.len` must succeed.

A zero-length access at `offset > bytes.len` must fail with `EndOfStream`.

`offset + len` overflowing `usize` must fail with `EndOfStream`. Overflow and
buffer overrun are not distinguished by the error set; both indicate that the
requested window does not fit within `bytes`.

## `load(T, ...)` semantics

`load(T, bytes, offset)` returns the value at:

```zig
bytes[offset..][0..@sizeOf(T)]
```

using `stdx.bytes.loadUnaligned(T, window)`, where `window` is a
`*const [@sizeOf(T)]u8` borrow into `bytes`.

The function must:

- inherit the compile-time `T` restrictions of
  `stdx.bytes.loadUnaligned`;
- assemble the `*const [@sizeOf(T)]u8` window only after the bounds check
  succeeds;
- not perform endian conversion;
- not validate value content; callers requiring endian conversion use
  `stdx.layout.Le(T)` or `stdx.layout.Be(T)` as the type argument.

Endian composition:

```zig
const value = (try stdx.bytes.load(stdx.layout.Le(u32), table, offset)).native();
```

## `store(T, ...)` semantics

`store(T, bytes, offset, value)` writes `value` into:

```zig
bytes[offset..][0..@sizeOf(T)]
```

using `stdx.bytes.storeUnaligned(T, window, value)`, where `window` is a
`*[@sizeOf(T)]u8` borrow into `bytes`.

The function must:

- inherit the compile-time `T` restrictions of
  `stdx.bytes.storeUnaligned`;
- assemble the `*[@sizeOf(T)]u8` window only after the bounds check succeeds;
- not perform endian conversion;
- not partially write any byte when the bounds check fails.

Endian composition:

```zig
try stdx.bytes.store(
    stdx.layout.Le(u32),
    table,
    offset,
    stdx.layout.Le(u32).fromNative(value),
);
```

## `loadSlice(...)` semantics

`loadSlice(bytes, offset, len)` returns:

```zig
bytes[offset..][0..len]
```

after verifying that the window fits within `bytes`.

The returned slice borrows from `bytes`. The implementation must not copy
bytes.

A zero-length call must return an empty slice at `offset` when
`offset <= bytes.len`.

## `storeSlice(...)` semantics

`storeSlice(bytes, offset, src)` copies `src` into:

```zig
bytes[offset..][0..src.len]
```

after verifying that the destination window fits within `bytes`.

The copy is byte-wise. The implementation may use `@memcpy` when source and
destination are known to not overlap; it must produce defined behavior when
they do overlap because callers must not rely on aliasing semantics from this
spec.

A zero-length `src` must succeed when `offset <= bytes.len` and must not
mutate `bytes`.

The implementation must not write any byte of `bytes` when the bounds check
fails.

## `loadTail(...)` semantics

`loadTail(bytes, offset)` returns:

```zig
bytes[offset..]
```

when `offset <= bytes.len`, and `EndOfStream` otherwise.

The returned slice borrows from `bytes`. The implementation must not copy
bytes.

`offset == bytes.len` returns an empty slice.

## Composition with `bytes.Cursor` and future builders

`bytes.Cursor` (`docs/specs/bytes/cursor.md`) is the stateful sequential
reader. Its `peek`, `read`, `peekBytes`, `readBytes`, `skip`, and
`remainingBytes` operations may be implemented as thin wrappers over the
random-access primitives in this spec:

```zig
pub fn read(self: *Cursor, comptime T: type) Error!T {
    const value = try stdx.bytes.load(T, self.bytes, self.index);
    self.index += @sizeOf(T);
    return value;
}
```

The implementation choice is internal. The cursor's published contract is
unchanged.

Planned `bytes.Builder` (`docs/specs/project/scope.md`) composes on top of
`store` and `storeSlice` in the same way.

## Behavior contract

| Operation     | Allocation | Waiting | Bounds          | Invalidation       | Concurrency         | Ordering        |
| ---           | ---        | ---     | ---             | ---                | ---                 | ---             |
| `load`        | never      | never   | O(`@sizeOf(T)`) | none               | caller-owned buffer | byte order only |
| `store`       | never      | never   | O(`@sizeOf(T)`) | written bytes only | caller-owned buffer | byte order only |
| `loadSlice`   | never      | never   | O(1)            | none               | caller-owned buffer | none            |
| `storeSlice`  | never      | never   | O(`src.len`)    | written bytes only | caller-owned buffer | byte order only |
| `loadTail`    | never      | never   | O(1)            | none               | caller-owned buffer | none            |

All operations must not allocate, wait, access hidden globals, target-probe,
use atomics, use barriers, or perform volatile access.

`store` and `storeSlice` mutate only the destination window after the bounds
check succeeds; they must not mutate any byte on failure.

## Ownership and lifetime

These primitives borrow `bytes`. They never own or free memory.

The caller owns the lifetime of `bytes`. Returned slices borrow from `bytes`
and must not outlive it.

The caller owns synchronization between writes through `store` /
`storeSlice` and any concurrent reader or writer of `bytes`. This spec
provides no atomicity, fences, volatile semantics, or concurrent progress
guarantees.

## Concurrency and ordering

Concurrent access to the same buffer requires caller-owned external
synchronization. Immutable input bytes may be shared only under the caller's
memory model.

## Debug assertion behavior

`load`, `store`, `loadSlice`, `storeSlice`, and `loadTail` do not assert.
They return `EndOfStream` on out-of-bounds inputs and return the requested
value or slice otherwise.

Programmer-error conditions are limited to the compile-time `T` restrictions
inherited from `bytes.loadUnaligned` and `bytes.storeUnaligned`.

## Usage

### Random-access typed load

```zig
const length = (try stdx.bytes.load(
    stdx.layout.Le(u32),
    table,
    @offsetOf(Header, "length"),
)).native();
```

### Random-access typed store

```zig
try stdx.bytes.store(
    stdx.layout.Le(u32),
    table,
    @offsetOf(Header, "length"),
    stdx.layout.Le(u32).fromNative(length),
);
```

### Variable-length payload after a fixed header

```zig
const payload = try stdx.bytes.loadSlice(
    table,
    @sizeOf(Header),
    length - @sizeOf(Header),
);
```

### Rest of buffer after a parsed prefix

```zig
const rest = try stdx.bytes.loadTail(packet, header_size);
```

### Bulk copy into an output buffer

```zig
try stdx.bytes.storeSlice(output, offset, payload);
```

### Composition with `Cursor`

```zig
var cursor = stdx.bytes.Cursor.wrap(table);
try cursor.skip(@offsetOf(Header, "length"));
const length = (try cursor.read(stdx.layout.Le(u32))).native();

const tail_offset = @sizeOf(Header);
const payload = try stdx.bytes.loadSlice(table, tail_offset, length - tail_offset);
```

## Planned use

- random-access field decode within fixed-layout register or descriptor
  windows where an offset is computed from an external field rather than a
  sequential walk;
- record decode where header fields carry payload offsets that must be read
  before the payload is sliced;
- table body field reads at fixed `@offsetOf` positions inside a validated
  overlay, including revision-gated field reads and header peeks over
  variable-entry subtables;
- payload extraction via `loadSlice` and `loadTail`.

## Required tests

### Construction-free use

- `load`, `store`, `loadSlice`, `storeSlice`, and `loadTail` work directly
  on a `[]u8` or `[]const u8` without constructing a wrapper.

### Bounds — `load(T)` and `store(T)`

- success at `offset == 0`;
- success at `offset == bytes.len - @sizeOf(T)`;
- `EndOfStream` at `offset == bytes.len - @sizeOf(T) + 1`;
- `EndOfStream` at `offset == bytes.len` for non-zero `@sizeOf(T)`;
- `EndOfStream` when `offset + @sizeOf(T)` overflows `usize`;
- on `EndOfStream`, `bytes` is not modified by `store`.

### Bounds — `loadSlice` and `storeSlice`

- success for full-length slice from `offset == 0`;
- success for an empty slice at `offset == bytes.len`;
- success for an empty `src` to `storeSlice` at `offset == bytes.len`;
- `EndOfStream` at `offset == bytes.len + 1`;
- `EndOfStream` when `offset + len` overflows `usize`;
- on `EndOfStream`, `bytes` is not modified by `storeSlice`.

### Bounds — `loadTail`

- `offset == 0` returns the full buffer;
- `offset == bytes.len` returns an empty slice;
- `EndOfStream` at `offset == bytes.len + 1`.

### Typed read and write composition

- `load(u8)` returns the byte at `offset` and matches `bytes[offset]`;
- `load(stdx.layout.Le(u16))` decodes the expected little-endian value at an
  unaligned offset;
- `load(stdx.layout.Be(u32))` decodes the expected big-endian value at an
  unaligned offset;
- round-trip: `store(T, dst, offset, value)` followed by
  `load(T, dst, offset)` yields `value` for `T` covering `u8`, `u16`, `u32`,
  `u64`, `layout.Le(u32)`, and `layout.Be(u32)`;
- typed read and write succeed after a deliberate one-byte offset to confirm
  unaligned composition with `bytes.loadUnaligned` and
  `bytes.storeUnaligned`.

### Slice copy behavior

- `storeSlice` copies the requested bytes and does not touch neighbors;
- `loadSlice` returns a slice with the expected length and starting byte;
- returned slices remain valid across subsequent calls;
- `storeSlice` with an empty `src` does not mutate `bytes`.

### Debug and compile-time behavior

Required when supported by the compile-fail test harness:

- invalid typed-read categories inherit `bytes.loadUnaligned` compile
  failures;
- invalid typed-write categories inherit `bytes.storeUnaligned` compile
  failures.

## Open questions

None.
