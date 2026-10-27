//! Allocation algorithms. See `docs/specs/algo/alloc/`.

pub const alloc = @import("alloc.zig");

test {
    _ = alloc.buddy.unit;
    _ = alloc.placement.unit;
}
