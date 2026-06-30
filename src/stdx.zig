//! Public stdx facade. See docs/specs/root-exports.md.

pub const core = @import("core.zig");
pub const bits = @import("bits.zig");
pub const addr = @import("addr.zig");
pub const ranges = @import("ranges.zig");
pub const graph = @import("graph.zig");
pub const layout = @import("layout.zig");
pub const bytes = @import("bytes.zig");
pub const mem = @import("mem.zig");
pub const collections = @import("collections.zig");
pub const intrusive = @import("intrusive.zig");
pub const algo = @import("algo.zig");
pub const tags = @import("tags.zig");
pub const arch = @import("arch.zig");

pub const List = collections.List;
pub const Ring = collections.Ring;
