//! core primitives

const traits = @import("traits.zig");
const result = @import("result.zig");

pub const debug = @import("debug.zig");

pub const Order = traits.Order;
pub const Compare = traits.Compare;
pub const LessThan = traits.LessThan;
pub const Eql = traits.Eql;
pub const Hash = traits.Hash;

pub const Result = result.Result;
pub const ResultExt = result.ResultExt;

test {
    _ = result.unit;
}
