//! Graph and tree topology primitives.

pub const forest = @import("forest.zig");

pub const Forest = forest.Forest;

test {
    _ = forest.unit;
}
