//! Core trait callback contract tests. Spec: docs/specs/core/traits.md.

const std = @import("std");

const zstdx = @import("zstdx");

const testing = std.testing;

fn compareU32(_: void, lhs: *const u32, rhs: *const u32) zstdx.core.Order {
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
    try testing.expectEqual(zstdx.core.Order.lt, zstdx.core.Order.lt);
    _ = zstdx.core.Compare;
    _ = zstdx.core.LessThan;
    _ = zstdx.core.Eql;
    _ = zstdx.core.Hash;
}

test "unit: trait factories compile for void context and scalar values" {
    const Compare = zstdx.core.Compare(void, u32);
    const LessThan = zstdx.core.LessThan(void, u32);
    const Eql = zstdx.core.Eql(void, u32);
    const Hash = zstdx.core.Hash(void, u32);

    const compare: Compare = compareU32;
    const less_than: LessThan = lessU32;
    const eql: Eql = eqlU32;
    const hash: Hash = hashU32;

    const lhs: u32 = 10;
    const rhs: u32 = 20;
    try testing.expectEqual(zstdx.core.Order.lt, compare({}, &lhs, &rhs));
    try testing.expect(less_than({}, &lhs, &rhs));
    try testing.expect(!eql({}, &lhs, &rhs));
    try testing.expectEqual(@as(u64, 10), hash({}, &lhs));
}

test "unit: trait callbacks receive pointer operands" {
    const less_than: zstdx.core.LessThan(void, u32) = lessU32;
    const value: u32 = 3;
    try testing.expect(!less_than({}, &value, &value));
}

test "unit: trait callbacks compile with pointer context" {
    const Eql = zstdx.core.Eql(*const PointerContext, u32);
    const eql: Eql = eqlWithPointerContext;
    const context = PointerContext{ .bias = 7 };
    const lhs: u32 = 5;
    const rhs: u32 = 5;
    try testing.expect(eql(&context, &lhs, &rhs));
}
