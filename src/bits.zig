//! Bit primitives. See docs/specs/bits/power-of-two.md and
//! docs/specs/bits/bitset-static.md.

pub const power_of_two = @import("bits/power_of_two.zig");

pub const BitSet = @import("bits/set.zig").BitSet;

pub const isPowerOfTwo = power_of_two.isPowerOfTwo;
pub const nextPowerOfTwo = power_of_two.nextPowerOfTwo;
