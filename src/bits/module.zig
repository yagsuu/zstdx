//! Bit primitives. See `docs/specs/bits/mask.md`, `docs/specs/bits/set/static.md`,
//! and `docs/specs/bits/word.md`.

pub const mask = @import("mask.zig");
pub const set = @import("set.zig");
const word = @import("word.zig");

pub const Set = set.Set;
pub const Word = word.Word;

test {
    _ = word.unit;
    _ = mask.unit;
    _ = set.unit;
}
