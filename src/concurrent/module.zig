//! Concurrent data structures. See `docs/specs/concurrent/mpsc/ring.md`,
//! `docs/specs/concurrent/spsc/ring.md`, and `docs/specs/concurrent/qsbr.md`.

pub const mpsc = @import("mpsc.zig");
pub const qsbr = @import("qsbr.zig");
pub const spsc = @import("spsc.zig");

test {
    _ = @import("mpsc/ring.zig").unit;
    _ = @import("spsc/ring.zig").unit;
}
