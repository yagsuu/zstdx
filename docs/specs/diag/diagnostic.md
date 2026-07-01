# Scoped diagnostics

Status: Approved.

`stdx.diag.Diagnostics` is a scoped failure-context carrier. Callers pass
`?*Diagnostics` through fallible call chains; each participating function opens a
`Scope` that describes the operation it is attempting. Successful scopes are
removed on `pop`. Scopes marked with `fail(err)` are retained, so the surviving
frames render as nested context lines for the final error.

The primitive is intentionally narrow: typed ownership and rendering of failure
context, not logging.

## Owned scope

This spec owns:

- the `stdx.diag` namespace surface for scoped diagnostics;
- `diag.Diagnostics`, `diag.ScopeOptions`, `diag.Scope`, `diag.LazyDetail`, and
  `diag.lazy`;
- scope push/pop semantics and the required `defer s.pop()` pattern;
- explicit `errdefer |err| s.fail(err)` failure marking;
- private arena ownership for labels, eager details, lazy detail captures, and
  frames;
- retained frame tree topology;
- null diagnostics adapter behavior;
- deterministic text rendering to `*std.Io.Writer`;
- allocation-failure degradation to `Scope.noop` or no-op detail behavior;
- source-location rendering when provided;
- retained-frame-lazy detail materialization;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- severity levels;
- log filtering;
- structured payloads beyond label/detail strings;
- message templates beyond Zig format strings passed to `lazy` or `detailf`;
- sinks beyond `*std.Io.Writer`;
- multi-thread coordination or internal locking;
- integration with `std.log`;
- invariant checkers, trace ring buffers, or panic-safe logs;
- root promotion of diagnostic types.

Structured subsystem diagnostics may exist next to this primitive later. This
primitive owns only the cross-call failure-context trace.

## Public namespace

`Diagnostics`, `ScopeOptions`, `Scope`, `LazyDetail`, and `lazy` live under
`stdx.diag`:

```zig
stdx.diag.Diagnostics
stdx.diag.ScopeOptions
stdx.diag.Scope
stdx.diag.LazyDetail
stdx.diag.lazy
```

They are not root-promoted:

```zig
stdx.Diagnostics // not exported
stdx.Scope       // not exported
stdx.LazyDetail  // not exported
```

The root package facade exports the `diag` namespace once this spec lands:

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
pub const ScopeOptions = diagnostic.ScopeOptions;
pub const Scope = diagnostic.Scope;
pub const LazyDetail = diagnostic.LazyDetail;
pub const lazy = diagnostic.lazy;
```

## Primitive dependencies

`Diagnostics` uses `stdx.graph.Forest.Linked` for retained frame topology. The
diagnostics arena owns frame payloads; `graph.Forest` owns only parent,
first-child, and next-sibling link semantics.

## Approved API

```zig
const std = @import("std");
const graph = @import("../graph.zig");

const Allocator = std.mem.Allocator;
const SourceLocation = std.builtin.SourceLocation;

pub fn LazyDetail(comptime Args: type, comptime fmt: []const u8) type;
pub fn lazy(comptime fmt: []const u8, args: anytype) LazyDetail(@TypeOf(args), fmt);

pub const Diagnostics = struct {
    const FrameForest = graph.Forest.Linked(Frame, "node");

    arena: std.heap.ArenaAllocator,
    frames: FrameForest = .init(),
    current: ?*Frame = null,

    pub fn init(gpa: Allocator) Diagnostics;
    pub fn deinit(self: *Diagnostics) void;

    pub fn isEmpty(self: *const Diagnostics) bool;
    pub fn scoped(self: *Diagnostics, options: anytype) Scope;
    pub fn open(diag: ?*Diagnostics, options: anytype) Scope;
    pub fn format(self: Diagnostics, w: *std.Io.Writer) std.Io.Writer.Error!void;

    pub const Frame = struct {
        node: graph.Forest.LinkedNode,
        label: []const u8,
        detail: ?[]const u8,
        pending_detail: ?PendingDetail,
        source: ?SourceLocation,
        err: ?anyerror,
    };
};

/// Concrete eager-detail options. `Diagnostics.open` and `scoped` also accept
/// struct literals whose `.detail` field is `lazy(fmt, args)`.
pub const ScopeOptions = struct {
    label: []const u8,
    detail: ?[]const u8 = null,
    source: ?SourceLocation = null,
};

pub const Scope = struct {
    inner: ?Inner = null,

    pub const noop: Scope = .{};

    const Inner = struct {
        diag: *Diagnostics,
        frame: *Diagnostics.Frame,
    };

    pub fn detail(self: Scope, text: []const u8) void;
    pub fn detailf(self: Scope, comptime fmt: []const u8, args: anytype) void;
    pub fn fail(self: Scope, err: anyerror) void;
    pub fn pop(self: Scope) void;
};
```

`LazyDetail` is a generic detail-capture value. Callers normally use it only
through `lazy(fmt, args)`; the concrete return type is inferred at the call site.

`Diagnostics.scoped` and `Diagnostics.open` accept an options struct with:

- required `.label: []const u8`;
- optional `.source: ?SourceLocation`;
- optional `.detail`, either eager bytes (`[]const u8` or `?[]const u8`) or
  `lazy(fmt, args)`.

`Frame` fields are public so diagnostic-specific tools can inspect retained
frame payloads. Retained frames have `pending_detail == null` after `pop`; tools
should read materialized `detail`. Tree traversal uses
`graph.Forest.Linked(Frame, "node")`. Frame storage remains owned by
`Diagnostics` and is invalidated by `deinit`.

## Usage pattern

Every participating fallible function uses this pattern:

```zig
var s = Diagnostics.open(diag, .{
    .label = "firmware code",
    .source = @src(),
    .detail = stdx.diag.lazy("{s} (relative to {s})", .{
        raw,
        paths.profile_dir,
    }),
});
defer s.pop();
errdefer |err| s.fail(err);
```

`defer s.pop()` must be present for every opened scope. `errdefer |err|
s.fail(err)` records the propagated error. Omitting the `errdefer` means the
scope is discarded when it has no failed children.

`Diagnostics.open(null, options)` returns `Scope.noop`, so call sites do not need
an `if (diag)` branch. When `diag` is null, lazy details are not copied or
formatted.

## Scope semantics

`Diagnostics.scoped(options)` allocates a frame in the diagnostics arena, copies
`options.label`, copies eager `options.detail` bytes when present, copies lazy
detail captures when `.detail = lazy(fmt, args)` is used, links the frame through
`graph.Forest.Linked(Frame, "node")`, and makes it the new `current` frame. If
no frame is currently open, the frame is linked at top level. Multiple top-level
retained frames render as siblings in insertion order.

`Scope.fail(err)` stores `err` on the frame. Calling `fail` more than once
replaces the stored error with the latest error.

`Scope.detail(text)` copies `text` into the diagnostics arena, replaces the
materialized frame detail, and clears any pending lazy detail. Previous detail
bytes remain arena-owned but unreachable.

`Scope.detailf(fmt, args)` records a pending lazy detail capture. It does not
format immediately. Formatting runs during `pop` only if the frame is retained
because it has an error or retained children.

`lazy(fmt, args)` creates the same lazy detail capture for use in `Diagnostics`
options: `.detail = stdx.diag.lazy(fmt, args)`. Captured arguments are copied by
value into the diagnostics arena when the scope opens. Any memory referenced by
captured arguments must remain valid until `pop`. Use eager `detail(text)` or
`ScopeOptions.detail` when bytes must be copied immediately.

`Scope.pop()` moves `current` back to the popped frame's forest parent. If the
frame has no error and no retained children, it is unlinked from the forest and
any pending lazy detail is discarded without formatting. If the frame has an
error or retained children, pending lazy detail materializes into the diagnostics
arena before the frame remains linked.

Scopes are a strict stack. Popping out of LIFO order is programmer error.

## Allocation and ownership

`Diagnostics.init(gpa)` initializes a private `std.heap.ArenaAllocator`. All
frames, labels, materialized details, lazy detail captures, and retained detail
strings are allocated from that arena. `Diagnostics.deinit()` releases the arena
and invalidates every `Frame`, label, detail pointer, and lazy capture.

The diagnostics arena is intentionally separate from subsystem arenas. A failing
subsystem may deinitialize its own arena during unwinding without destroying the
failure context.

`Diagnostics.scoped`, `Scope.detail`, and `Scope.detailf` are infallible. On
arena allocation failure they silently degrade to no-op behavior:

- `scoped` returns `Scope.noop`;
- eager `detail` leaves the existing detail unchanged;
- lazy detail capture leaves the existing detail unchanged when capture
  allocation fails;
- lazy detail materialization leaves the existing detail unchanged when
  formatting allocation fails.

This preserves the originating error path. Diagnostics must not replace a real
failure with a diagnostic `OutOfMemory` failure.

## Rendering

`Diagnostics.format(w)` renders the retained frame tree in deterministic DFS
pre-order. Empty diagnostics render nothing.

Each frame renders as:

```text
<indent>at <label>[: <detail>] [(file:line)] [-> <err>]
```

Rules:

- root/top-level frames use two spaces of indentation;
- each child depth adds two more spaces;
- siblings preserve push order;
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

`Diagnostics` is single-owner and externally synchronized. Concurrent callers
must coordinate above this type. Internal locking is not provided.

## Required tests

The implementation must cover:

1. empty diagnostics render nothing;
2. push/pop success discards the frame;
3. push/fail/pop retains the frame and error tag;
4. nested failed scopes render as a chain in DFS order;
5. sibling failed scopes render side by side under the parent;
6. `Diagnostics.open(null, ...)` returns a no-op scope whose methods are safe;
7. detail replacement renders only the latest detail;
8. `detailf` renders formatted detail text on retained frames;
9. lazy option detail renders formatted detail text on retained frames;
10. lazy details are not formatted for discarded success scopes;
11. allocation failure during push degrades to no retained frame;
12. source location renders when present and is omitted when null;
13. label/detail escaping covers control characters and backslashes.
