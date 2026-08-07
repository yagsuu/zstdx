# Time rate counter

Status: Approved.

`stdx.time.RateCounter` is a fixed-rate projection of `stdx.time.Instant`
into an integer counter of configurable bit width, with wrap-edge
detection across sampling calls. It composes with any clock matching the
backend contract in `docs/specs/time/monotonic.md`.

`RateCounter` owns the projection and the wrap-edge detector; the caller
owns any register storage, status bit, or interrupt delivery.

`RateCounter` is a value, not a scheduler primitive. It never sleeps,
never parks, and never touches the backend beyond calling
`Backend.now()`.

## What this spec is

This spec owns:

- `stdx.time.RateCounter`, the projection value type;
- `stdx.time.RateCounter.Config`, the caller-provided anchor, rate, and
  width;
- `stdx.time.RateCounter.Sample`, the tagged result of `sample`;
- the `Instant`-to-counter projection formula and its overflow domain;
- the wrap-edge detector state and its update contract;
- the `clock: anytype` composition seam, duck-typed against
  `Backend.now`;
- debug-only structural validation of `Config` and `RateCounter` under
  `stdx.core.debug.checksEnabled`;
- required tests.

## What this spec is not

This spec does not own:

- wrap-boundary scheduling — arming callbacks or interrupts at the next
  wrap `Instant` is the caller's job through `Deadline` or a hardware
  timer;
- status-bit register writes, SCI raise, or any device-side side effect
  of `wrapped = true`;
- non-integer-Hz precision — every configured rate is an integer number
  of hertz;
- concurrent access — `RateCounter` is single-owner, matching
  `Clock.Monotonic`;
- mutation of identity fields (`base`, `rate_hz`, `width_bits`) after
  `init`;

## Public namespace

`RateCounter` lives under `stdx.time`:

```zig
stdx.time.RateCounter
stdx.time.RateCounter.Config
stdx.time.RateCounter.Sample
```

Source ownership:

```text
src/time.zig
src/time/rate_counter.zig
test/time/rate_counter_test.zig
```

`src/time.zig` re-exports:

```zig
pub const rate_counter = @import("time/rate_counter.zig");

pub const RateCounter = rate_counter.RateCounter;
```

`src/time.zig` is a thin facade. It contains no logic beyond re-exporting
and aliasing.

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
`stdx.core.debug.checksEnabled(.build_mode)`, `init` calls
`config.assertValid()`.

`init` does not touch the clock. Consumers that anchor at "now" pass
`clock.now()` into `Config.base`.

### Reset

`reset(clock)` sets `base = clock.now()` and `last_wrap_count = 0`. The
next `sample` reports `wrapped = false` regardless of prior history.
`rate_hz` and `width_bits` are unchanged.

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

The intermediate `elapsed_ns * rate_hz` is computed in `u128` to avoid
overflow across the full `Instant` and `rate_hz` domains.

`elapsed_ns` must be non-negative. Under
`stdx.core.debug.checksEnabled(.build_mode)`, `peek` and `sample` assert
`now.afterOrEq(base)`. A `base` sourced from the same monotonic clock
cannot trip this assertion.

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

`wrapped` is `true` iff the unbounded tick count crossed a
`1 << width_bits` boundary between the previous `sample` (or `init` /
`reset`) and this call. Multiple wraps between two `sample` calls
produce a single `wrapped = true` return; consumers who need a wrap
count read `last_wrap_count` directly.

`sample` at the exact wrap boundary (`unbounded % (1 << width_bits) == 0`)
counts as a wrap on the call that crosses into the new interval.

### assertValid

`Config.assertValid` checks:

- `rate_hz > 0`;
- `width_bits >= 1`;
- `width_bits <= 64`.

`Config.assertValid` runs unconditionally.

`RateCounter.assertValid` recurses into the embedded config invariants
via a projected `Config`. Runs unconditionally. `RateCounter.init` calls
`config.assertValid()` under `checksEnabled(.build_mode)` only.

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

Testing MUST use a caller-controlled `FakeClock` and must not read a real clock. This method isolates the projection and wrap detector from backend timing.

- Boundary and validation tests verify that invalid `rate_hz` and `width_bits` values trap, that `init` copies the identity fields and clears `last_wrap_count`, and that debug-only checks reject a clock reading before `base` while release-mode behavior does not add that trap.
- Projection-model tests compare `peek` with the specified `u128` formula across the anchor, whole-second conversion, masked widths, and `width_bits == 64`. They prove masking and intermediate-overflow behavior without relying on a backend.
- Transition tests drive the fake clock across zero, an exact wrap boundary, and multiple wrap intervals. They verify that `sample` reports one wrap event per sampling interval, `peek` does not alter detector state, and `reset` re-anchors and suppresses the next wrap report.
- Compile-time tests reject clocks without `now(*Self) Instant`, verify the fixed `RateCounter` size assertion, and compile the module for a non-x86 target. These tests prove the clock seam and representation constraints.
