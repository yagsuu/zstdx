//! Time primitives. See docs/specs/time/monotonic.md,
//! docs/specs/time/deadline.md, and docs/specs/time/backoff.md.

pub const monotonic = @import("time/monotonic.zig");
pub const deadline = @import("time/deadline.zig");
pub const backoff = @import("time/backoff.zig");

pub const Instant = monotonic.Instant;
pub const Duration = monotonic.Duration;
pub const Clock = monotonic.Clock;
pub const Deadline = deadline.Deadline;
pub const Backoff = backoff.Backoff;
