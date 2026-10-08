# Core debug

Status: Approved.

`stdx.core.debug.checksEnabled()` reports whether the stdx module's Zig build mode enables optional checks.

## API

```zig
pub fn checksEnabled() bool;
```

The result MUST be computed from `@import("builtin").mode` and MUST be evaluable at compile time.

| Build mode | Result |
| --- | --- |
| Debug | `true` |
| ReleaseSafe | `true` |
| ReleaseFast | `false` |
| ReleaseSmall | `false` |

A caller MUST branch on `checksEnabled()` before evaluating an optional predicate or validation scan that must be omitted when checks are disabled.

## Verification

Build-mode verification MUST check that guarded predicates execute in Debug and ReleaseSafe and are omitted in ReleaseFast and ReleaseSmall.

Consumer tests MUST verify documented behavior across all four build modes.
