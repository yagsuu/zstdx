# `stdx.bits.mask`

Low-bit, single-bit, and inclusive bit-range masks.

`T` MUST be a positive-width unsigned integer type. Other types, including `u0`,
are compile errors. Non-power-of-two widths are supported.

| Operation | Caller requirements | Result |
| --- | --- | --- |
| `mask.low(T, count)` | `0 <= count <= @bitSizeOf(T)` | Lowest `count` bits set. Zero for zero count and all ones for full width. |
| `mask.single(T, index)` | `index < @bitSizeOf(T)` | Only bit `index` set. |
| `mask.range(T, first, last)` | `first <= last < @bitSizeOf(T)` | Bits `first` through `last`, inclusive, set. Full-width ranges return all ones. |

Counts and positions use `usize`. Positions are zero-based.

All operations support comptime evaluation and take O(1) time without allocation
or waiting.

## References

- [Mask construction](../../../src/bits/mask.zig)
- [Single-integer bit words](word.md)
