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

## Owned scope

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

## Deferred scope and non-goals

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
- root promotion of `RateCounter`.

## Public namespace

`RateCounter` lives under `stdx.time`:

```zig
stdx.time.RateCounter
stdx.time.RateCounter.Config
stdx.time.RateCounter.Sample
```

It is not root-promoted:

```zig
stdx.RateCounter // not exported
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

## Approved API

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

There is no `RateCounter.rate`, no `RateCounter.periodNanos`, and no
identity-field setter. There is no wrap-boundary scheduling method;
consumers that need wrap-boundary interrupts derive the next wrap
`Instant` from `base`, `rate_hz`, `width_bits`, and `last_wrap_count`,
then arm a `Deadline` or a hardware timer themselves.

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

## Debug assertion behavior

`RateCounter.init` calls `config.assertValid()` under
`stdx.core.debug.checksEnabled(.build_mode)`. Explicit
`RateCounter.assertValid` calls run unconditionally, matching the
`assertValid` convention in `core/debug.md`.

`RateCounter.peek` and `RateCounter.sample` assert
`now.afterOrEq(self.base)` under
`stdx.core.debug.checksEnabled(.build_mode)`.

Common misconfigurations caught by the debug checks:

- `rate_hz == 0`;
- `width_bits == 0` or `width_bits > 64`;
- `base` anchored ahead of the clock's current reading.

## std.Io lane

`RateCounter` is freestanding-safe: no vtable, no runtime, no
allocation, no wait. It composes identically inside a downstream
`std.Io` backend and outside one.

## Examples

ACPI PM timer emulation (24-bit @ 3.579545 MHz, wrap raises `TMR_STS`):

```zig
const stdx = @import("stdx");
const time = stdx.time;

var pm_timer: time.RateCounter = .init(.{
    .base = clock.now(),
    .rate_hz = 3_579_545,
    .width_bits = 24,
});

fn readPmTmr(clock: anytype, pm1_sts: *PmStatus) u32 {
    const s = pm_timer.sample(clock);
    if (s.wrapped) pm1_sts.raiseTmrSts();
    return @intCast(s.value);
}
```

HPET main counter emulation (64-bit @ 10 MHz, no wrap in practice):

```zig
var hpet_main: time.RateCounter = .init(.{
    .base = clock.now(),
    .rate_hz = 10_000_000,
    .width_bits = 64,
});

fn readHpetMain(clock: anytype) u64 {
    return hpet_main.peek(clock);
}
```

Re-anchoring on a virtual machine warm reset:

```zig
fn onVmReset(pm_timer: *time.RateCounter, clock: anytype) void {
    pm_timer.reset(clock);
}
```

## Required tests

Tests live in `test/time/rate_counter_test.zig` and use a `FakeClock`
returning a caller-controlled `Instant`; no real monotonic clock is
required.

Required tests:

- `Config.assertValid` traps on `rate_hz == 0`;
- `Config.assertValid` traps on `width_bits == 0`;
- `Config.assertValid` traps on `width_bits > 64` for values `65..127`
  within the `u7` domain;
- `init(config)` under `checksEnabled(.build_mode)` traps on invalid
  config;
- `init(config)` sets `last_wrap_count = 0` and copies identity fields
  verbatim;
- `peek` at `clock.now() == base` returns `0`;
- `peek` at `clock.now() == base + 1s` for `rate_hz = 10` returns `10`;
- `peek` masks to `width_bits`: at `rate_hz = 3_579_545`,
  `width_bits = 24`, and an elapsed sufficient to overflow 24 bits, the
  returned value equals `unbounded_ticks & 0xFF_FFFF`;
- `peek` at `width_bits = 64` returns the full unbounded tick count
  within the `u64` domain;
- Two consecutive `peek` calls at the same clock reading return the
  same value;
- `peek` does not update `last_wrap_count`: a `peek` between two
  `sample` calls that straddle a wrap boundary still reports
  `wrapped = true` on the second `sample`;
- `sample` at `clock.now() == base` returns
  `.{ .value = 0, .wrapped = false }`;
- `sample` across one wrap boundary returns `wrapped = true` exactly
  once;
- `sample` across multiple wrap boundaries in one call returns
  `wrapped = true` (single event, not per-wrap);
- `sample` at `width_bits = 64` always returns `wrapped = false`;
- `sample` exactly at the wrap boundary (unbounded ticks divisible by
  `1 << width_bits`) counts as a wrap on that call;
- `reset(clock)` re-anchors `base` and clears `last_wrap_count`; the
  next `sample` reports `wrapped = false`;
- `peek` and `sample` under `checksEnabled(.build_mode)` trap when
  `clock.now()` returns an instant before `base`;
- `peek` and `sample` under `checksEnabled == false` do not fault when
  given the same `now < base` input;
- Compile-only: passing a clock without `now(*Self) Instant` is
  rejected;
- Compile-only: `@sizeOf(RateCounter)` is stable, asserted against a
  fixed value in the type body;
- Non-x86 build compiles the module.

## Open questions

None.
