//! Range collections. See `docs/specs/ranges/set.md` and
//! `docs/specs/ranges/map.md`.

pub const set = @import("set.zig");
pub const map = @import("map.zig");

pub const RangeSet = set.RangeSet;
pub const RangeMap = map.RangeMap;
