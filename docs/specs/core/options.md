# Core options

Status: Approved.

`stdx.core.SafetyMode` selects whether an operation compiles optional zstdx safety checks. This specification also defines requirements for type-specific option structs.

## What this spec is

This specification defines `SafetyMode`, its public namespace, and the requirements for type-specific option structs that use it.

## What this spec is not

This specification does not define allocation, concurrency, growth, poisoning, statistics, or the checks that an individual primitive performs.

## Public namespace and source ownership

`SafetyMode` is available as `stdx.core.SafetyMode`. It is not available as `stdx.SafetyMode`.

Source ownership:

```text
src/core.zig
src/core/options.zig
```

`src/core.zig` re-exports `SafetyMode` from `core/options.zig`.

## Cross-spec relationships

A primitive that uses `SafetyMode` depends on this specification. `docs/specs/core/debug.md` defines how `SafetyMode` maps to the compilation of optional checks.

## Global invariants

`SafetyMode` controls zstdx optional checks only. It does not disable Zig language safety, allocator safety, atomic-ordering requirements, memory-safety obligations, or documented error-returning behavior unless the owning primitive specification explicitly defines an unsafe or preconditioned operation.

`.unchecked` MUST NOT change a safe error-returning operation into memory-unsafe behavior unless the owning primitive specification explicitly marks that operation unsafe or preconditioned.

## API

```zig
pub const SafetyMode = enum {
    build_mode,
    checked,
    unchecked,
};
```

## `SafetyMode` behavior

| Mode | Behavior |
| --- | --- |
| `build_mode` | `stdx.core.debug.checksEnabled` enables optional checks in Debug and ReleaseSafe builds and disables them in ReleaseFast and ReleaseSmall builds. |
| `checked` | `stdx.core.debug.checksEnabled` enables optional checks. |
| `unchecked` | `stdx.core.debug.checksEnabled` disables optional checks. |

An owning primitive specification MUST state which checks `SafetyMode` controls, which errors and assertions remain enforced, which checks `.unchecked` omits, and whether any operation is unsafe or preconditioned.

## Type-specific options

A primitive that accepts options MUST define its option type beside the primitive or primitive family that consumes it. The type name MUST be `Options` unless the owning specification defines a more specific public name.

A primitive that uses `SafetyMode` SHOULD use this default shape when no additional option is required:

```zig
pub const Options = struct {
    safety: stdx.core.SafetyMode = .build_mode,
};
```

The owning primitive specification MUST document each option field, its default value, the operations that observe it, whether it changes public errors or only optional assertions, and whether it changes layout, ABI, or type identity.

An option that changes type layout or code generation MUST be a `comptime` parameter. A primitive that stores options at runtime MUST specify the required runtime behavior.

For a generic family whose options are rarely changed, the owning specification SHOULD provide a default factory and an explicit-options factory, for example:

```zig
pub fn Static(comptime T: type, comptime N: usize) type;
pub fn StaticWithOptions(comptime T: type, comptime N: usize, comptime opts: Options) type;
```

The owning primitive specification defines its factory names and may use a different API shape when that shape preserves an explicit options path.

## Implementation constraints

`SafetyMode` contains exactly `build_mode`, `checked`, and `unchecked`.

## Testing

Tests for `SafetyMode` MUST verify that `stdx.core` exports the enum and that its values are exactly `build_mode`, `checked`, and `unchecked`. This proves the public compile-time vocabulary and prevents an incompatible value change.

For each primitive that uses `SafetyMode`, tests MUST exercise enabled optional checks with `.checked` and normal valid operations with each supported mode. Tests that depend on `.build_mode` MUST use an explicit build mode. Tests MUST NOT use `.unchecked` to conceal an invalid invariant; this proves that disabled optional checks do not redefine the primitive's valid-state contract.
