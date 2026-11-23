# `time.RateCounter`

`RateCounter` projects elapsed monotonic time into a fixed-width counter
and reports wrap boundaries crossed between samples.

## Configuration and clocks

`RateCounter.Config` supplies an `Instant` base, nonzero `u64` rate in hertz,
and `u7` width in `1..64`. `RateCounter.init(config)` starts with zero wrap history.

The public `base`, `rate_hz`, and `width` fields are for inspection. Create
a new counter to change the rate or width. Use `RateCounter.reset()` to
reanchor the base. Callers MUST NOT write `wraps`.
The counter occupies 32 bytes.

Clock arguments follow the [monotonic clock contract](monotonic.md).
Invalid `now` signatures fail at compile time. The caller MUST use one clock
domain and epoch for the base and all reads. Readings must be non-decreasing
and at or after the base. Elapsed nanoseconds must fit `i64`.

## Projection

For elapsed nanoseconds `e`, the total tick count is
`floor(e * rate_hz / 1_000_000_000)`. The multiplication uses `u128`.
The returned `u64` value contains the low `width` bits of this tick count.
Fractional ticks are discarded. The value wraps modulo `2^width`.

For widths below 64, the wrap count is
`floor(total_ticks / 2^width)`. The caller MUST keep this count within
`u64` for both `RateCounter.peek()` and `RateCounter.sample()`.
At width 64, projection truncates to `u64` and the wrap count is always zero.

## Sampling and reset

`RateCounter.peek(clock)` reads the clock once and returns the projected
value without changing wrap history.

`RateCounter.sample(clock)` reads the clock once and returns the value and
`wrapped`. For widths below 64, `wrapped` is true if the current wrap count
exceeds the stored count. The call then stores the current count.
The sampling window starts at initialization, reset, or the previous sample.
An exact wrap boundary counts as a crossing. Multiple crossings produce
one true result. Repeating a sample at the same reading returns false.
Peeks do not consume pending crossings.

At width 64, `RateCounter.sample()` always reports `wrapped = false`,
including when the returned value wraps.

`RateCounter.reset(clock)` reads a new base and clears wrap history, preserving
rate and width. Subsequent samples report wraps since that base.

## Costs and concurrency

Operations take O(1) work plus the stated clock read without allocation or waiting.
Serialize conflicting access and satisfy the clock's execution-context requirements.

## References

- [Fixed-rate projection](../../../src/time/rate_counter.zig)

