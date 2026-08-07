//! Default host test suite aggregate. See `docs/specs/project/architecture.md`.

comptime {
    _ = @import("core/all.zig");
    _ = @import("bits/all.zig");
    _ = @import("addr/all.zig");
    _ = @import("ranges/all.zig");
    _ = @import("graph/all.zig");
    _ = @import("layout/all.zig");
    _ = @import("bytes/all.zig");
    _ = @import("mem/all.zig");
    _ = @import("collections/all.zig");
    _ = @import("intrusive/all.zig");
    _ = @import("algo/all.zig");
    _ = @import("tags/all.zig");
    _ = @import("arch/all.zig");
    _ = @import("diag/all.zig");
    _ = @import("sync/all.zig");
    _ = @import("concurrent/all.zig");
    _ = @import("io/all.zig");
    _ = @import("barrier/all.zig");
    _ = @import("time/all.zig");
    _ = @import("dma/all.zig");
    _ = @import("cpu/all.zig");
    _ = @import("func/all.zig");
}
