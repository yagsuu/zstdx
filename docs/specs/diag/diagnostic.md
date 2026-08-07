# Scoped diagnostics

Status: Approved.

`stdx.diag.Diagnostics` stores bounded, function-scoped context for one propagated error path and renders the retained frames deterministically.

## What this spec is

This specification defines the `stdx.diag` scoped-diagnostics namespace, inline frame and formatted-detail storage, scoped error unwinding, deterministic rendering, the null adapter, ownership, capacity degradation, and required verification.

## What this spec is not

This specification does not define logging, severity, filtering, structured payloads other than label and detail strings, sinks other than `*std.Io.Writer`, automatic stack traces, handled-error aggregation, retry reporting, record or rollback operations, caller-provided frame storage, allocator-backed construction, internal locking, or panic-safe logging. `docs/specs/diag/panic_log.md` defines panic-safe logging.

## Public namespace and source ownership

The public names are `stdx.diag.Diagnostics`, `stdx.diag.Scope`, `stdx.diag.FormattedDetail`, `stdx.diag.fmt`, and `stdx.diag.scope`. `stdx.diag` is re-exported by `src/stdx.zig`.

The implementation is `src/diag/diagnostic.zig`. The required tests are in `test/diag/diagnostic_test.zig`. `src/diag.zig` is a thin facade that re-exports the public names.

## Data structures and representation

`Diagnostics.Static(config)` returns a concrete type that owns inline frame slots and an inline formatted-detail arena. The type does not guarantee the layout of its frames or arena.

Each retained frame contains a borrowed label, an optional borrowed or arena-owned detail, an optional copied `SourceLocation`, an optional error, and parent/child/sibling links. Retained roots and siblings preserve insertion order.

## Global invariants

- `config.frames` and `config.arena_bytes` MUST be greater than zero; either zero value is a compile error.
- A diagnostics value owns its frame slots, topology state, and formatted-detail arena bytes.
- Label bytes and eager detail bytes are borrowed and MUST remain valid until `clear()` or `deinit()` invalidates the report.
- Formatted detail bytes remain valid until `clear()` or `deinit()` resets the arena.
- A diagnostics value MUST NOT move while formatted detail allocations are live.
- Failed diagnostic work MUST NOT replace the originating error or corrupt retained frame topology.
- `clear()` and `deinit()` invalidate all previous frame and detail pointers.
- Scopes form a strict LIFO stack. A caller that pops a scope out of LIFO order has a programmer error.

## API

```zig
const std = @import("std");

const SourceLocation = std.builtin.SourceLocation;

pub fn FormattedDetail(comptime Args: type, comptime format: []const u8) type;
pub fn fmt(comptime format: []const u8, args: anytype) FormattedDetail(@TypeOf(args), format);
pub fn scope(diag: anytype, options: anytype) Scope(@TypeOf(diag), @TypeOf(options));

pub const Diagnostics = struct {
    pub const StaticConfig = struct {
        frames: usize,
        arena_bytes: usize = 0,
    };

    pub fn Static(comptime config: StaticConfig) type;
};

pub fn Scope(comptime Diag: type, comptime Options: type) type {
    return struct {
        pub fn pop(self: *@This()) void;
        pub fn unwind(self: *@This(), err: anyerror) void;
        pub fn detail(self: *@This(), detail: anytype) void;
    };
}
```

`Diagnostics.Static(config)` exposes:

```zig
pub fn init() Self;
pub fn deinit(self: *Self) void;
pub fn clear(self: *Self) void;
pub fn isEmpty(self: *const Self) bool;
pub fn scope(self: *Self, options: anytype) Scope(*Self, @TypeOf(options));
pub fn format(self: *const Self, w: *std.Io.Writer) std.Io.Writer.Error!void;
```

`scope` and `Diagnostics.Static(...).scope` accept a structural options value with a required non-empty `.label: []const u8`, optional `.source: ?SourceLocation`, and optional `.detail`. `.detail` is eager bytes (`[]const u8` or `?[]const u8`) or `fmt(format, args)`. There is no public `ScopeOptions` type.

## Scoped operations

### `scope` and `pop`

When a non-null diagnostics value has frame capacity, `scope` MUST push a frame immediately. It MUST NOT materialize formatted option detail at entry. When capacity is exhausted, `scope` MUST return a no-op scope.

`scope(null, options)` returns a no-op scope. Its `pop`, `unwind`, and `detail` methods are no-ops; it allocates no frame and materializes no formatted detail.

`pop` restores the parent as the active scope. It discards a frame and its descendants when the frame has no error. It retains an errored frame in the diagnostics tree.

### `unwind` and `detail`

`unwind(err)` stores `err` in the active frame. Unless `detail` has already been called, `unwind` applies the option `.detail` first. It materializes formatted option detail only on this error path.

`detail(value)` immediately sets or replaces the active-frame detail. Eager detail is borrowed. Formatted detail is materialized in the inline arena. `null` clears the detail. Arena exhaustion leaves the prior detail unchanged. Calling `detail` suppresses later materialization of the option detail.

`fmt(format, args)` stores `args` by value and neither formats nor allocates. Its argument expressions are evaluated at the `scope` call. A caller that must defer expensive argument computation MUST compute it in an explicit `errdefer` block before calling `detail` and `unwind`.

For a participating fallible function, the caller MUST register `defer frame.pop()` before `errdefer |err| frame.unwind(err)` so that `unwind` runs before `pop` on an error path.

### Capacity, allocation, and lifetime

`scope` and `diag.scope` are infallible. Frame exhaustion produces a no-op scope. Formatted-detail arena exhaustion omits a new option detail or preserves the existing explicit detail; it does not remove the frame or its error. The API performs no heap allocation.

`clear()` removes retained frames, resets frame occupancy and the formatted-detail arena, and invalidates all retained report data. Calling `clear()` while a scope is open is programmer error. `deinit()` performs `clear()` and invalidates the diagnostics value. A caller MUST call `clear()` or `deinit()` before using a consumed diagnostics value for an unrelated operation.

### Rendering

`format(w)` renders retained frames in deterministic depth-first pre-order. Empty diagnostics render no bytes. Each frame has this form:

```text
<indent>at <label>[: <detail>] [(file:line)] [-> <err>]
```

- Root frames use two spaces of indentation; each child depth adds two spaces.
- Siblings render in insertion order.
- Labels and details use `std.zig.fmtString` escaping.
- A source suffix renders only when `source != null`; `SourceLocation.fn_name` is not rendered.
- An error suffix renders only when the frame has an error; error tags use `{t}` formatting.
- The final frame has no trailing newline.

### Concurrency

`Diagnostics` is single-owner. Concurrent callers MUST synchronize outside this type. The type provides no internal locking.

## Implementation constraints

The implementation MUST use only the inline frame slots and formatted-detail arena owned by `Diagnostics.Static(config)`. It MUST retain error-path frames in the parent/child topology and discard successful scopes. It MUST preserve the originating error when diagnostic capacity or arena capacity is exhausted.

## Testing

Tests MUST verify the observable frame representation by rendering empty, single-frame, nested, sourced, unsourced, and escaped frames. These tests prove rendering order, indentation, optional fields, escaping, and absence of a final newline.

Tests MUST verify scope transitions: a null scope is safe and does not materialize formatted detail; a successful scope is discarded; an error unwind retains the frame; nested unwinds retain the outer-to-inner chain; and an explicit detail overrides option detail. These tests prove the error-path-only materialization and retention contract.

Tests MUST exhaust frame capacity and formatted-detail arena capacity. They MUST confirm that the original error and retained topology survive, while only the unavailable frame or detail is omitted. Tests MUST also verify that `clear()` resets retained frames and arena use before reuse. These failure and boundary tests prove bounded, allocation-free degradation.
