//! Allocation algorithms.

pub const alloc = @import("alloc.zig");

test {
    _ = alloc.buddy.unit;
    _ = alloc.placement.unit;
}
