# `stdx.layout.CacheAlign` / `stdx.layout.CachePad`

Type factories that wrap a payload with target-defined cache-line alignment.

## Payload and target

Both factories require a payload type `T` that can be an ordinary runtime
struct field. `void`, zero-sized payloads, and payloads with
`@alignOf(T) > std.atomic.cache_line` are compile errors.

Both wrappers use the target-defined `std.atomic.cache_line` for alignment.
Wrapper size, alignment, and padding can differ between targets.

## Representation and construction

| Property | `layout.CacheAlign(T)` | `layout.CachePad(T)` |
| --- | --- | --- |
| Payload | `value: T` with cache-line alignment. No default | Same |
| Explicit padding | None | `_pad: [pad]u8`, with a zero-filled default, including when `pad == 0` |
| Padding length | — | `0` when `@sizeOf(T)` is a cache-line multiple. Otherwise `std.atomic.cache_line - (@sizeOf(T) % std.atomic.cache_line)` |
| Wrapper alignment | `std.atomic.cache_line` | Same |
| Wrapper size | Size of a single-field struct with the stated alignment, including implicit trailing padding | Size of the aligned payload and explicit padding, rounded to the wrapper alignment |

Arrays of either wrapper have a cache-line-multiple stride. Adjacent elements do
not share cache lines under the target-defined model.

The factories operate at comptime without runtime allocation or waiting.
The caller manages payload ownership and lifetime and synchronizes concurrent
access according to `T`'s rules.

## References

- [Cache-line wrappers](../../../src/layout/cache.zig)
