//! Time primitives. See docs/specs/time/monotonic.md.

pub const monotonic = @import("time/monotonic.zig");

pub const Instant = monotonic.Instant;
pub const Duration = monotonic.Duration;
pub const Clock = monotonic.Clock;
