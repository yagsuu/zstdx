# `stdx.bits.Word`

Single-integer bit words. `Word` below denotes `stdx.bits.Word(T)`.

`T` MUST be a positive-width unsigned integer type. Other types, including `u0`,
are compile errors. Non-power-of-two widths are supported.
`Word` is an enum backed by `T`. `Word.width` is the bit width.
`Word.size` is the native storage size in bytes, which can include padding
for non-power-of-two widths.

## Operations

| Operation or value | Contract |
| --- | --- |
| `Word.zero` / `Word.full` | No bits / all `Word.width` bits set. |
| `Word.from(value)` / `Word.raw()` | Convert between `T` and `Word` without changing bits. Every `T` value is valid. |
| `Word.wordsFor(bit_count)` | Returns `ceil(bit_count / Word.width)` for every `usize` input. |
| `Word.maskOf(index)` | Returns `T` with only bit `index` set. |
| `Word.isSet(index)` | Returns whether bit `index` is set. |
| `Word.set(index)` / `Word.unset(index)` | Set / clear only bit `index`. |
| `Word.toggle(index)` | Inverts only bit `index`. |

Indexes are zero-based `usize` values and MUST be less than `Word.width`.

All operations support comptime evaluation and take O(1) time without allocation
or waiting.
Callers MUST externally synchronize concurrent mutable access. Word operations
establish no memory ordering.

## References

- [Word values and operations](../../../src/bits/word.zig)
- [Mask construction](mask.md)
- [Fixed-capacity bit sets](set.md)
