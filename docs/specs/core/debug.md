# Core debug

Status: Approved.

`stdx.core.debug.checksEnabled` maps `SafetyMode` to the compilation of optional zstdx checks. Each primitive owns its own invariants and invariant checks.

## What this spec is

This specification defines `checksEnabled`, the `assertValid` and `assertValidDeep` conventions, assertion-versus-error behavior, and the `SafetyMode` rules for optional checks.

## What this spec is not

This specification does not define diagnostics, generic invariant-checker frameworks, poisoning, statistics, panic or logging helpers, or the invariant details of an individual primitive.

## Public namespace and source ownership

`checksEnabled` is available as `stdx.core.debug.checksEnabled`. It is not available as `stdx.debug` or `stdx.checksEnabled`.

Source ownership:

```text
src/core.zig
src/core/debug.zig
```

`src/core.zig` exports `debug` from `core/debug.zig`.

## Cross-spec relationships

This specification depends on `docs/specs/core/options.md` for `SafetyMode`. A primitive specification that uses optional invariant checks depends on this specification and owns the checks it invokes.

## API

```zig
pub fn checksEnabled(comptime mode: stdx.core.SafetyMode) bool;
```

| Mode | Result |
| --- | --- |
| `.build_mode` in Debug | `true` |
| `.build_mode` in ReleaseSafe | `true` |
| `.build_mode` in ReleaseFast | `false` |
| `.build_mode` in ReleaseSmall | `false` |
| `.checked` | `true` |
| `.unchecked` | `false` |

`mode` is a `comptime` parameter. A caller MUST branch directly on `checksEnabled(mode)` when the caller needs disabled check code to compile out.

## `assertValid` convention

A type with non-trivial invariants MUST expose this method unless its owning specification defines another explicit validation contract:

```zig
pub fn assertValid(self: *const Self) void;
```

A pure value type with no buffer or slice field MAY use a value receiver when its owning specification approves the receiver:

```zig
pub fn assertValid(self: Self) void;
```

Containers, borrowed-buffer types, and stateful walkers MUST use `self: *const Self`. Pure value types, including `Range(T)`, `Address(Tag, Int)`, `EndianInt(T, endian)`, `Page(Addr, ps).Frame`, and `Page(Addr, ps).Count`, MAY use `self: Self`. The receiver choice depends on data shape, not size. A type that carries a backing slice, including `mem.alloc.Arena.Bounded`, MUST use `*const Self`.

`assertValid` MUST NOT allocate, wait, block, sleep, spin, or mutate logical state. It MUST check each cheap structural invariant owned by the type. It MUST use assertions for programmer errors and MUST NOT replace validation of external input.

## `assertValidDeep` convention

A type with an $O(n)$ structural invariant that is too costly for automatic checks MAY expose:

```zig
pub fn assertValidDeep(self: *const Self) void;
```

`assertValidDeep` MUST NOT allocate or mutate logical state. It MAY traverse every element or link. It complements `assertValid`; an integration or model test MAY call it when the test requires a deep structural check.

An explicit `assertValid()` or `assertValidDeep()` call always performs its check. `SafetyMode` controls only automatic invocations inside primitive operations.

## Errors and fault behavior

A primitive MUST return an error or `null` for an expected runtime condition, including `error.Full`, `error.OutOfBounds`, capacity exhaustion, an expected lookup miss, and a stale handle when the API promises an error or `null` result.

A primitive MUST use an assertion for a programmer contract violation, including an invalid internal structure after mutation, duplicate membership where membership must be unique, removal of an unlinked node where linked membership is required, an invalid unchecked range, or a documented precondition violation.

A primitive MUST NOT assert on malformed external bytes or user input that the API promises to validate.

## `SafetyMode` interaction

| Check | `SafetyMode` control | Behavior when disabled |
| --- | --- | --- |
| Public error condition | No | The operation still returns its documented error. |
| Memory-safety requirement | No | The requirement remains enforced. |
| Internal invariant check | Usually yes | The operation omits the check. |
| Expensive validation scan | Yes, when documented | The operation omits the scan. |
| Explicit `assertValid()` call | No | The call performs the check. |

A primitive MUST state each optional check that `SafetyMode` controls. `.unchecked` MUST NOT make a safe error-returning API memory-unsafe unless the primitive specification explicitly marks the operation unsafe or preconditioned.

## Implementation constraints

A caller MUST NOT pass an expensive predicate to a generic assertion wrapper when the caller expects `SafetyMode` to omit the predicate evaluation. The caller MUST branch on `checksEnabled` before evaluating that predicate.

This specification does not approve `InvariantChecker`, `Diagnostic`, `PoisonPolicy`, `StatsPolicy`, `debug.assert(...)`, `debug.assertValid(anytype)`, or `debug.panic(...)` as public API.

## Testing

Tests for `stdx.core.debug` MUST verify at compile time that `checksEnabled(.checked)` is `true`, `checksEnabled(.unchecked)` is `false`, and `checksEnabled(.build_mode)` matches `builtin.mode`. Tests MUST also verify the `stdx.core.debug.checksEnabled` public path. These checks prove the compile-time safety-mode mapping and public export.

For each type that exposes `assertValid`, tests MUST call it after normal public mutations. When `SafetyMode` gates an invariant check, tests MUST exercise the enabled `.checked` path and MUST verify that valid operations work with `.checked` and `.unchecked` when both modes are public. Tests MUST NOT use `.unchecked` to conceal invalid state. These tests prove the valid-state contract independently of optional automatic checks.
