//! Callback trait type factories. See docs/specs/core/traits.md.

pub const Order = enum {
    lt,
    eq,
    gt,
};

pub fn Compare(comptime Context: type, comptime T: type) type {
    return fn (context: Context, lhs: *const T, rhs: *const T) Order;
}

pub fn LessThan(comptime Context: type, comptime T: type) type {
    return fn (context: Context, lhs: *const T, rhs: *const T) bool;
}

pub fn Eql(comptime Context: type, comptime T: type) type {
    return fn (context: Context, lhs: *const T, rhs: *const T) bool;
}

pub fn Hash(comptime Context: type, comptime T: type) type {
    return fn (context: Context, value: *const T) u64;
}
