# Bytes cursor

Status: Approved.

`zstdx.bytes.Cursor` is a forward read cursor over caller-owned immutable bytes.

It must:

- bounds-check every peek, read, and skip;
- advance only through explicit read or skip operations;
- compose typed reads with `zstdx.layout.unalignedLoad`;
- model checkpoints as ordinary value copies.

## Owned scope

This spec owns:

- `bytes.Cursor`;
- forward read cursor behavior over `[]const u8`;
- byte-window peek, read, skip, and remaining operations;
- typed reads through `layout.unalignedLoad`;
- cursor value-copy checkpointing semantics;
- no-allocation and no-waiting behavior;
- required tests.

This spec does not own:

- mutable or write cursors;
- builders, readers, writers, or append APIs;
- endian-specific method names such as `readLeU32`;
- variable-length integers;
- bit readers or bit writers;
- checksum logic;
- diagnostics;
- pointer reinterpretation;
- volatile or MMIO access;
- domain-specific TLV, package, table, or device-path parsing;
- root exports.

## Public namespace

`Cursor` lives under `zstdx.bytes`:

```zig
zstdx.bytes.Cursor
```

It is not root-promoted:

```zig
zstdx.Cursor // not exported
```

Source ownership:

```text
src/bytes.zig
src/bytes/cursor.zig
test/bytes/cursor_test.zig
```

`src/bytes.zig` re-exports:

```zig
pub const cursor = @import("bytes/cursor.zig");

pub const Cursor = cursor.Cursor;
```

## Approved API

```zig
pub const Cursor = struct {
    bytes: []const u8,
    index: usize = 0,

    pub const Error = error{EndOfStream};

    pub fn init(bytes: []const u8) Cursor;

    pub fn assertValid(self: Cursor) void;
    pub fn isValid(self: Cursor) bool;

    pub fn position(self: Cursor) usize;
    pub fn remaining(self: Cursor) usize;
    pub fn remainingBytes(self: Cursor) []const u8;
    pub fn isEmpty(self: Cursor) bool;

    pub fn peekBytes(self: Cursor, len: usize) Error![]const u8;
    pub fn readBytes(self: *Cursor, len: usize) Error![]const u8;
    pub fn skip(self: *Cursor, len: usize) Error!void;

    pub fn peek(self: Cursor, comptime T: type) Error!T;
    pub fn read(self: *Cursor, comptime T: type) Error!T;
};
```

The API must not include `fork`, `checkpoint`, `restore`, or parser-combinator
methods. Parsers that branch must copy the cursor value.

## Invariant

A valid cursor satisfies:

```zig
cursor.index <= cursor.bytes.len
```

`init(bytes)` returns `.{ .bytes = bytes, .index = 0 }`.

`assertValid` asserts the invariant. `isValid` returns the invariant result.
All operations other than `isValid` and `assertValid` may assert the invariant as
a programmer contract.

## Position and remaining bytes

`position()` returns `index`.

`remaining()` returns `bytes.len - index`.

`remainingBytes()` returns `bytes[index..]`.

`isEmpty()` returns `remaining() == 0`.

These operations do not advance the cursor.

## Byte-window semantics

`peekBytes(len)` returns `bytes[index..][0..len]` without advancing.

`readBytes(len)` returns `bytes[index..][0..len]` and advances `index` by `len`
only after the bounds check succeeds.

`skip(len)` advances `index` by `len` only after the bounds check succeeds.

`len == 0` must be accepted at the start, middle, and end of the input. A
zero-length read returns an empty slice at the current position and does not
advance.

Returned slices borrow from the original input. Cursor movement must not
invalidate previously returned slices.

## Typed read semantics

`peek(T)` reads `@sizeOf(T)` bytes with `layout.unalignedLoad(T, window)` and
does not advance.

`read(T)` reads `@sizeOf(T)` bytes with `layout.unalignedLoad(T, window)` and
advances by `@sizeOf(T)` only after the bounds check succeeds.

The cursor must not perform endian conversion. Endian-aware reads must use
explicit layout types:

```zig
const value = (try cursor.read(zstdx.layout.Le(u32))).native();
```

Invalid `T` categories follow the compile-time rules of `layout.unalignedLoad`.
The cursor must not validate externally supplied byte patterns.

## Error behavior

`peekBytes`, `readBytes`, `skip`, `peek`, and `read` return
`error.EndOfStream` when the requested byte count exceeds `remaining()`.

On `error.EndOfStream`, `index` is unchanged.

Implementations must avoid unchecked `index + len`. Compare the requested length
with `remaining()` or use checked arithmetic.

## Checkpointing and branching

Checkpointing is value copy:

```zig
const start = cursor;

var branch = cursor;
try parseCandidate(&branch);
```

Commit is assignment from the advanced copy:

```zig
cursor = branch;
```

Rollback restores or keeps the original copy:

```zig
cursor = start;
```

Cursor copies must not share hidden state. A copy must not create a parent/child
relationship, ownership transfer, copy-on-write state, or hidden mutation
between cursor values.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `init` | never | never | O(1) | none | caller-owned memory | none |
| position helpers | never | never | O(1) | none | caller-owned memory | none |
| `peekBytes` | never | never | O(1) | none | caller-owned memory | none |
| `readBytes` | never | never | O(1) | cursor index | caller-owned memory | byte order only |
| `skip` | never | never | O(1) | cursor index | caller-owned memory | byte order only |
| `peek(T)` | never | never | O(`@sizeOf(T)`) | none | caller-owned memory | byte order only |
| `read(T)` | never | never | O(`@sizeOf(T)`) | cursor index | caller-owned memory | byte order only |

All operations must not allocate, wait, access hidden globals, target-probe, use
atomics, use barriers, or perform volatile access.

## Ownership and lifetime

`Cursor` borrows `bytes`. It never owns or frees memory.

The caller must keep the original byte slice alive and immutable for the lifetime
of the cursor and any slices returned from it.

## Capacity behavior

Cursor capacity is exactly `bytes.len`. It never grows, reserves, allocates,
compacts, or copies the input buffer.

## Concurrency and ordering

Concurrent access to a cursor value requires caller-owned external
synchronization. Immutable input bytes may be shared only under the caller's
memory model.

The cursor provides deterministic forward byte access only. It provides no
atomicity, fences, volatile semantics, or concurrent progress guarantee.

## Debug assertion behavior

`assertValid` asserts `index <= bytes.len`.

Public operations may call `assertValid` on entry. A corrupted cursor state is a
programmer error, not `error.EndOfStream`.

## Usage

TLV walk:

```zig
var cursor = zstdx.bytes.Cursor.init(bytes);

while (!cursor.isEmpty()) {
    const tag = (try cursor.read(zstdx.layout.Le(u16))).native();
    const len = (try cursor.read(zstdx.layout.Le(u32))).native();
    const payload = try cursor.readBytes(len);

    try handle(tag, payload);
}
```

Unaligned field after a one-byte prefix:

```zig
try cursor.skip(1);
const value = (try cursor.read(zstdx.layout.Le(u16))).native();
```

Fixed header plus byte tail:

```zig
const header = try cursor.read(Header);
const body = try cursor.readBytes(header.body_len);
```

AML-style candidate parse with rollback:

```zig
const start = cursor;

var branch = cursor;
parsePackage(&branch) catch {
    cursor = start;
    return error.InvalidPackage;
};

cursor = branch;
```

## Consumer requirements

- `zvm`: support sequential identity TLV reads and fixed byte-buffer assembly
  checks over manual byte offsets.
- `zfw`: support UEFI variable record name loops and device-path node walking,
  including unaligned little-endian node lengths through `layout.Le(u16)`.
- `zacpi`: support XSDT entry iteration, MADT/DBG2/MCFG variable-entry streams,
  and AML package parsing with value-copy rollback.

## Required tests

### Construction and position

- `init` starts at position zero;
- `remaining` equals the input length at initialization;
- `remainingBytes` returns the original input at initialization;
- `isEmpty` is true for an empty input and false for a non-empty input;
- `len == 0` works at the start, middle, and end.

### Byte windows

- `peekBytes` returns the requested slice and does not advance;
- `readBytes` returns the requested slice and advances;
- `skip` advances without returning bytes;
- returned slices remain valid after later cursor movement;
- `EndOfStream` from `peekBytes`, `readBytes`, and `skip` leaves `index`
  unchanged.

### Typed reads

- `read(u8)` returns the first byte and advances one byte;
- `read(zstdx.layout.Le(u16))` decodes the expected little-endian value;
- `read(zstdx.layout.Be(u32))` decodes the expected big-endian value;
- typed reads work after a deliberate one-byte skip to an unaligned position;
- `peek(T)` returns the same value as the corresponding `read(T)` and does not
  advance;
- `EndOfStream` from `peek(T)` and `read(T)` leaves `index` unchanged.

### Checkpointing

- copying a cursor and reading from the copy leaves the original unchanged;
- assigning the advanced copy back commits progress;
- restoring the original copy rolls progress back.

### Debug and compile-time behavior

Required when supported by the compile-fail test harness:

- `assertValid` succeeds for every public mutation sequence;
- `assertValid` catches a manually corrupted `index`;
- invalid typed-read categories inherit `layout.unalignedLoad` compile failures.

## Open questions

None.
