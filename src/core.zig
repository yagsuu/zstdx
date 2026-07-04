//! Core primitives. See docs/specs/core/options.md,
//! docs/specs/core/debug.md, docs/specs/core/range.md,
//! and docs/specs/core/traits.md.

const traits = @import("core/traits.zig");
pub const debug = @import("core/debug.zig");

pub const SafetyMode = @import("core/options.zig").SafetyMode;
pub const Range = @import("core/range.zig").Range;
pub const Order = traits.Order;
pub const Compare = traits.Compare;
pub const LessThan = traits.LessThan;
pub const Eql = traits.Eql;
pub const Hash = traits.Hash;
