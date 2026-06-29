//! Core trait callback contract tests. Spec: docs/specs/core/traits.md.

const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;

fn compareU32(_: void, lhs: *const u32, rhs: *const u32) stdx.core.Order {
    if (lhs.* < rhs.*) return .lt;
    if (lhs.* > rhs.*) return .gt;
    return .eq;
}

fn lessU32(_: void, lhs: *const u32, rhs: *const u32) bool {
    return lhs.* < rhs.*;
}

fn eqlU32(_: void, lhs: *const u32, rhs: *const u32) bool {
    return lhs.* == rhs.*;
}

fn hashU32(_: void, value: *const u32) u64 {
    return value.*;
}

const PointerContext = struct {
    bias: u32,
};

fn eqlWithPointerContext(context: *const PointerContext, lhs: *const u32, rhs: *const u32) bool {
    return lhs.* + context.bias == rhs.* + context.bias;
}

test "unit: core trait symbols are public" {
    try testing.expectEqual(stdx.core.Order.lt, stdx.core.Order.lt);
    _ = stdx.core.Compare;
    _ = stdx.core.LessThan;
    _ = stdx.core.Eql;
    _ = stdx.core.Hash;
}

test "unit: trait factories compile for void context and scalar values" {
    const Compare = stdx.core.Compare(void, u32);
    const LessThan = stdx.core.LessThan(void, u32);
    const Eql = stdx.core.Eql(void, u32);
    const Hash = stdx.core.Hash(void, u32);

    const compare: Compare = compareU32;
    const less_than: LessThan = lessU32;
    const eql: Eql = eqlU32;
    const hash: Hash = hashU32;

    const lhs: u32 = 10;
    const rhs: u32 = 20;
    try testing.expectEqual(stdx.core.Order.lt, compare({}, &lhs, &rhs));
    try testing.expect(less_than({}, &lhs, &rhs));
    try testing.expect(!eql({}, &lhs, &rhs));
    try testing.expectEqual(@as(u64, 10), hash({}, &lhs));
}

test "unit: trait callbacks receive pointer operands" {
    const less_than: stdx.core.LessThan(void, u32) = lessU32;
    const value: u32 = 3;
    try testing.expect(!less_than({}, &value, &value));
}

test "unit: trait callbacks compile with pointer context" {
    const Eql = stdx.core.Eql(*const PointerContext, u32);
    const eql: Eql = eqlWithPointerContext;
    const context = PointerContext{ .bias = 7 };
    const lhs: u32 = 5;
    const rhs: u32 = 5;
    try testing.expect(eql(&context, &lhs, &rhs));
}
