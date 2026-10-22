//! Core primitives.
//! See `docs/specs/core/debug.md`, `docs/specs/core/range.md`,
//! and `docs/specs/core/traits.md`.

const traits = @import("traits.zig");

pub const debug = @import("debug.zig");

pub const Range = @import("range.zig").Range;
pub const InclusiveRange = @import("range.zig").InclusiveRange;
pub const Order = traits.Order;
pub const Compare = traits.Compare;
pub const LessThan = traits.LessThan;
pub const Eql = traits.Eql;
pub const Hash = traits.Hash;
