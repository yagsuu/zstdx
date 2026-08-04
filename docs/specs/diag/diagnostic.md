# Scoped diagnostics

Status: Approved.

`stdx.diag.Diagnostics` is a type family for static diagnostics instances. A
participating fallible function opens one frame at function entry, registers any
static or formatted detail with that frame, and marks the frame from `errdefer`
only when an error propagates through it.

The primitive is intentionally narrow: function-scope error context and
deterministic rendering, not logging and not handled-error aggregation.

## Owned scope

This spec owns:

- the `stdx.diag` namespace surface for scoped diagnostics;
- `diag.Diagnostics.Static`, `diag.Scope`, `diag.FormattedDetail`, `diag.fmt`,
  and `diag.scope`;
- inline frame storage and inline formatted-detail arena bytes owned by the
  `Diagnostics.Static(config)` value;
- the required `defer frame.pop()` and `errdefer |err| frame.unwind(err)` usage
  pattern;
- lazy formatted detail registered through `scope()` and materialized by
  `Scope.unwind()` only on the error path;
- null diagnostics adapter behavior;
- deterministic text rendering to `*std.Io.Writer`;
- capacity-failure degradation to no-op diagnostics or omitted details;
- source-location rendering when provided;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- severity levels;
- log filtering;
- structured payloads beyond label/detail strings;
- sinks beyond `*std.Io.Writer`;
- multi-thread coordination or internal locking;
- integration with `std.log`;
- invariant checkers, trace ring buffers, or panic-safe logs;
- root promotion of diagnostic types or functions;
- automatic compiler stack traces;
- handled-error aggregation, retry reports, `record`, or mark/rollback APIs;
- standalone `unwind` functions that allocate frames during `errdefer`;
- caller-provided diagnostics frame storage;
- allocator-wrapped diagnostics construction.

Structured subsystem diagnostics MAY exist next to this primitive later. This
primitive owns only scoped context for one propagated error path.

## Public namespace

`Diagnostics`, `Scope`, `FormattedDetail`, `fmt`, and `scope` live under
`stdx.diag`:

```zig
stdx.diag.Diagnostics
stdx.diag.Scope
stdx.diag.FormattedDetail
stdx.diag.fmt
stdx.diag.scope
```

They are not root-promoted:

```zig
stdx.Diagnostics // not exported
stdx.Scope       // not exported
stdx.fmt         // not exported
```

The root package facade exports the `diag` namespace:

```zig
pub const diag = @import("diag.zig");
```

## Source ownership

```text
src/diag.zig
src/diag/diagnostic.zig
test/diag/diagnostic_test.zig
```

`src/diag.zig` is a thin facade:

```zig
pub const diagnostic = @import("diag/diagnostic.zig");

pub const Diagnostics = diagnostic.Diagnostics;
pub const Scope = diagnostic.Scope;
pub const FormattedDetail = diagnostic.FormattedDetail;
pub const fmt = diagnostic.fmt;
pub const scope = diagnostic.scope;
```

## Approved API

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

There is no public `ScopeOptions` type. Diagnostic entry points MUST accept a
structural options value.

`Diagnostics.Static(config)` returns a concrete diagnostics type with inline
frame slots and inline detail-arena bytes. `config.frames` and
`config.arena_bytes` MUST both be greater than zero. A zero value for either
field is a compile error.

## Options shape

`scope` and `Diagnostics.Static(...).scope` accept an options struct with:

- required `.label: []const u8`;
- optional `.source: ?SourceLocation`;
- optional `.detail`, either eager bytes (`[]const u8` or `?[]const u8`) or
  `fmt(format, args)`.

`.label` MUST be non-empty. `.source = @src()` SHOULD be used when call-site
location is useful.

`FormattedDetail` is a generic detail-format value. Callers SHOULD create it only
through `fmt(format, args)`; the concrete return type is inferred at the call
site.

## Construction

The only user-facing construction API is `Diagnostics.Static(config).init()`:

```zig
const Diag = stdx.diag.Diagnostics.Static(.{
    .frames = diag_frame_capacity,
    .arena_bytes = diag_detail_capacity,
});

var diag = Diag.init();
```

or inline:

```zig
var diag = stdx.diag.Diagnostics.Static(.{
    .frames = diag_frame_capacity,
    .arena_bytes = diag_detail_capacity,
}).init();
```

The diagnostics value owns its frame slots and detail arena. It MUST NOT be moved
while formatted detail allocations are live; this matches the pointer-stability
contract of `stdx.mem.Arena.Static`.

## Common usage: scoped propagated-error unwind

Every participating fallible function SHOULD use this pattern for propagated
errors:

```zig
fn loadFirmware(path: []const u8, diag: anytype) !Firmware {
    var frame = stdx.diag.scope(diag, .{
        .label = "load firmware",
        .source = @src(),
        .detail = stdx.diag.fmt("{s}", .{path}),
    });
    defer frame.pop();
    errdefer |err| frame.unwind(err);

    const bytes = try readFile(path);
    return parseFirmware(bytes, diag);
}
```

`stdx.diag.scope(null, options)` returns a no-op scope, so call sites do not need
an `if (diag)` branch. When `diag` is null, no diagnostic frame is allocated, no
formatted detail is materialized, and `pop`, `unwind`, and `detail` are no-ops.

`defer frame.pop()` MUST be registered before `errdefer |err| frame.unwind(err)`
so `unwind` runs before `pop` on the error path.

`fmt(format, args)` does not format or allocate. It stores `args` by value in the
returned scope handle. `Scope.unwind(err)` materializes the detail only if the
error path is taken. Argument expressions are still evaluated when `scope()` is
called; callers that need to defer expensive argument computation should compute
that value inside an explicit `errdefer` block and call `frame.detail(...)` before
`frame.unwind(err)`.

Nested scopes render as a nested domain stack trace. Because frames are opened at
function entry, retained diagnostics follow live function-stack order:

```text
  at load firmware: /boot/fw.bin (src/fw.zig:10) -> InvalidFirmware
    at parse firmware (src/fw.zig:21) -> InvalidFirmware
      at parse header (src/fw.zig:44) -> InvalidFirmware
```

`Diagnostics` values are single-report accumulators. After a report has been
consumed, call `clear()` or `deinit()` before reusing the same value for an
unrelated operation.

## Static diagnostics semantics

A `Diagnostics.Static(config)` value exposes:

```zig
pub fn init() Self;
pub fn deinit(self: *Self) void;
pub fn clear(self: *Self) void;
pub fn isEmpty(self: *const Self) bool;
pub fn scope(self: *Self, options: anytype) Scope(*Self, @TypeOf(options));
pub fn format(self: *const Self, w: *std.Io.Writer) std.Io.Writer.Error!void;
```

`scope(diag, options)` and `diag.scope(options)` push a frame immediately when
`diag` is non-null and frame capacity remains. They do not materialize formatted
detail at scope entry.

`Scope.unwind(err)` stores `err` on the frame. If the scope options contain
`.detail` and `Scope.detail(...)` has not already set a detail, `unwind` applies
that option detail first. Formatted option detail is allocated from the inline
arena only during `unwind`.

`Scope.detail(detail)` sets or replaces the frame detail immediately:

- eager byte details are borrowed;
- formatted details are materialized from the inline arena;
- `null` clears the current detail;
- arena exhaustion leaves the previous detail unchanged.

Calling `Scope.detail(...)` suppresses later materialization of the `.detail`
value registered in the original scope options.

`Scope.pop()` moves the active scope back to the popped scope's parent. If the
frame has no error, the frame and its descendants are discarded. If the frame has
an error, it remains linked in the retained diagnostics tree.

Scopes are a strict stack. Popping out of LIFO order is programmer error.

## Allocation and ownership

The diagnostics value owns:

- frame slot storage;
- frame occupancy and topology state;
- inline arena bytes for formatted details.

The diagnostics value borrows:

- label bytes;
- eager detail bytes;
- source-location values are copied by value.

Label bytes and eager detail bytes MUST remain valid until the diagnostics report
is no longer formatted or until `clear()`/`deinit()` invalidates the report.
Formatted detail bytes live in the diagnostics inline arena and remain valid
until `clear()`/`deinit()` resets that arena.

`scope` and `diag.scope` are infallible. If frame capacity is exhausted, they
return a no-op scope. If formatted detail materialization exhausts the inline
arena, the detail is omitted or left unchanged; the frame and originating error
remain intact.

Diagnostics MUST NOT replace a real failure with a diagnostic `OutOfMemory`
failure. Failed diagnostic additions MUST NOT corrupt the retained frame
topology.

`clear()` removes all retained frames, resets frame occupancy, resets the inline
arena, and invalidates all previous frame/detail pointers. Calling `clear()` while
a scope is open is programmer error.

`deinit()` performs `clear()` and invalidates the diagnostics value.

## Rendering

`format(w)` renders retained frames in deterministic DFS pre-order. Empty
diagnostics render nothing.

Each frame renders as:

```text
<indent>at <label>[: <detail>] [(file:line)] [-> <err>]
```

Rules:

- root/top-level frames use two spaces of indentation;
- each child depth adds two more spaces;
- siblings preserve insertion order;
- label and detail bytes are escaped with `std.zig.fmtString`;
- source location renders only when `source != null`;
- the error suffix renders only when `err != null`;
- error tags use `{t}` formatting;
- no trailing newline is written after the last frame.

Example:

```text
  at prepare host resources (src/host/resources.zig:73) -> FileNotFound
    at firmware code: ./boot.fd (relative to /home/me/example) (src/host/resources.zig:198) -> FileNotFound
```

`SourceLocation.fn_name` is stored but not rendered by this spec.

## Threading

`Diagnostics` values are single-owner and externally synchronized. Concurrent
callers MUST coordinate above this type. Internal locking is not provided.

## Required tests

The implementation MUST cover:

1. empty diagnostics render nothing;
2. `scope(null, ...)` returns a no-op scope whose methods are safe;
3. null scopes do not evaluate formatted details;
4. single `errdefer frame.unwind(err)` renders one retained frame;
5. nested scoped unwinds render an outer-to-inner chain;
6. successful scoped calls do not evaluate formatted details;
7. successful scoped calls do not consume arena bytes for scoped formatted
   details;
8. frame capacity exhaustion preserves the originating error and omits the frame;
9. formatted detail arena exhaustion preserves the originating error and omits
   only the detail;
10. successful scoped leaf frames are discarded on `pop`;
11. direct detail replacement renders only the latest detail;
12. `fmt` option detail renders on retained frames;
13. explicit `Scope.detail(fmt(...))` renders formatted detail;
14. `Scope.detail(...)` overrides option detail;
15. `clear` removes retained frames, resets frame occupancy, and resets arena
   usage;
16. source location renders when present and is omitted when null;
17. label/detail escaping covers control characters and backslashes.
