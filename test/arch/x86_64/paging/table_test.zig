//! x86_64 paging structure and entry contract tests.
//! Spec: docs/specs/arch/x86_64/paging.md.

const std = @import("std");
const paging = @import("stdx").arch.x86_64.paging;

const testing = std.testing;

fn frame4k(raw: u64) !paging.Phys4K.Frame {
    return paging.Phys4K.Frame.fromAddressInt(raw);
}

fn frame2m(raw: u64) !paging.Phys2M.Frame {
    return paging.Phys2M.Frame.fromAddressInt(raw);
}

fn frame1g(raw: u64) !paging.Phys1G.Frame {
    return paging.Phys1G.Frame.fromAddressInt(raw);
}

fn exerciseMemory(comptime Producer: type) !void {
    const Entry = Producer.Entry;
    const Memory = Producer.Memory;
    var memory = Memory.init();

    for (memory.entries) |entry| {
        try testing.expectEqual(Entry.empty(), entry);
    }

    const before = paging.Index.fromInt(6);
    const target = paging.Index.fromInt(7);
    const after = paging.Index.fromInt(8);
    const metadata = try Entry.nonPresent(0x1234_5678_9abc_def0);
    memory.set(target, metadata);
    try testing.expectEqual(Entry.empty(), memory.get(before));
    try testing.expectEqual(metadata, memory.get(target));
    try testing.expectEqual(@as(u64, 0x1234_5678_9abc_def0), metadata.raw());
    try testing.expectEqual(Entry.empty(), memory.get(after));
    memory.clear(target);
    try testing.expectEqual(Entry.empty(), memory.get(target));
    try testing.expectError(error.Present, Entry.nonPresent(1));
}

test "contract: widths and exact types cover the complete data model" {
    for (0..256) |raw| {
        const value: u8 = @intCast(raw);
        const supported = switch (value) {
            32, 36, 39, 40, 46, 48, 52 => true,
            else => false,
        };
        if (supported) {
            const width = try paging.PhysicalAddressWidth.fromBits(value);
            try testing.expectEqual(@as(u6, @intCast(value)), width.bits());
        } else {
            try testing.expectError(
                error.UnsupportedPhysicalAddressWidth,
                paging.PhysicalAddressWidth.fromBits(value),
            );
        }
    }

    comptime {
        const producers = .{ paging.PML5, paging.PML4, paging.PDPT, paging.PD, paging.PT };
        for (producers, 0..) |Left, left_index| {
            const producer_info = @typeInfo(Left).@"enum";
            if (producer_info.tag_type != u64 or producer_info.is_exhaustive) {
                @compileError("paging producer representation mismatch");
            }
            if (Left.Entry.TagType != Left or Left.Entry.Raw != u64) {
                @compileError("paging entry metadata mismatch");
            }
            if (@sizeOf(Left.Memory) != 4096 or @alignOf(Left.Memory) != 4096) {
                @compileError("paging memory layout mismatch");
            }
            if (@typeInfo(@FieldType(Left.Memory, "entries")).array.len != 512) {
                @compileError("paging memory capacity mismatch");
            }
            for (producers, 0..) |Right, right_index| {
                if (left_index != right_index and Left.Entry == Right.Entry) {
                    @compileError("paging entry types must be distinct");
                }
                if (left_index != right_index and Left.Memory == Right.Memory) {
                    @compileError("paging memory types must be distinct");
                }
            }
        }
    }

    inline for (.{ paging.PML5, paging.PML4, paging.PDPT, paging.PD, paging.PT }) |Producer| {
        try exerciseMemory(Producer);
    }

    const arbitrary: u64 = 0xfedc_ba98_7654_3211;
    try testing.expectEqual(
        arbitrary,
        paging.PagingStructureEntry.fromRaw(arbitrary).raw(),
    );
    try testing.expectEqual(@as(u64, 0), paging.PagingStructureEntry.empty().raw());

    const common_fields = paging.PagingStructureEntry.fromRaw(0x11f);
    try testing.expect(common_fields.present);
    try testing.expect(common_fields.writable);
    try testing.expect(common_fields.user);
    try testing.expect(common_fields.write_through);
    try testing.expect(common_fields.cache_disable);
    try testing.expect(!common_fields.accessed);
    try testing.expect(!common_fields.dirty);
    try testing.expect(!common_fields.page_size_or_pat);
    try testing.expect(common_fields.global_or_ignored);
    try testing.expectEqual(@as(u3, 0), common_fields.available_low);
    try testing.expectEqual(@as(u40, 0), common_fields.physical_address_bits);
    try testing.expectEqual(@as(u11, 0), common_fields.available_high);
    try testing.expect(!common_fields.no_execute);
}

test "model: table transitions and entry addresses preserve exact levels" {
    const pml5 = try paging.PML5.init(try frame4k(0x1000));
    const pml4 = try paging.PML4.init(try frame4k(0x2000));
    const pdpt = try paging.PDPT.init(try frame4k(0x3000));
    const pd = try paging.PD.init(try frame4k(0x4000));
    const pt = try paging.PT.init(try frame4k(0x5000));
    const flags = paging.TableEntryFlags{
        .writable = true,
        .user = true,
        .write_through = true,
        .cache_disable = true,
        .accessed = true,
        .no_execute = true,
        .available_low = 0b101,
        .available_high = 0x155,
    };
    const flag_bits = @as(u64, 1) |
        (@as(u64, 0b1_1111) << 1) |
        (@as(u64, 0b101) << 9) |
        (@as(u64, 0x155) << 52) |
        (@as(u64, 1) << 63);

    try testing.expectEqual(pml4.base().addressInt() | flag_bits, paging.PML5.tableEntry(pml4, flags).raw());
    try testing.expectEqual(pdpt.base().addressInt() | flag_bits, paging.PML4.tableEntry(pdpt, flags).raw());
    try testing.expectEqual(pd.base().addressInt() | flag_bits, paging.PDPT.tableEntry(pd, flags).raw());
    try testing.expectEqual(pt.base().addressInt() | flag_bits, paging.PD.tableEntry(pt, flags).raw());

    inline for (.{ pml5, pml4, pdpt, pd, pt }) |producer| {
        try testing.expectEqual(producer.base().address(), producer.entryAddress(.fromInt(0)));
        try testing.expectEqual(
            producer.base().addressInt() + 511 * @sizeOf(u64),
            producer.entryAddress(.fromInt(511)).raw(),
        );
    }
}

test "model: construction flags occupy independent architectural fields" {
    const pdpt = try paging.PDPT.init(try frame4k(0));
    const table_cases = [_]struct { flags: paging.TableEntryFlags, bits: u64 }{
        .{ .flags = .{ .writable = true }, .bits = @as(u64, 1) << 1 },
        .{ .flags = .{ .user = true }, .bits = @as(u64, 1) << 2 },
        .{ .flags = .{ .write_through = true }, .bits = @as(u64, 1) << 3 },
        .{ .flags = .{ .cache_disable = true }, .bits = @as(u64, 1) << 4 },
        .{ .flags = .{ .accessed = true }, .bits = @as(u64, 1) << 5 },
        .{ .flags = .{ .available_low = 0b111 }, .bits = @as(u64, 0b111) << 9 },
        .{ .flags = .{ .available_high = 0x7ff }, .bits = @as(u64, 0x7ff) << 52 },
        .{ .flags = .{ .no_execute = true }, .bits = @as(u64, 1) << 63 },
    };
    for (table_cases) |case| {
        try testing.expectEqual(@as(u64, 1) | case.bits, paging.PML4.tableEntry(pdpt, case.flags).raw());
    }

    const page4k = try frame4k(0);
    const page2m = try frame2m(0);
    const page1g = try frame1g(0);
    const page_cases = [_]struct {
        flags: paging.PageFlags,
        page4k_bits: u64,
        large_page_bits: u64,
    }{
        .{ .flags = .{ .writable = true }, .page4k_bits = @as(u64, 1) << 1, .large_page_bits = @as(u64, 1) << 1 },
        .{ .flags = .{ .user = true }, .page4k_bits = @as(u64, 1) << 2, .large_page_bits = @as(u64, 1) << 2 },
        .{ .flags = .{ .write_through = true }, .page4k_bits = @as(u64, 1) << 3, .large_page_bits = @as(u64, 1) << 3 },
        .{ .flags = .{ .cache_disable = true }, .page4k_bits = @as(u64, 1) << 4, .large_page_bits = @as(u64, 1) << 4 },
        .{ .flags = .{ .accessed = true }, .page4k_bits = @as(u64, 1) << 5, .large_page_bits = @as(u64, 1) << 5 },
        .{ .flags = .{ .dirty = true }, .page4k_bits = @as(u64, 1) << 6, .large_page_bits = @as(u64, 1) << 6 },
        .{ .flags = .{ .pat = true }, .page4k_bits = @as(u64, 1) << 7, .large_page_bits = @as(u64, 1) << 12 },
        .{ .flags = .{ .global = true }, .page4k_bits = @as(u64, 1) << 8, .large_page_bits = @as(u64, 1) << 8 },
        .{ .flags = .{ .available_low = 0b111 }, .page4k_bits = @as(u64, 0b111) << 9, .large_page_bits = @as(u64, 0b111) << 9 },
        .{ .flags = .{ .available_high = 0x7ff }, .page4k_bits = @as(u64, 0x7ff) << 52, .large_page_bits = @as(u64, 0x7ff) << 52 },
        .{ .flags = .{ .no_execute = true }, .page4k_bits = @as(u64, 1) << 63, .large_page_bits = @as(u64, 1) << 63 },
    };
    for (page_cases) |case| {
        try testing.expectEqual(
            @as(u64, 1) | case.page4k_bits,
            (try paging.PT.pageEntry(page4k, case.flags)).raw(),
        );
        const large_expected =
            @as(u64, 1) | (@as(u64, 1) << 7) | case.large_page_bits;
        try testing.expectEqual(
            large_expected,
            (try paging.PD.pageEntry(page2m, case.flags)).raw(),
        );
        try testing.expectEqual(
            large_expected,
            (try paging.PDPT.pageEntry(page1g, case.flags)).raw(),
        );
    }
}

test "model: page encodings preserve size geometry and PAT placement" {
    const flags = paging.PageFlags{
        .writable = true,
        .user = true,
        .dirty = true,
        .global = true,
        .pat = true,
    };
    const common = @as(u64, 1) |
        (@as(u64, 1) << 1) |
        (@as(u64, 1) << 2) |
        (@as(u64, 1) << 6) |
        (@as(u64, 1) << 8);
    const base4k: u64 = 0x0000_0000_1234_5000;
    const base2m: u64 = 0x0000_0000_1220_0000;
    const base1g: u64 = 0x0000_0000_8000_0000;

    try testing.expectEqual(base4k | common | (@as(u64, 1) << 7), (try paging.PT.pageEntry(try frame4k(base4k), flags)).raw());
    try testing.expectEqual(base2m | common | (@as(u64, 1) << 7) | (@as(u64, 1) << 12), (try paging.PD.pageEntry(try frame2m(base2m), flags)).raw());
    try testing.expectEqual(base1g | common | (@as(u64, 1) << 7) | (@as(u64, 1) << 12), (try paging.PDPT.pageEntry(try frame1g(base1g), flags)).raw());

    const frames = [_]paging.PageFrame{
        .{ .page4kib = try frame4k(base4k) },
        .{ .page2mib = try frame2m(base2m) },
        .{ .page1gib = try frame1g(base1g) },
    };
    const levels = [_]paging.Level{ .pt, .pd, .pdpt };
    for (frames, levels) |frame, level| {
        try testing.expectEqual(level, frame.level());
        try testing.expectEqual(level.pageSizeBytes().?, frame.sizeBytes());
        try testing.expectEqual(level.pageOffsetBits().?, frame.offsetBits());
        try testing.expectEqual(level.pageOffsetMask().?, frame.offsetMask());
    }
}

test "unit: producer and page overflow fail before caller memory changes" {
    const too_wide = @as(u64, 1) << 52;
    try testing.expectError(
        error.PhysicalAddressTooWide,
        paging.PML4.init(try frame4k(too_wide)),
    );

    var memory = paging.PT.Memory.init();
    const sentinel = try paging.PT.Entry.nonPresent(0x200);
    memory.set(.fromInt(9), sentinel);

    try testing.expectError(error.PhysicalAddressTooWide, paging.PT.pageEntry(try frame4k(too_wide), .{}));
    try testing.expectError(error.PhysicalAddressTooWide, paging.PD.pageEntry(try frame2m(too_wide), .{}));
    try testing.expectError(error.PhysicalAddressTooWide, paging.PDPT.pageEntry(try frame1g(too_wide), .{}));
    try testing.expectEqual(sentinel, memory.get(.fromInt(9)));
}
