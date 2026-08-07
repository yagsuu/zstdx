# Bytes access

Status: Approved.

`stdx.bytes` provides overflow-safe, bounds-checked random access to caller-owned byte buffers.

The module provides only the behavior that Zig 0.16 standard primitives do not provide directly:

- a fallible borrowed slice at a runtime offset;
- a fallible, all-or-nothing slice copy at a runtime offset;
- defined behavior for overlapping source and destination slices.

Callers use `std.mem` for fixed-window value conversion and `std.Io.Reader` or `std.Io.Writer` for sequential access.

## Owned scope

This spec owns:

- `bytes.loadSlice`;
- `bytes.storeSlice`;
- overflow-safe bounds checks for runtime offsets and lengths;
- the shared bounds error;
- overlap-safe slice copying;
- no-allocation, no-waiting, and no-hidden-state behavior;
- required tests.

This spec does not own:

- typed value loads or stores;
- native object-representation conversion;
- endian conversion;
- sequential readers, writers, or cursors;
- byte builders or growth policy;
- variable-length integers;
- bit readers or bit writers;
- pointer reinterpretation;
- alignment policy;
- address arithmetic;
- volatile, MMIO, or atomic access;
- diagnostics;
- root exports.

## Public namespace

The helpers and their error set live under `stdx.bytes`:

```zig
stdx.bytes.Error
stdx.bytes.loadSlice
stdx.bytes.storeSlice
```

They are not root-promoted:

```zig
stdx.Error      // not exported
stdx.loadSlice  // not exported
stdx.storeSlice // not exported
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
pub const Error = access.Error;
pub const loadSlice = access.loadSlice;
pub const storeSlice = access.storeSlice;
```

## Approved API

```zig
pub const Error = error{EndOfStream};

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
```

## Bounds semantics

The implementation must verify `offset <= bytes.len` before it computes `bytes.len - offset`.

The implementation must return `error.EndOfStream` when `len > bytes.len - offset`. For `storeSlice`, `len` is `src.len`.

The implementation must not use unchecked `offset + len` arithmetic before these checks. An overflowing or out-of-bounds request must return `error.EndOfStream`.

A zero-length operation at `offset == bytes.len` must succeed. A zero-length operation at `offset > bytes.len` must return `error.EndOfStream`.

## `loadSlice` semantics

After a successful bounds check, `loadSlice(bytes, offset, len)` returns:

```zig
bytes[offset..][0..len]
```

The returned slice borrows from `bytes`. `loadSlice` must not copy the bytes.

## `storeSlice` semantics

After a successful bounds check, `storeSlice(bytes, offset, src)` copies `src` into:

```zig
bytes[offset..][0..src.len]
```

The function must produce `memmove` semantics when `src` overlaps the destination. The function must select the copy direction before it copies the first byte.

The function must not mutate `bytes` when the bounds check fails. An empty `src` must not mutate `bytes`.

## Standard-library composition

Use `std.mem.readInt` and `std.mem.writeInt` for endian-aware integer access after obtaining a checked window:

```zig
const window = try stdx.bytes.loadSlice(table, offset, @sizeOf(u32));
const value = std.mem.readInt(u32, window[0..4], .little);
```

```zig
var encoded: [4]u8 = undefined;
std.mem.writeInt(u32, &encoded, value, .little);
try stdx.bytes.storeSlice(table, offset, &encoded);
```

Use `std.mem.bytesToValue` and `std.mem.toBytes` only when native object-representation semantics are intentional and valid for the type.

Use `std.Io.Reader.fixed` for sequential access to a fixed byte slice. Use `std.Io.Writer.fixed` for sequential writes to a fixed byte buffer.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `loadSlice` | never | never | O(1) | none | caller-owned buffer | none |
| `storeSlice` | never | never | O(`src.len`) | destination window | caller-owned buffer | byte copy order only |

These helpers must not allocate, wait, access hidden globals, target-probe, use atomics, use barriers, or perform volatile access.

Concurrent access to the same mutable buffer requires caller-owned synchronization. The helpers provide no atomicity, fences, or progress guarantee.

## Ownership and lifetime

The caller owns `bytes` and its lifetime. A slice returned by `loadSlice` must not outlive `bytes`.

The helpers never own or free memory.

## Required tests

Tests must verify:

- a full-length load from offset zero;
- an empty load at `bytes.len`;
- an empty store at `bytes.len`;
- `error.EndOfStream` when `offset > bytes.len`;
- `error.EndOfStream` when the requested window exceeds the remaining bytes;
- `error.EndOfStream` for an offset that would make unchecked end arithmetic overflow;
- no destination mutation after a failed store;
- no destination mutation after an empty store;
- preservation of bytes outside the destination window;
- forward-overlap and backward-overlap copy behavior.

## Open questions

None.
