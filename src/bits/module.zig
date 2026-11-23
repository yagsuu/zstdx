//! Bit primitives.

pub const mask = @import("mask.zig");
pub const set = @import("set.zig");
const word = @import("word.zig");
const field = @import("field.zig");

pub const Set = set.Set;
pub const Word = word.Word;
pub const BitField = field.BitField;
pub const BitFieldExt = field.BitFieldExt;

test {
    _ = word.unit;
    _ = mask.unit;
    _ = set.unit;
    _ = field.unit;
}
