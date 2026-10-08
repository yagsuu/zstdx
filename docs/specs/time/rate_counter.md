# Time rate counter

Status: Approved.

`stdx.time.RateCounter` is a fixed-rate projection of `stdx.time.Instant`
into an integer counter of configurable bit width, with wrap-edge
detection across sampling calls. It composes with any clock matching the
backend contract in `docs/specs/time/monotonic.md`.

`RateCounter` owns the projection and the wrap-edge detector; the caller
owns any register storage, status bit, or interrupt delivery.

## API

```zig
pub const RateCounter = struct {
    pub const Config = struct {
        base: Instant,
        rate_hz: u64,
        width_bits: u7,

        pub fn assertValid(self: Config) void;
    };

    pub const Sample = struct {
        value: u64,
        wrapped: bool,
    };

    base: Instant,
    rate_hz: u64,
    width_bits: u7,
    last_wrap_count: u64,

    pub fn init(config: Config) RateCounter;

    pub fn reset(self: *RateCounter, clock: anytype) void;

    pub fn peek(self: *const RateCounter, clock: anytype) u64;
    pub fn sample(self: *RateCounter, clock: anytype) Sample;

    pub fn assertValid(self: *const RateCounter) void;
};
```

`base`, `rate_hz`, and `width_bits` are public fields for read-only
inspection. Callers must not mutate them; a geometry change is a fresh
`RateCounter`. `last_wrap_count` is mutated by `sample` and `reset`;
callers must not write it.

## Clock parameter

Every operation that takes `clock: anytype` requires the argument's type
to expose:

```zig
pub fn now(self: *Self) stdx.time.Instant;
```

matching the `Backend.now` signature approved in
`docs/specs/time/monotonic.md`. Both a `*time.Clock.Monotonic(Backend)`
wrapper and a bare backend satisfy the signature. The signature is
compile-time checked at each callsite; `anyerror` returns and error-union
returns are rejected via `@compileError`.

Passing two different clocks across the lifetime of one `RateCounter` is
a caller contract violation. `RateCounter` is not tagged; the primitive
cannot detect the mix. Wrap-edge reports become unreliable when the
`base` anchor and later `peek`/`sample` reads use different clocks.

## Semantics

### Representation

`RateCounter` is a plain `struct` holding a `u64` anchor instant, a
`u64` rate in hertz, a `u7` width, and a `u64` wrap counter.
`@sizeOf(RateCounter) <= 32` on every supported target; the exact size
is pinned by a `comptime` assertion inside the type body.

### Construction

`RateCounter.init(config)` returns a `RateCounter` with the identity
fields copied from `config` and `last_wrap_count = 0`. Under
`stdx.core.debug.checksEnabled()`, `init` calls
`config.assertValid()`.

`init` does not touch the clock. Consumers that anchor at "now" pass
`clock.now()` into `Config.base`.

### Reset

`reset(clock)` MUST set `base = clock.now()` and `last_wrap_count = 0`, preserving rate and width. Subsequent samples detect wraps since the new base; reset does not suppress a wrap that occurs before the next sample.

### Projection formula

Given a clock reading `now`, the unbounded tick count is:

```
elapsed_ns   = now.since(base).nanos()          // i64; must be >= 0
unbounded    = (elapsed_ns * rate_hz) / 1e9      // computed as u128
value        = unbounded & mask(width_bits)      // masked to counter width
wrap_count   = unbounded >> width_bits           // wrap counter, or 0 at width 64
```

`mask(width_bits)` is `(1 << width_bits) - 1` for `width_bits < 64` and
`maxInt(u64)` for `width_bits == 64`. `wrap_count` is `0` for
`width_bits == 64`.

The caller MUST supply a non-negative elapsed separation that fits `i64`. For widths below 64, the computed `wrap_count` MUST fit `u64` for both `peek` and `sample`. The `u128` multiplication avoids intermediate overflow within this domain.

When `core.debug.checksEnabled()` is true, `peek` and `sample` MUST assert `now.afterOrEq(base)`.

### peek

`peek(clock)` computes `value` from the projection formula and returns
it. The wrap-edge state is neither read nor updated. Two `peek` calls at
the same clock reading return the same value.

`peek` interleaves safely with `sample`: a `peek` between two `sample`
calls neither hides nor introduces a wrap event.

### sample

`sample(clock)` computes `value` and `wrap_count` from the projection
formula, sets `wrapped = wrap_count > self.last_wrap_count`, updates
`self.last_wrap_count = wrap_count`, and returns
`.{ .value = value, .wrapped = wrapped }`.

For `width_bits < 64`, `wrapped` MUST be true when the wrap count increases since the previous sample or initialization/reset. Multiple wraps produce one event; `last_wrap_count` stores the count. Reaching an exact wrap boundary increases that count.

For `width_bits == 64`, `wrap_count` is zero and `wrapped` MUST be false.

### assertValid

`Config.assertValid` checks:

- `rate_hz > 0`;
- `width_bits >= 1`;
- `width_bits <= 64`.

`Config.assertValid` runs unconditionally.

`RateCounter.assertValid` recurses into the embedded config invariants
via a projected `Config`. Runs unconditionally. `RateCounter.init` calls
`config.assertValid()` under `checksEnabled()` only.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `Config.assertValid` | never | never | O(1) | value type | none | asserts on invalid config |
| `RateCounter.init` | never | never | O(1) | value type | none | asserts under `checksEnabled` |
| `RateCounter.reset` | never | never | O(1) + backend | single-owner | backend-defined | infallible |
| `RateCounter.peek` | never | never | O(1) + backend | reader | backend-defined | infallible; asserts non-negative elapsed under `checksEnabled` |
| `RateCounter.sample` | never | never | O(1) + backend | single-owner | backend-defined | infallible; asserts non-negative elapsed under `checksEnabled` |
| `RateCounter.assertValid` | never | never | O(1) | reader | none | asserts on invalid state |

`RateCounter` is safe from any execution context including NMI when the
supplied clock backend is safe from that context. The primitive itself
performs no allocation, no locking, no syscall, and no atomic operation.

## Testing

Tests MUST use a caller-controlled clock.

- Check configuration boundaries, initial detector state, and enabled checks for readings before the base.
- Compare `peek` with the projection formula within the supported elapsed-time and wrap-count bounds.
- Cross exact and multiple-wrap boundaries; check that `peek` preserves detector state and reset discards prior history while detecting subsequent wraps.
- Check that width 64 returns the projected value with `wrapped == false`.
- Reject invalid clock shapes at compile time and compile for a non-x86 target.
