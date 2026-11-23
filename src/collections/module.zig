//! Fixed-storage container primitives.

pub const list = @import("list.zig");
pub const ring = @import("ring.zig");

pub const List = list.List;
pub const Ring = ring.Ring;

test {
    _ = list.unit;
    _ = ring.unit;
}
