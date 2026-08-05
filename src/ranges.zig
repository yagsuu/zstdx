//! Range collections. See `docs/specs/ranges/set.md` and
//! `docs/specs/ranges/map.md`.

pub const set = @import("ranges/set.zig");
pub const map = @import("ranges/map.zig");

pub const RangeSet = set.RangeSet;
pub const RangeMap = map.RangeMap;
