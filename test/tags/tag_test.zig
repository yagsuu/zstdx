//! Tag value-type tests. See `docs/specs/tags/tag-allocator.md`.

const std = @import("std");
const stdx = @import("stdx");

const Tag = stdx.tags.Tag;

const testing = std.testing;

const DomainA = struct {};
const DomainB = struct {};
const DomainC = struct {};

test "unit: Tag(D, u16).fromInt/raw round-trips at zero, midpoint, and max" {
    const T = Tag(DomainA, u16);
    try testing.expectEqual(@as(u16, 0), T.fromInt(0).raw());
    try testing.expectEqual(@as(u16, 0x4321), T.fromInt(0x4321).raw());
    try testing.expectEqual(
        @as(u16, std.math.maxInt(u16)),
        T.fromInt(std.math.maxInt(u16)).raw(),
    );
}

test "unit: Tag exposes Domain and Int comptime decls" {
    const T = Tag(DomainA, u16);
    try testing.expect(T.Domain == DomainA);
    try testing.expect(T.Int == u16);
}

test "compile: Tag(A, u16) and Tag(B, u16) are distinct types" {
    comptime {
        std.debug.assert(Tag(DomainA, u16) != Tag(DomainB, u16));
        std.debug.assert(Tag(DomainA, u16) != Tag(DomainC, u16));
    }
    try testing.expect(Tag(DomainA, u16) != Tag(DomainB, u16));
}

test "compile: Tag(D, u16) and Tag(D, u32) are distinct types" {
    comptime std.debug.assert(Tag(DomainA, u16) != Tag(DomainA, u32));
    try testing.expect(Tag(DomainA, u16) != Tag(DomainA, u32));
}

test "compile: Tag(D, I) tag-type identity is stable across recall" {
    comptime std.debug.assert(Tag(DomainA, u16) == Tag(DomainA, u16));
    try testing.expect(Tag(DomainA, u16) == Tag(DomainA, u16));
}

test "unit: Tag(D, u1) carries the narrowest unsigned width" {
    const T = Tag(DomainA, u1);
    try testing.expectEqual(@as(u1, 0), T.fromInt(0).raw());
    try testing.expectEqual(@as(u1, 1), T.fromInt(1).raw());
}

test "unit: Tag(D, u64) carries the widest unsigned width" {
    const T = Tag(DomainA, u64);
    try testing.expectEqual(
        @as(u64, std.math.maxInt(u64)),
        T.fromInt(std.math.maxInt(u64)).raw(),
    );
}

// Compile-error cases (declaring `Tag(D, i32)` or `Tag(D, f32)`) are
// guarded by `@compileError` in `src/tags/tag.zig` and cannot be tested at
// runtime in Zig. The comptime instantiations pin the contract for valid
// Int widths.
