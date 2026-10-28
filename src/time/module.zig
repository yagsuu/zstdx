//! Time primitives. Normative contracts are in `docs/specs/time/`.

pub const monotonic = @import("monotonic.zig");
pub const deadline = @import("deadline.zig");
pub const backoff = @import("backoff.zig");
pub const rate_counter = @import("rate_counter.zig");
pub const deadline_queue = @import("deadline_queue.zig");
pub const timer_wheel = @import("timer_wheel.zig");

pub const Instant = monotonic.Instant;
pub const Duration = monotonic.Duration;
pub const Clock = monotonic.Clock;
pub const Deadline = deadline.Deadline;
pub const Backoff = backoff.Backoff;
pub const RateCounter = rate_counter.RateCounter;
pub const DeadlineQueue = deadline_queue.DeadlineQueue;
pub const TimerWheel = timer_wheel.TimerWheel;

test {
    _ = monotonic.unit;
    _ = deadline.unit;
    _ = backoff.unit;
    _ = rate_counter.unit;
    _ = deadline_queue.unit;
}
