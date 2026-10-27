//! core primitives

const traits = @import("traits.zig");

pub const debug = @import("debug.zig");

pub const Order = traits.Order;
pub const Compare = traits.Compare;
pub const LessThan = traits.LessThan;
pub const Eql = traits.Eql;
pub const Hash = traits.Hash;
