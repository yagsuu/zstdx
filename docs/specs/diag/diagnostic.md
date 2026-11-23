# `stdx.diag.Diagnostics`

`Diagnostics` retains bounded scope context for propagated errors and renders
the retained frames as a report.

## Storage and lifetime

`Diagnostics.Static(.{ .frames = N, .arena_bytes = B }).init()` owns inline frame
slots and a formatted-detail arena. Both capacities must be greater than zero
at compile time. The default arena size is zero, so callers must supply it.

Labels and byte details are borrowed. Source locations are copied, but their
referenced strings remain borrowed. Callers MUST keep these bytes valid while
their frames can be rendered. Formatted details use the inline arena and remain
valid until `Diagnostics.clear()` or `Diagnostics.deinit()`.

Keep diagnostics in place while scopes or formatted details are live.
Callers MUST serialize access.

`Diagnostics.clear()` removes all frames and resets the arena.
`Diagnostics.deinit()` clears and invalidates the value. Both require all scopes
to be closed and invalidate prior report data. Clear a completed report before
starting an unrelated operation. `Diagnostics.isEmpty()` reports whether any root
frame exists, including an open root.

## Scopes and errors

`diag.scope(pointer, options)` and `Diagnostics.scope(options)` accept a required
nonempty `.label`, optional `.source: ?std.builtin.SourceLocation`, and optional
`.detail`. Details can be bytes, optional bytes, `null`, or `diag.fmt(...)`.

Scope entry immediately adds a frame beneath the active scope when capacity is
available. Scopes MUST close in LIFO order. Register `defer frame.pop()` before
`errdefer |err| frame.unwind(err)` so that error retention runs before closure.

| Operation | Effect |
| --- | --- |
| `Scope.unwind(err)` | Stores the error and applies option detail unless explicit detail has already been supplied. Does not close the scope or propagate the error. |
| `Scope.detail(value)` | Immediately replaces detail; `null` clears it. Suppresses later application of option detail, even if formatting fails. |
| `Scope.pop()` | Restores the parent. Retains an errored frame; otherwise discards that frame and its descendants. Further operations on that scope do nothing. |

Propagate errors through each enclosing scope whose context must be retained.
A successful parent discards retained child failures when it closes.
Repeated `Scope.unwind()` calls replace the error and can materialize option
detail again if no explicit detail was supplied.

`diag.scope()` also accepts an optional diagnostics pointer or literal `null`.
A null pointer, literal `null`, or exhausted frame capacity produces a scope
whose operations do nothing and do not materialize detail.

## Detail formatting and failure

`diag.fmt(format, args)` stores evaluated arguments by value. Keep borrowed
arguments live until materialization: `Scope.unwind()` for option detail,
or `Scope.detail()` for explicit detail.

Formatted detail allocates only from the inline arena. Allocation or formatter
failure leaves existing detail unchanged; a new frame can therefore retain its
error without detail. Frame exhaustion omits context without replacing the
originating error. Replacing details and discarding successful scopes do not
reclaim arena space; `Diagnostics.clear()` resets it.

`FormattedDetail.materialize(allocator)` can also be called directly. It returns
allocated text or `null` on formatting failure; the supplied allocator determines
that text's ownership and lifetime.

## Rendering and execution context

`Diagnostics.format(writer)` renders roots and siblings in insertion order,
with each parent before its children:

```text
<indent>at <label>[: <detail>] [(file:line)] [-> <error>]
```

Roots have two spaces of indentation; each child adds two more. Labels and
details use `std.zig.fmtString` escaping. Source locations show file and line;
errors use tag formatting. Frames are separated by newlines with no final
newline. Empty diagnostics emit no bytes.

Writer errors propagate unchanged with possible partial output.
Rendering preserves the report; retries start at its beginning.

Frame storage is bounded and recording uses no heap allocation. Scope entry and
ordinary error retention take constant time apart from detail formatting;
closure can scan siblings. Rendering traverses the report recursively and costs
time proportional to frames, indentation, and output bytes. Custom formatters
and writers determine their own execution-context requirements.
Callers MUST choose suitable callbacks and storage capacities.

## References

- [Diagnostics and scope declarations](../../../src/diag/diagnostic.zig)
- [Concurrent event log](../concurrent/log.md)
