//! Public zstdx facade. See docs/specs/root-exports.md.

pub const core = @import("core.zig");
pub const bits = @import("bits.zig");
pub const addr = @import("addr.zig");
pub const mem = @import("mem.zig");
