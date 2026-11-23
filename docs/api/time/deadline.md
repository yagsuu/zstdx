# `time.Deadline`

`Deadline` is a monotonic nanosecond target for inclusive expiration checks
and signed remaining-time queries.

## Values and clocks

`Deadline` is an `enum(u64)` with backing alias `Int = u64`.
`Deadline.from(instant)` preserves the instant's nanosecond count.
`Deadline.instant()` returns that count as an `Instant`.

Clock arguments follow the [monotonic clock contract](monotonic.md): an
infallible `pub fn now(self: *Self) Instant`. Invalid signatures fail at
compile time. A bare backend or `Clock.Monotonic(Backend)` wrapper can supply
the clock. The caller MUST use the same clock domain and epoch for
construction and every subsequent query.

## Construction and queries

| Operation | Result |
| --- | --- |
| `Deadline.after(clock, delta)` | Reads the clock once and adds the signed duration. Returns `error.Overflow` for a target outside `0..maxInt(u64)`. |
| `Deadline.isNever()` | Tests whether the stored target equals `maxInt(u64)`. |
| `Deadline.isExpired(clock)` | Reads the clock once and returns true when the reading is greater than or equal to the target. |
| `Deadline.remaining(clock)` | For a finite target, reads the clock once and returns target minus reading as a signed `Duration`: positive before, zero at, and negative after the target. |
| `Deadline.check(clock)` | Returns `error.Timeout` at or after the target. Otherwise succeeds. |

Negative deltas are accepted when the target remains in range.
For finite `Deadline.remaining()` calls, the caller MUST ensure that the
signed difference fits `i64`, as required by `Instant.since()`.

`Deadline.never` stores `maxInt(u64)`. Constructing that target with
`Deadline.from()` or `Deadline.after()` produces the same sentinel.
`Deadline.never.remaining()` returns `Duration.fromNanos(maxInt(i64))`
without reading the clock. Expiration still uses the inclusive comparison:
the sentinel expires if the clock reaches `maxInt(u64)`, and
`Deadline.never.check()` then returns `error.Timeout`.

## Costs and concurrency

Operations take O(1) work plus clock reads without allocation or waiting.
The clock's concurrency and execution-context requirements apply.

## References

- [Deadlines](../../../src/time/deadline.zig)
- [Backoff](backoff.md)

