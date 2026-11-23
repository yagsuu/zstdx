# `stdx.core.debug`

`debug.checksEnabled()` reports whether the stdx module's Zig build mode enables
optional checks. The result is evaluable at compile time.

| Build mode | `debug.checksEnabled()` |
| --- | --- |
| Debug | `true` |
| ReleaseSafe | `true` |
| ReleaseFast | `false` |
| ReleaseSmall | `false` |

Callers MUST branch on `debug.checksEnabled()` before evaluating an optional
predicate or validation scan that must be omitted when checks are disabled.

## References

- [Build-mode checks](../../../src/core/debug.zig)
