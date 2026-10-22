//! Public stdx facade. See `docs/specs/stdx.md`.

pub const core = @import("core");
pub const bits = @import("bits");
pub const addr = @import("addr");
pub const ranges = @import("ranges");
pub const graph = @import("graph");
pub const layout = @import("layout");
pub const bytes = @import("bytes");
pub const mem = @import("mem");
pub const collections = @import("collections");
pub const intrusive = @import("intrusive");
pub const algo = @import("algo");
pub const tags = @import("tags");
pub const arch = @import("arch");
pub const diag = @import("diag");
pub const sync = @import("sync");
pub const concurrent = @import("concurrent");
pub const io = @import("io");
pub const barrier = @import("barrier");
pub const time = @import("time");
pub const dma = @import("dma");
pub const cpu = @import("cpu");
pub const func = @import("func");
