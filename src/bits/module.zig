//! Bit primitives. See `docs/specs/bits/mask.md`, `docs/specs/bits/set/static.md`,
//! and `docs/specs/bits/word.md`.

pub const mask = @import("mask.zig");
pub const word = @import("word.zig");

pub const BitSet = @import("set.zig").BitSet;
