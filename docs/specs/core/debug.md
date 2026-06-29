# Core debug

Status: Approved.

`zstdx.core.debug` owns the minimal shared helper that maps `SafetyMode` to whether optional zstdx checks are compiled into an operation. Per-type invariant checks remain owned by each primitive.

## Owned scope

This spec owns:

- `zstdx.core.debug.checksEnabled`;
- the `assertValid` method convention;
- assertion-versus-error rules;
- `SafetyMode` interaction rules for debug checks;
- required tests for debug-check behavior.

This spec does not own:

- diagnostics;
- invariant checker frameworks;
- poisoning;
- stats;
- panic/log helpers;
- generic `anytype` assertion helpers;
- per-primitive invariant details.

## Public namespace

`checksEnabled` lives under `zstdx.core.debug`:

```zig
zstdx.core.debug.checksEnabled
```

It is not root-promoted:

```zig
zstdx.debug // not exported
zstdx.checksEnabled // not exported
```

Source ownership:

```text
src/core.zig
src/core/debug.zig
```

`src/core.zig` re-exports:

```zig
pub const debug = @import("core/debug.zig");
```

## Approved API

```zig
pub fn checksEnabled(comptime mode: zstdx.core.SafetyMode) bool;
```

Semantics:

| Mode | Result |
| --- | --- |
| `.build_mode` in Debug | `true` |
| `.build_mode` in ReleaseSafe | `true` |
| `.build_mode` in ReleaseFast | `false` |
| `.build_mode` in ReleaseSmall | `false` |
| `.checked` | `true` |
| `.unchecked` | `false` |

Implementation shape:

```zig
const builtin = @import("builtin");

const SafetyMode = @import("options.zig").SafetyMode;

pub fn checksEnabled(comptime mode: SafetyMode) bool {
    return switch (mode) {
        .build_mode => switch (builtin.mode) {
            .Debug, .ReleaseSafe => true,
            .ReleaseFast, .ReleaseSmall => false,
        },
        .checked => true,
        .unchecked => false,
    };
}
```

`mode` is comptime so disabled checks can compile out.

## Usage pattern

Cheap automatic check:

```zig
if (zstdx.core.debug.checksEnabled(opts.safety)) {
    self.assertValid();
}
```

Expensive automatic check:

```zig
if (zstdx.core.debug.checksEnabled(opts.safety)) {
    self.assertValidDeep();
}
```

Do not pass expensive predicates into a generic wrapper. Arguments would be evaluated before the wrapper call. This is why no `debug.assert(mode, condition)` helper is approved.

## `assertValid` convention

Types with non-trivial invariants expose:

```zig
pub fn assertValid(self: *const Self) void;
```

Small value types may use a value receiver when their owning spec approves it:

```zig
pub fn assertValid(self: Self) void;
```

Expected receiver choices:

- containers: `self: *const Self`;
- intrusive collections: `self: *const Self`;
- small immutable value types such as `Range(T)`: `self: Self`.

`assertValid` requirements:

- never allocates;
- never waits, blocks, sleeps, or spins;
- does not mutate logical state;
- checks all cheap structural invariants owned by the type;
- may be O(n) only when the primitive spec documents it;
- uses assertions for programmer errors;
- is not a replacement for validation of external input.

An explicit `assertValid()` call always performs the check. `SafetyMode` controls only automatic checks inside operations.

## Assertion versus error rule

Use errors or `null` for expected runtime conditions:

```zig
error.Full
error.OutOfRange
null
```

Use assertions for programmer contract violations:

- invalid internal structure after mutation;
- double insert when the primitive spec says membership must be unique;
- removing a node that is not linked when the API requires linked membership;
- using an invalid unchecked range;
- violating documented preconditions.

Do not assert on:

- malformed external bytes;
- user-provided input data that the API promises to validate;
- ordinary capacity exhaustion;
- expected lookup misses;
- stale handles when the API promises an error or `null` result.

## `SafetyMode` interaction

A primitive using `SafetyMode` must state:

| Check | Controlled by `SafetyMode`? | Behavior when disabled |
| --- | --- | --- |
| public error conditions | no | still returns errors |
| memory-safety requirements | no | still required |
| internal invariant checks | usually yes | skipped |
| expensive validation scans | yes if documented | skipped |
| explicit `assertValid()` call | no | always checks |

`.unchecked` must not convert a safe error-returning API into unchecked memory unsafety unless the primitive spec explicitly marks the operation as unsafe or preconditioned.

## First-slice consumers

### `Range(T)`

- exposes `assertValid(self: Self)`;
- asserts `start <= end`;
- does not need a `SafetyMode` option.

### `List.Static` and `List.Bounded`

- expose `assertValid(self: *const Self)`;
- check `len <= capacity`;
- mutating operations may call `assertValid` when `checksEnabled(opts.safety)`.

### `Ring.Static` and `Ring.Bounded`

- expose `assertValid(self: *const Self)`;
- check `len <= capacity`, head/tail bounds, and wrap invariants;
- mutating operations may call `assertValid` when `checksEnabled(opts.safety)`.

### Intrusive structures

- expose `assertValid(self: *const Self)` when the collection owns structural invariants;
- may use `SafetyMode` for double-insert or double-remove checks if node state is tracked;
- if node state is not tracked, the primitive spec must say those violations are unchecked preconditions.

## Non-goals

This spec does not approve:

```zig
InvariantChecker
Diagnostic
PoisonPolicy
StatsPolicy
debug.assert(...)
debug.assertValid(anytype)
debug.panic(...)
```

These are deferred until a concrete primitive or diagnostic spec needs them.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `checksEnabled` | never | never | O(1) comptime branch | none | value-only | none |
| explicit `assertValid` convention | never | never | per primitive | none | per primitive | none |

## Required tests

For `zstdx.core.debug`:

- `checksEnabled(.checked)` is comptime `true`;
- `checksEnabled(.unchecked)` is comptime `false`;
- `checksEnabled(.build_mode)` matches `builtin.mode`;
- function is public as `zstdx.core.debug.checksEnabled`.

For consumers:

- each type with `assertValid` has at least one success test after normal public mutations;
- if `SafetyMode` gates a check, one test exercises checked behavior where practical;
- valid operation tests pass under `.checked` and `.unchecked` where the primitive exposes both;
- tests must not use `.unchecked` to hide invalid state.
