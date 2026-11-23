# `stdx.bytes`

`stdx.bytes.loadSlice()` and `stdx.bytes.storeSlice()` provide bounds-checked
access to byte-slice windows at runtime offsets.

## Bounds and errors

Offsets and lengths use `usize` and count bytes. Both operations accept a
window exactly when:

```zig
offset <= bytes.len and len <= bytes.len - offset
```

Here, `len` is the requested load length or `src.len` for a store.
An invalid window returns `error.EndOfStream` without changing storage.

A zero-length window at `offset == bytes.len` succeeds. A zero-length window
beyond the end returns `error.EndOfStream`.

## Access

| Operation | Successful result |
| --- | --- |
| `stdx.bytes.loadSlice(bytes, offset, len)` | Returns `bytes[offset..][0..len]` as `[]const u8`, without copying |
| `stdx.bytes.storeSlice(bytes, offset, src)` | Copies `src` into `bytes[offset..][0..src.len]`, preserving bytes outside that window |

`stdx.bytes.storeSlice()` supports overlapping source and destination windows
with `memmove` behavior in either direction. An empty source changes no bytes.

A loaded slice borrows the input storage and observes subsequent changes to
that storage. The caller MUST keep the storage alive while the slice is used.
Further loads do not invalidate earlier slices.

For typed values or byte-order conversion, compose these operations with
standard-library conversions or [endian integers](../layout/endian.md).

## Execution and concurrency

`stdx.bytes.loadSlice()` takes O(1) time.
`stdx.bytes.storeSlice()` takes O(`src.len`) time. Neither operation allocates,
waits, or provides atomic, volatile, or synchronization semantics.
The caller MUST synchronize concurrent access when an access can mutate the
same storage.

## References

- [Byte access operations](../../../src/bytes/access.zig)
