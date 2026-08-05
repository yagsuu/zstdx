# Core options

Status: Approved.

`stdx.core` owns shared option vocabulary only when a concrete primitive needs it. This spec approves `SafetyMode` and option-shape rules. Growth, poisoning, stats, allocation-policy, and concurrency-policy abstractions are not approved here.

## Owned scope

This spec owns:

- shared option naming rules;
- `SafetyMode`;
- rules for type-specific `Options` structs;
- rules for option defaults;
- deferred option categories.

This spec does not own:

- runtime metadata;
- allocation policy enums;
- concurrency policy enums;
- growth algorithms;
- debug/assert implementation details for each primitive;
- whether a primitive is implemented.

## Public namespace

`SafetyMode` lives under `stdx.core`:

```zig
stdx.core.SafetyMode
```

It is not root-promoted:

```zig
stdx.SafetyMode // not exported
```

Source ownership:

```text
src/core.zig
src/core/options.zig
```

`src/core.zig` re-exports:

```zig
pub const SafetyMode = @import("core/options.zig").SafetyMode;
```

## Approved API

```zig
pub const SafetyMode = enum {
    build_mode,
    checked,
    unchecked,
};
```

## `SafetyMode` semantics

| Mode | Meaning |
| --- | --- |
| `build_mode` | Enable zstdx optional safety checks in Debug and ReleaseSafe; disable them in ReleaseFast and ReleaseSmall. |
| `checked` | Always enable zstdx optional safety checks. |
| `unchecked` | Disable zstdx optional safety checks. |

`SafetyMode` controls zstdx library checks only.

Examples of checks a primitive spec may put behind `SafetyMode`:

- invariant assertions;
- double-insert checks;
- double-remove checks;
- stale-handle checks when implemented as optional debug checks;
- precondition checks beyond Zig's own safety checks.

`SafetyMode` does not disable:

- Zig language safety;
- allocator safety;
- atomic ordering requirements;
- memory-safety obligations;
- documented error-returning behavior unless the owning primitive spec explicitly says so.

`.unchecked` must not turn valid error-returning API behavior into memory unsafety unless the primitive spec marks the operation as unsafe or preconditioned.

## Option struct rules

Type-specific options live beside the type or family that consumes them. They are named `Options` unless the owning spec approves a more specific name.

Default shape:

```zig
pub const Options = struct {
    safety: stdx.core.SafetyMode = .build_mode,
};
```

A primitive that accepts options must document:

- every option field;
- default value;
- which operations observe the option;
- whether the option changes public errors or only debug assertions;
- whether the option affects layout, ABI, or type identity.

Options that affect type layout or code generation should be `comptime` parameters. Runtime-stored options require an owning spec rationale.

## Generic family option factories

Zig generic family APIs should optimize for common usage while preserving an explicit options path.

Preferred pattern when options are rarely changed:

```zig
pub fn Static(comptime T: type, comptime N: usize) type;
pub fn StaticWithOptions(comptime T: type, comptime N: usize, comptime opts: Options) type;
```

A primitive spec may choose a different shape if the resulting API is clearer. The owning primitive spec decides the exact factory names.

## Deferred options

The following options are candidates only. They are not approved public API by this spec.

### `GrowthPolicy`

Deferred until a dynamic container spec needs it.

Candidate consumers:

- `List.Managed`;
- `Ring.Managed`;
- `HashMap.Managed`;
- `bytes.Builder`.

### `PoisonPolicy`

Deferred until an allocator or container spec requires poisoning.

Candidate consumers:

- `mem.alloc.Arena.Bounded`;
- `mem.BumpAllocator`;
- `mem.alloc.SlabAllocator`;
- `List.Static`;
- `Ring.Static`.

### `StatsPolicy`

Deferred until diagnostics or allocator stats have concrete consumers.

Candidate consumers:

- `diag.AllocationStats`;
- `mem.alloc.SlabAllocator`;
- `HashMap.Managed`.

## Rejected generic policies

Do not create generic versions of these policies in `core`:

```zig
AllocationPolicy
ConcurrencyPolicy
```

Allocation and concurrency semantics belong in each primitive's operation contract. Generic policy enums become vague metadata without forcing correctness.

## Required behavior documentation

Any primitive using `SafetyMode` must state:

- which checks are controlled by `SafetyMode`;
- which errors or assertions are always enforced;
- which checks disappear under `.unchecked`;
- whether `.unchecked` changes public error behavior or only debug assertions;
- which operations are unsafe or preconditioned, if any.

## Required tests

For `SafetyMode` itself:

- the enum is public through `stdx.core`;
- values are exactly `build_mode`, `checked`, and `unchecked`.

For every primitive using `SafetyMode`:

- one test exercises checked behavior where practical;
- one test proves normal valid operations work independent of mode;
- no test relies on build-mode-dependent behavior unless the test target mode is explicit.

Tests may use `.unchecked` for valid operation paths. Tests must not use `.unchecked` to hide broken invariants.

## Open questions

None.
