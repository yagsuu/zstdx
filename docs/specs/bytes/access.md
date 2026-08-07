# Bytes access

Status: Approved.

`stdx.bytes` provides bounds-checked access to byte-slice windows at runtime offsets.

## What this spec is

This spec defines:

- `stdx.bytes.Error`;
- `stdx.bytes.loadSlice` and `stdx.bytes.storeSlice`;
- bounds, overflow, and overlap behavior;
- ownership, lifetime, allocation, waiting, and concurrency behavior; and
- required tests.

## What this spec is not

This spec does not define:

- typed-value or endian conversion;
- sequential access or buffer growth;
- variable-length integer or bit access;
- pointer reinterpretation;
- volatile, MMIO, or atomic access; or
- synchronization policy.

## Public namespace and source ownership

The public declarations are:

```zig
stdx.bytes.Error
stdx.bytes.loadSlice
stdx.bytes.storeSlice
```

`src/bytes/access.zig` implements the declarations. `src/bytes.zig` MUST re-export them as follows:

```zig
pub const access = @import("bytes/access.zig");
pub const Error = access.Error;
pub const loadSlice = access.loadSlice;
pub const storeSlice = access.storeSlice;
```

`test/bytes/access_test.zig` contains the required tests.

## Cross-spec relationships

This API does not convert a byte slice to a typed value. A caller MAY compose a successful `loadSlice` result with a standard-library conversion operation.

This API does not provide sequential access. A caller MAY use `std.Io.Reader` or `std.Io.Writer` for sequential access.

## Global invariants

Each operation MUST preserve the following invariants:

- The operation MUST NOT access bytes outside the requested window.
- The operation MUST NOT allocate or free memory.
- The operation MUST NOT wait, block, sleep, spin, invoke a callback, access hidden mutable state, issue a syscall, or read a clock.
- The operation MUST NOT perform an atomic, volatile, or barrier operation.
- The operation MUST NOT provide synchronization or memory-ordering guarantees.

## API

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

## Bounds contract

For a requested length `len`, an operation succeeds only when:

```zig
offset <= bytes.len and len <= bytes.len - offset
```

The implementation MUST verify `offset <= bytes.len` before it evaluates `bytes.len - offset`. The implementation MUST NOT evaluate unchecked `offset + len` before it verifies the bounds condition.

The operation MUST return `error.EndOfStream` when the bounds condition is false. A zero-length operation at `offset == bytes.len` MUST succeed. A zero-length operation at `offset > bytes.len` MUST return `error.EndOfStream`.

## `loadSlice`

### Contract

On success, `loadSlice(bytes, offset, len)` MUST return:

```zig
bytes[offset..][0..len]
```

The returned slice MUST borrow storage from `bytes`. `loadSlice` MUST NOT copy the requested bytes.

### Errors and fault behavior

`loadSlice` MUST return `error.EndOfStream` when the bounds condition is false.

### Invalidation and lifetime

`loadSlice` MUST NOT invalidate `bytes` or a slice returned by an earlier `loadSlice` call. The caller MUST keep `bytes` alive for the lifetime of each returned slice.

### Complexity and progress

`loadSlice` MUST have O(1) time complexity and MUST NOT wait.

## `storeSlice`

### Contract

On success, `storeSlice(bytes, offset, src)` MUST copy `src` into:

```zig
bytes[offset..][0..src.len]
```

`storeSlice` MUST preserve bytes outside the destination window. When `src` overlaps the destination window, the result MUST be equivalent to `memmove`. An empty `src` MUST NOT mutate `bytes`.

### Errors and fault behavior

`storeSlice` MUST return `error.EndOfStream` when the bounds condition is false. On `error.EndOfStream`, `storeSlice` MUST NOT mutate `bytes`.

### Concurrency effects

The caller MUST externally synchronize concurrent access when at least one access can mutate the same storage.

### Complexity and progress

`storeSlice` MUST have O(`src.len`) time complexity and MUST NOT wait.

## Implementation constraints

The implementation MUST preserve the specified overlap behavior without undefined behavior.

## Testing

Tests MUST call the public operations with observable byte slices and compare returned slices, returned errors, and resulting destination bytes. This method verifies the public contract without depending on private helpers.

### Bounds and errors

Tests MUST exercise a full-length load at offset zero and zero-length load and store operations at `bytes.len`. Tests MUST exercise `offset > bytes.len`, a requested length greater than the remaining length, and an offset that would overflow unchecked end arithmetic. These cases prove the bounds predicate, including its overflow-safe evaluation, and `error.EndOfStream` behavior.

### Mutation and borrowing

Tests MUST compare the complete destination before and after a failing store and an empty store. Tests MUST compare bytes outside a successful destination window. Tests MUST retain a successful load result across a later `loadSlice` call and compare its bytes. These comparisons prove no mutation on error, empty-store behavior, window isolation, and borrowed-slice validity.

### Overlap

Tests MUST perform forward- and backward-overlap stores and compare the complete destination bytes with the corresponding `memmove` result. These cases prove the required copy direction behavior without depending on an implementation helper.
