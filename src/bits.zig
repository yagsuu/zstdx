//! Bit primitives. See `docs/specs/bits/mask.md`,
//! `docs/specs/bits/power-of-two.md`, `docs/specs/bits/bitset/static.md`, and
//! `docs/specs/bits/word.md`.

pub const mask = @import("bits/mask.zig");
pub const power_of_two = @import("bits/power_of_two.zig");
pub const word = @import("bits/word.zig");

pub const BitSet = @import("bits/set.zig").BitSet;

pub const isPowerOfTwo = power_of_two.isPowerOfTwo;
pub const nextPowerOfTwo = power_of_two.nextPowerOfTwo;
