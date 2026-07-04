//! IO primitives. See docs/specs/io/mmio.md and docs/specs/io/poll-until.md.

pub const mmio = @import("io/mmio.zig");
pub const poll = @import("io/poll.zig");

pub const Mmio = mmio.Mmio;
