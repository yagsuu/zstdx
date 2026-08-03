//! x86_64 paging address and geometry contract tests.
//! Spec: docs/specs/arch/x86_64/paging.md.

const std = @import("std");
const paging = @import("stdx").arch.x86_64.paging;

const testing = std.testing;

test "model: paging modes and levels expose complete geometry" {
    try testing.expectEqual(paging.Level.pml4, paging.Mode.level4.rootLevel());
    try testing.expectEqual(@as(u8, 48), paging.Mode.level4.linearBits());
    try testing.expectEqual(paging.Level.pml5, paging.Mode.level5.rootLevel());
    try testing.expectEqual(@as(u8, 57), paging.Mode.level5.linearBits());

    const levels = [_]paging.Level{ .pt, .pd, .pdpt, .pml4, .pml5 };
    const shifts = [_]u6{ 12, 21, 30, 39, 48 };
    const next = [_]?paging.Level{ null, .pt, .pd, .pdpt, .pml4 };
    const offset_bits = [_]?u6{ 12, 21, 30, null, null };
    const sizes = [_]?u64{ 4096, 2 * 1024 * 1024, 1024 * 1024 * 1024, null, null };

    for (levels, shifts, next, offset_bits, sizes) |level, shift, next_level, offset, size| {
        try testing.expectEqual(shift, level.indexShift());
        try testing.expectEqual(next_level, level.next());
        try testing.expectEqual(offset, level.pageOffsetBits());
        try testing.expectEqual(size, level.pageSizeBytes());
        try testing.expectEqual(
            if (size) |bytes| bytes - 1 else null,
            level.pageOffsetMask(),
        );
    }
}

test "model: canonical validation and sign extension distinguish both modes" {
    const cases = [_]struct {
        mode: paging.Mode,
        low: u64,
        high: u64,
        noncanonical: u64,
        unextended: u64,
    }{
        .{
            .mode = .level4,
            .low = 0x0000_7fff_ffff_ffff,
            .high = 0xffff_8000_0000_0000,
            .noncanonical = 0x0000_8000_0000_0000,
            .unextended = 0x0000_8000_0000_0001,
        },
        .{
            .mode = .level5,
            .low = 0x00ff_ffff_ffff_ffff,
            .high = 0xff00_0000_0000_0000,
            .noncanonical = 0x0100_0000_0000_0000,
            .unextended = 0x0100_0000_0000_0001,
        },
    };

    for (cases) |case| {
        const low = try paging.LinearAddress.fromCanonical(case.low, case.mode);
        const high = try paging.LinearAddress.fromCanonical(case.high, case.mode);
        try testing.expect(low.isCanonical(case.mode));
        try testing.expect(high.isCanonical(case.mode));
        try testing.expectError(
            error.NonCanonical,
            paging.LinearAddress.fromCanonical(case.noncanonical, case.mode),
        );
        try testing.expectEqual(
            case.high | 1,
            paging.LinearAddress.signExtend(case.unextended, case.mode).raw(),
        );
    }

    const arbitrary = paging.LinearAddress.fromInt(0x0123_4567_89ab_cdef);
    try testing.expectEqual(@as(u64, 0x0123_4567_89ab_cdef), arbitrary.raw());
}

test "model: index extraction covers every level in both modes" {
    const raw4 = (@as(u64, 0x55) << 39) |
        (@as(u64, 0x66) << 30) |
        (@as(u64, 0x77) << 21) |
        (@as(u64, 0x88) << 12) |
        0xabc;
    const raw5 = (@as(u64, 0x55) << 48) | raw4;

    const cases = [_]struct {
        mode: paging.Mode,
        raw: u64,
        expected: [5]u9,
    }{
        .{ .mode = .level4, .raw = raw4, .expected = .{ 0, 0x55, 0x66, 0x77, 0x88 } },
        .{ .mode = .level5, .raw = raw5, .expected = .{ 0x55, 0x55, 0x66, 0x77, 0x88 } },
    };
    const levels = [_]paging.Level{ .pml5, .pml4, .pdpt, .pd, .pt };

    for (cases) |case| {
        const indices = (try paging.LinearAddress.fromCanonical(case.raw, case.mode))
            .indices(case.mode);
        for (levels, case.expected) |level, expected| {
            const index = indices.at(level);
            try testing.expectEqual(expected, index.raw());
            try testing.expectEqual(index, paging.Index.fromInt(expected));
        }
    }
}
