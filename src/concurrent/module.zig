//! Concurrent data structures. See `docs/specs/concurrent/mpsc/ring.md`,
//! `docs/specs/concurrent/spsc/ring.md`, and `docs/specs/concurrent/qsbr.md`.

pub const log = @import("log.zig");
pub const mpsc = @import("mpsc.zig");
pub const qsbr = @import("qsbr.zig");
pub const spsc = @import("spsc.zig");

pub const EventLog = log.EventLog;

test {
    _ = @import("qsbr_test.zig");
    _ = @import("mpsc/ring_test.zig");
    _ = @import("spsc/ring_test.zig");
    _ = log.unit;
    _ = @import("mpsc/ring.zig").unit;
    _ = qsbr.unit;
    _ = @import("spsc/ring.zig").unit;
}
