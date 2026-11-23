# `time.Instant`, `time.Duration`, and `time.Clock`

`Instant` and `Duration` represent nanosecond time values.
`Clock.Monotonic(Backend)` adapts a caller-supplied monotonic clock.

## Time values

`Instant` is an `enum(u64)` nanosecond count relative to a backend-defined
epoch. `Duration` is an `enum(i64)` signed nanosecond difference. Their
`Int` aliases name these backing types. `Instant.fromNanos()` / `Instant.nanos()`
and `Duration.fromNanos()` / `Duration.nanos()` preserve every backing value.
`Instant.zero` and `Duration.zero` represent zero.

Compare or subtract instants only within the same clock domain and epoch.
Time arithmetic does not wrap.

| Operation | Result and limits |
| --- | --- |
| `Instant.add(delta)` | Adds a signed duration. Returns `error.Overflow` if the result is below zero or above `maxInt(u64)`. |
| `Instant.since(base)` | Returns the signed difference; the difference MUST fit `i64`. |
| `Instant.isAtOrAfter(other)` | Returns true for greater or equal nanosecond counts, including equality. |
| `Duration.fromMicros()`, `Duration.fromMillis()`, `Duration.fromSeconds()` | Multiply the signed input by 1,000, 1,000,000, or 1,000,000,000. Return `error.Overflow` if the result does not fit `i64`. |
| `Duration.isPositive()`, `Duration.isNegative()` | Test strictly positive or negative values. Both return false for zero. |

Value operations take O(1) time without allocation or waiting.

## Clock backend and ownership

A backend provides `pub fn now(self: *Backend) Instant`. It may also provide
`pub fn sleep(self: *Backend, delta: Duration) void`. The factory rejects a
missing or incorrectly typed `now`, or an incorrectly typed declared
`sleep`, at compile time. Error-union returns are invalid.

`Clock.Monotonic(Backend).init(backend)` stores the backend by value.
Keep referenced resources live and serialize conflicting access.
Backend readings MUST be non-decreasing within a consistent clock domain and epoch.

## Reading and sleeping

`Clock.Monotonic(Backend).now()` returns one backend reading.
`Clock.Monotonic(Backend).sleep(delta)` forwards a non-negative duration once,
including zero, and exists when the backend provides `sleep`.
Sleep granularity, interruption, and early return follow backend policy.

Wrapper operations add O(1) work without allocation. Backend costs and
execution-context requirements apply.

## References

- [Time values and clocks](../../../src/time/monotonic.zig)
- [Deadlines](deadline.md)

