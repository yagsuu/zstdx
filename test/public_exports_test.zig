//! Public facade export contract tests. Spec: docs/specs/root-exports.md.

const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;

const first_slice_root_exports = [_][]const u8{
    "core",
    "bits",
    "addr",
    "ranges",
    "layout",
    "bytes",
    "mem",
    "collections",
    "intrusive",
    "algo",
    "tags",
    "arch",
    "List",
    "Ring",
};

fn expectExactDecls(comptime namespace: type, comptime expected: []const []const u8) !void {
    const actual = @typeInfo(namespace).@"struct".decls;

    try testing.expectEqual(expected.len, actual.len);

    inline for (expected) |name| {
        if (!@hasDecl(namespace, name)) {
            @compileError("missing public export: " ++ name);
        }
    }
}

test "contract: root public exports are exactly the approved first slice" {
    try expectExactDecls(stdx, &first_slice_root_exports);
}

test "contract: root promotions alias canonical collection families" {
    try testing.expect(stdx.List == stdx.collections.List);
    try testing.expect(stdx.List.Static == stdx.collections.List.Static);
    try testing.expect(stdx.List.Bounded == stdx.collections.List.Bounded);

    try testing.expect(stdx.Ring == stdx.collections.Ring);
    try testing.expect(stdx.Ring.Static == stdx.collections.Ring.Static);
    try testing.expect(stdx.Ring.Bounded == stdx.collections.Ring.Bounded);
}

test "contract: root facade does not flatten domain-owned symbols" {
    inline for (.{
        "Address",
        "PhysAddr",
        "VirtAddr",
        "Page",
        "RangeSet",
        "RangeMap",
        "Pool",
        "Arena",
        "BitSet",
        "Cursor",
        "EndianInt",
        "SafetyMode",
        "alignUp",
        "isPowerOfTwo",
        "loadUnaligned",
        "Queue",
        "Stack",
        "io",
    }) |name| {
        try testing.expect(!@hasDecl(stdx, name));
    }
}
