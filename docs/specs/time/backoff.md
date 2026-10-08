# Time backoff

Status: Approved.

`stdx.time.Backoff` is a structured retry-delay generator. Each call to
`next` returns a `Step` describing what the caller should do — spin,
yield, sleep for a duration, or give up because the deadline has passed.
The primitive owns the phase progression and deadline clipping; the caller
owns the actual spin/yield/sleep.

`Backoff` is a value, not a scheduler. It does not spin, does not yield,
does not sleep, and never touches the clock beyond querying the deadline.

## API

```zig
pub const Backoff = struct {
    pub const Policy = struct {
        spin_iterations: u32,
        yield_iterations: u32,
        yield: ?*const fn () void,
        initial_wait: Duration,
        max_wait: Duration,
        growth_shift: u3,

        pub fn assertValid(self: Policy) void;
    };

    pub const Step = union(enum) {
        spin,
        yield,
        sleep: Duration,
        timeout,
    };

    policy: Policy,
    attempt: u32,
    next_wait: Duration,

    pub fn init(policy: Policy) Backoff;
    pub fn reset(self: *Backoff) void;

    pub fn next(
        self: *Backoff,
        deadline: Deadline,
        clock: anytype,
    ) Step;

    pub fn attempts(self: *const Backoff) u32;

    pub fn assertValid(self: *const Backoff) void;
};
```

`policy`, `attempt`, and `next_wait` are public fields. Callers may inspect
`next_wait` between calls for logging or heuristic sizing, and may
overwrite `policy` in place before calling `reset()` when they need to
swap policies.

## Policy semantics

`Policy.spin_iterations` is the number of `.spin` results returned before
transitioning to the yield phase. Zero is legal.

`Policy.yield_iterations` is the number of `.yield` results returned
before transitioning to the sleep phase. Zero is legal.

`Policy.yield` is a nullable function pointer. When `null`, the yield
phase is skipped entirely regardless of `yield_iterations`: `next` moves
directly from spin to sleep. This lets freestanding callers set
`yield: null` without altering `yield_iterations`.

`Policy.initial_wait` is the first `.sleep(Duration)` value returned in
the sleep phase. Must be non-negative.

`Policy.max_wait` is the ceiling on `next_wait`. Growth saturates at this
value. Must be `>= initial_wait`.

`Policy.growth_shift` is the left-shift applied to `next_wait` after each
sleep step. `0` produces a constant-wait backoff. Range is `u3` (0..7),
allowing up to 128× growth per step. Values that would push `next_wait`
past `max_wait` saturate.

`Policy.assertValid` checks:

- `initial_wait.nanos() >= 0`;
- `max_wait.nanos() >= 0`;
- `initial_wait.nanos() <= max_wait.nanos()`.

Explicit `Policy.assertValid()` and `Backoff.assertValid()` calls MUST validate the policy. `Backoff.init()` performs automatic policy validation when `core.debug.checksEnabled()` is true.

## Backoff semantics

### Initialization

`Backoff.init(policy)` returns a `Backoff` with `policy` stored,
`attempt = 0`, `next_wait = policy.initial_wait`. Under
`checksEnabled()`, `init` calls `policy.assertValid()`.

### Step transitions

`next(deadline, clock)` returns the next phase result. Logic, in order:

1. If `deadline.expired(clock)` → return `.timeout`. `attempt` is
   unchanged.
2. Else if `attempt < policy.spin_iterations` → return `.spin`,
   increment `attempt`.
3. Else if `policy.yield != null` and
   `attempt < policy.spin_iterations + policy.yield_iterations` →
   return `.yield`, increment `attempt`.
4. Else enter sleep phase:
   - compute `remaining = deadline.remaining(clock)`;
   - if `remaining.nanos() <= 0` → return `.timeout`, `attempt`
     unchanged;
   - compute `wait_ns = min(next_wait.nanos(), remaining.nanos())`;
     this can never be negative because both operands are non-negative
     (remaining is guaranteed positive at this point);
   - grow `next_wait`: `new_ns = next_wait.nanos() << policy.growth_shift`
     saturated at `policy.max_wait.nanos()`; overflow of the shift is
     also saturated at `max_wait`;
   - assign `next_wait = Duration.fromNanos(new_ns)`;
   - increment `attempt`;
   - return `.sleep(Duration.fromNanos(wait_ns))`.

- The deadline check runs first. A deadline that is already expired produces
  `.timeout` before any spin or yield step.
- Sleep-phase clipping is per step. A returned `.sleep(Duration)` does not
  exceed the deadline.
- `.timeout` does not increment `attempt`; `attempts()` reports productive
  steps rather than calls to `next`.

### Reset

`reset()` restores `attempt = 0` and `next_wait = policy.initial_wait`.
`policy` is not modified. Callers who want to swap policies overwrite
`self.policy` directly before calling `reset()`.

### Attempts

`attempts()` returns `self.attempt`, saturated at `maxInt(u32)`. The
counter is not expected to overflow in practical workloads; the return
type is `u32` matching the field.

### `assertValid`

`Backoff.assertValid` checks:

- `self.policy.assertValid()`;
- `self.next_wait.nanos() >= 0`;
- `self.next_wait.nanos() <= self.policy.max_wait.nanos()`.

Explicit validation uses `std.debug.assert`. Callers may gate the invocation with `checksEnabled()` as specified in [the Zig guidelines](../../guidelines/zig.md).

## Clock parameter

Every `next` call takes a `clock: anytype`. The clock's type must expose
`pub fn now(self: *Self) stdx.time.Instant` matching the backend contract
in `docs/specs/time/monotonic.md`. Compile-time signature check at each
callsite. `anyerror` returns and error-union returns are rejected.

Two `next` calls on the same `Backoff` should use the same clock. Mixing
clocks is a caller contract violation. `Backoff` is not tagged; the
primitive cannot detect the mix.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `Policy.assertValid` | never | never | O(1) | value type | none | asserts on invalid policy |
| `Backoff.init` | never | never | O(1) | value type | none | asserts under `checksEnabled` |
| `Backoff.reset` | never | never | O(1) | single-owner | none | infallible |
| `Backoff.next` | never | never | O(1) + backend `now` | single-owner | backend-defined | infallible; returns `.timeout` on expiry |
| `Backoff.attempts` | never | never | O(1) | reader | none | infallible |
| `Backoff.assertValid` | never | never | O(1) | reader | none | asserts on invalid state |

`Backoff` is safe from any execution context including NMI when the
supplied clock backend and yield hook (if any) are safe from that
context. The primitive itself performs no allocation, no locking, no
syscall, and no atomic operation.

## Testing

Tests MUST use a caller-controlled clock to check phase selection and deadline clipping without executing spin, yield, or sleep.

- Phase-transition tests exercise spin, configured yield, skipped yield, sleep, constant growth, geometric growth, and saturation. They verify that `next` returns the prescribed action and updates `attempt` and `next_wait` only for productive steps.
- Deadline-boundary tests use already-expired, exact-boundary, and positive-remaining deadlines. They verify that timeout takes precedence, sleep duration is clipped to the remaining duration, and `.timeout` does not increment `attempt`.
- Reset tests MUST verify restoration of `attempt` and `next_wait` and preservation of `policy`. Isolated validation tests MUST reject invalid policies and caller-mutated state.
- Compile-time tests MUST reject invalid clock shapes and compile the module for a non-x86 target.
