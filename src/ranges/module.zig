//! range values and collections

pub const range = @import("range.zig");
pub const set = @import("set.zig");
pub const map = @import("map.zig");

pub const Range = range.Range;
pub const InclusiveRange = range.InclusiveRange;
pub const RangeSet = set.RangeSet;
pub const RangeMap = map.RangeMap;

test {
    _ = range.unit;
    _ = set.unit;
    _ = map.unit;
}
