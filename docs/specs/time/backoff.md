# `time.Backoff`

`Backoff` generates retry actions with spin, yield, and bounded sleep phases.
The caller performs each returned action.

## Policy and state

`Backoff.Policy` groups a `spin` configuration, optional `yield`
configuration, and `wait` configuration:

- `spin.iterations` is the `u32` number of spin steps.
- A non-null `yield` supplies a `u32` iteration count and a
  `*const fn () void` hook. Null skips the yield phase. Zero iteration
  counts skip the corresponding phase.
- `wait.initial` and `wait.max` are non-negative signed-nanosecond
  durations with `initial <= max`.
- `wait.growth_shift` is `u3` (`0..7`). Each sleep step multiplies the next
  wait by `2^growth_shift`, saturating at `wait.max`. Zero keeps waits
  constant; an initial wait of zero remains zero.

The caller MUST keep `spin.iterations + yield.iterations` within `u32`.
`Backoff.init(policy)` starts with zero attempts and `policy.wait.initial`.
`Backoff.assertValid()` checks wait bounds.

## Progression and deadlines

`Backoff.next(deadline, clock)` uses the [deadline clock contract](deadline.md).
The caller MUST use a consistent clock domain and epoch for the deadline
and successive calls. Finite remaining-time differences must fit `i64`.

Each call selects an action in this order:

1. An expired deadline returns `.timeout`, including at the exact boundary.
2. The configured spin steps return `.spin`.
3. The configured yield steps return `.yield`.
4. The sleep phase queries remaining time again. A non-positive result
   returns `.timeout`. Otherwise it returns `.sleep` containing the smaller
   of `next_wait` and the observed remaining duration, then grows `next_wait`.

Sleep clipping uses the current reading; growth uses the stored wait.
The caller executes returned actions.

Non-timeout steps increment the `u32` count returned by `Backoff.attempts()`.
Reset before this count overflows. Timeout preserves attempts and `next_wait`.

`Backoff.reset()` restores zero attempts and `policy.wait.initial` without
changing the policy. To replace a policy, assign a valid policy and reset
before generating further steps. Public state must continue to satisfy
the bounds above.

## Costs and concurrency

Operations take O(1) work without allocation or waiting. `Backoff.next()` reads
the clock once, and once more during sleep selection for a finite deadline.
Serialize mutable access and satisfy the clock's execution-context requirements.

## References

- [Retry backoff](../../../src/time/backoff.zig)

