# `stdx.layout.EndianInt`

`stdx.layout.EndianInt(T, endian)` stores an unsigned integer in an explicit
byte order. `stdx.layout.Le(T)` selects `.little`.
`stdx.layout.Be(T)` selects `.big`.

## Integer domain

`T` must be an unsigned integer with a bit width divisible by 8, from 8 through
128 inclusive. Unsupported types, including target-sized types `usize` and
`isize`, cause a compile error.

## Representation

Here, `E` denotes an instantiated endian integer type.
Each `E` is an `extern struct` whose only instance field is
`bytes: [E.size]u8`, where `E.size` is `@bitSizeOf(T) / 8`.

`@sizeOf(E) == E.size` and `@alignOf(E) == 1`. The representation has no
padding, including for integer types such as `u24` whose native storage size
can exceed their bit width. Endian fields impose no additional alignment in
an enclosing `extern struct`.

For `.little`, `bytes[0]` holds the least-significant byte. For `.big`,
`bytes[0]` holds the most-significant byte, regardless of target native endianness.
Every byte pattern represents a valid `T` value.

## Native conversion

| Operation | Result |
| --- | --- |
| `E.from(value)` | Encodes a `T` value into `bytes` in `E.order` |
| `E.native()` | Decodes `bytes` in `E.order` and returns `T` |

Conversions are infallible and take O(`E.size`) time without allocation or waiting.

The exact byte representation composes with `std.mem.toBytes` and
`std.mem.bytesToValue`. Use [byte access](../bytes/access.md) when a byte window
requires runtime bounds checks.

## References

- [Endian integer types](../../../src/layout/endian.zig)
