//! Core primitives.
//! See `docs/specs/core/debug.md`, `docs/specs/core/range.md`,
//! and `docs/specs/core/traits.md`.

const range = @import("range.zig");
const traits = @import("traits.zig");

pub const debug = @import("debug.zig");

pub const Range = range.Range;
pub const InclusiveRange = range.InclusiveRange;
pub const Order = traits.Order;
pub const Compare = traits.Compare;
pub const LessThan = traits.LessThan;
pub const Eql = traits.Eql;
pub const Hash = traits.Hash;

test {
    _ = range.unit;
}
