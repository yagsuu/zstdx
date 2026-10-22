//! I/O primitives. See `docs/specs/io/mmio.md` and `docs/specs/io/poll.md`.

pub const mmio = @import("mmio.zig");
pub const poll = @import("poll.zig");

pub const MMIO = mmio.MMIO;
