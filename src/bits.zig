//! Bit primitives. See `docs/specs/bits/mask.md`, `docs/specs/bits/set/static.md`,
//! and `docs/specs/bits/word.md`.

pub const mask = @import("bits/mask.zig");
pub const word = @import("bits/word.zig");

pub const BitSet = @import("bits/set.zig").BitSet;
