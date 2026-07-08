//! x86_64 paging primitive contract tests.
//! Spec: docs/specs/arch/x86_64/paging.md.

const std = @import("std");

const stdx = @import("stdx");

const paging = stdx.arch.x86_64.paging;
const testing = std.testing;

const Slot = struct {
    address: u64,
    entry: paging.Entry,
};

const MemoryReader = struct {
    pub const Error = error{MissingEntry};

    slots: []const Slot,

    pub fn readEntry(self: *MemoryReader, address: paging.PhysAddr) Error!paging.Entry {
        const raw = address.raw();
        for (self.slots) |slot| {
            if (slot.address == raw) return slot.entry;
        }
        return error.MissingEntry;
    }
};

const full_features = paging.Features{
    .pcid = true,
    .no_execute = true,
    .page_1gib = true,
    .supervisor_write_protect = true,
};
const no_pcid_features = paging.Features{
    .pcid = false,
    .no_execute = true,
    .page_1gib = true,
    .supervisor_write_protect = true,
};
const no_1g_features = paging.Features{
    .pcid = true,
    .no_execute = true,
    .page_1gib = false,
    .supervisor_write_protect = true,
};
const no_write_protect_features = paging.Features{
    .pcid = true,
    .no_execute = true,
    .page_1gib = true,
    .supervisor_write_protect = false,
};
const nx_disabled_features = paging.Features{
    .pcid = true,
    .no_execute = false,
    .page_1gib = true,
    .supervisor_write_protect = true,
};

const user_table_flags = paging.table.Flags{ .writable = true, .user = true };
const readonly_user_table_flags = paging.table.Flags{ .writable = false, .user = true };
const supervisor_table_flags = paging.table.Flags{ .writable = true, .user = false };

const user_leaf_flags = paging.leaf.Flags{ .writable = true, .user = true };
const readonly_user_leaf_flags = paging.leaf.Flags{ .writable = false, .user = true };
const nx_user_leaf_flags = paging.leaf.Flags{ .writable = true, .user = true, .no_execute = true };

fn config(mode: paging.Mode, physical_bits: u8, f: paging.Features) paging.Config {
    return .{
        .mode = mode,
        .physical_bits = physical_bits,
        .features = f,
    };
}

fn config4() paging.Config {
    return config(.level4, 52, full_features);
}

fn frame4k(address: u64) !paging.Phys4K.Frame {
    return paging.Phys4K.Frame.fromAddressInt(address);
}

fn frame2m(address: u64) !paging.Phys2M.Frame {
    return paging.Phys2M.Frame.fromAddressInt(address);
}

fn frame1g(address: u64) !paging.Phys1G.Frame {
    return paging.Phys1G.Frame.fromAddressInt(address);
}

fn phys(address: u64) paging.PhysAddr {
    return paging.PhysAddr.fromInt(address);
}

fn rootAt(address: u64) !paging.Root {
    return .{
        .frame = try frame4k(address),
        .pcid = 0,
        .write_through = false,
        .cache_disable = false,
    };
}

fn linearRaw(opts: struct {
    pml5: u9,
    pml4: u9,
    pdpt: u9,
    pd: u9,
    pt: u9,
    offset: u12,
}) u64 {
    return (@as(u64, opts.pml5) << 48) |
        (@as(u64, opts.pml4) << 39) |
        (@as(u64, opts.pdpt) << 30) |
        (@as(u64, opts.pd) << 21) |
        (@as(u64, opts.pt) << 12) |
        @as(u64, opts.offset);
}

fn linear4() u64 {
    return linearRaw(.{
        .pml5 = 0,
        .pml4 = 1,
        .pdpt = 2,
        .pd = 3,
        .pt = 4,
        .offset = 0x05a,
    });
}

fn linear5() u64 {
    return linearRaw(.{
        .pml5 = 5,
        .pml4 = 1,
        .pdpt = 2,
        .pd = 3,
        .pt = 4,
        .offset = 0x05a,
    });
}

fn entryAddress(table_base: u64, index: u9) u64 {
    return table_base + @as(u64, index) * @as(u64, @sizeOf(paging.Entry));
}

fn tableEntry(frame_address: u64, flags: paging.table.Flags) !paging.Entry {
    return paging.table.entry(try frame4k(frame_address), flags);
}

fn leaf4kEntry(frame_address: u64, flags: paging.leaf.Flags) !paging.Entry {
    return paging.leaf.page4kib(try frame4k(frame_address), flags);
}

fn leaf2mEntry(frame_address: u64, flags: paging.leaf.Flags) !paging.Entry {
    return paging.leaf.page2mib(try frame2m(frame_address), flags);
}

fn leaf1gEntry(frame_address: u64, flags: paging.leaf.Flags) !paging.Entry {
    return paging.leaf.page1gib(try frame1g(frame_address), flags);
}

fn expectMapped(result: paging.walk.Result) !paging.walk.Mapping {
    return switch (result) {
        .mapped => |mapping| mapping,
        .fault => error.ExpectedMapped,
    };
}

fn expectFault(result: paging.walk.Result) !paging.walk.Fault {
    return switch (result) {
        .mapped => error.ExpectedFault,
        .fault => |fault| fault,
    };
}

fn runWalk(
    cfg: paging.Config,
    slots: []const Slot,
    root: paging.Root,
    raw_linear: u64,
    access: paging.walk.Access,
) !paging.walk.Result {
    const reader = MemoryReader{ .slots = slots };
    var walker = paging.Walker(MemoryReader).init(cfg, reader);
    return walker.walkRaw(root, raw_linear, access);
}

fn expectTableInitEmpty(comptime level: paging.Level) !void {
    const Table = paging.table.Type(level);
    const table_value = Table.init();
    for (table_value.entries) |entry| {
        try testing.expectEqual(paging.Entry.empty().raw(), entry.raw());
    }
}

test "unit: mode and level helpers report architectural widths and shifts" {
    try testing.expectEqual(paging.Level.pml4, paging.Mode.level4.rootLevel());
    try testing.expectEqual(@as(u8, 48), paging.Mode.level4.linearBits());
    try testing.expectEqual(paging.Level.pml5, paging.Mode.level5.rootLevel());
    try testing.expectEqual(@as(u8, 57), paging.Mode.level5.linearBits());

    try testing.expectEqual(@as(u6, 12), paging.Level.pt.indexShift());
    try testing.expectEqual(@as(u6, 21), paging.Level.pd.indexShift());
    try testing.expectEqual(@as(u6, 30), paging.Level.pdpt.indexShift());
    try testing.expectEqual(@as(u6, 39), paging.Level.pml4.indexShift());
    try testing.expectEqual(@as(u6, 48), paging.Level.pml5.indexShift());
}

test "unit: canonical checks distinguish implemented 48-bit and 57-bit ranges" {
    try testing.expect(paging.linear.isCanonical(0x0000_0000_0000_0000, .level4));
    try testing.expect(paging.linear.isCanonical(0x0000_7fff_ffff_ffff, .level4));
    try testing.expect(paging.linear.isCanonical(0xffff_8000_0000_0000, .level4));
    try testing.expect(paging.linear.isCanonical(0xffff_ffff_ffff_ffff, .level4));

    try testing.expect(!paging.linear.isCanonical(0x0000_8000_0000_0000, .level4));
    try testing.expect(!paging.linear.isCanonical(0xffff_7fff_ffff_ffff, .level4));
    try testing.expectError(error.NonCanonical, paging.linear.fromCanonical(0x0000_8000_0000_0000, .level4));

    try testing.expect(paging.linear.isCanonical(0x00ff_ffff_ffff_ffff, .level5));
    try testing.expect(paging.linear.isCanonical(0xff00_0000_0000_0000, .level5));
}

test "unit: signExtend uses the active high implemented linear bit" {
    try testing.expectEqual(
        @as(u64, 0xffff_8000_0000_0001),
        paging.linear.signExtend(0x0000_8000_0000_0001, .level4).raw(),
    );
    try testing.expectEqual(
        @as(u64, 0x0000_0000_0000_1234),
        paging.linear.signExtend(0xffff_0000_0000_1234, .level4).raw(),
    );
    try testing.expectEqual(
        @as(u64, 0xff00_0000_0000_1234),
        paging.linear.signExtend(0x0100_0000_0000_1234, .level5).raw(),
    );
}

test "unit: indices extracts every paging level index" {
    const raw4 = linearRaw(.{ .pml5 = 0, .pml4 = 0x012, .pdpt = 0x034, .pd = 0x056, .pt = 0x078, .offset = 0x9ab });
    const idx4 = try paging.linear.indices(try paging.linear.fromCanonical(raw4, .level4), .level4);
    try testing.expectEqual(@as(u9, 0), idx4.pml5.raw());
    try testing.expectEqual(@as(u9, 0x012), idx4.pml4.raw());
    try testing.expectEqual(@as(u9, 0x034), idx4.pdpt.raw());
    try testing.expectEqual(@as(u9, 0x056), idx4.pd.raw());
    try testing.expectEqual(@as(u9, 0x078), idx4.pt.raw());
    try testing.expectEqual(@as(u12, 0x9ab), idx4.offset_4kib);
    try testing.expectEqual(idx4.pd.raw(), idx4.at(.pd).raw());

    const raw5 = linearRaw(.{ .pml5 = 0x01a, .pml4 = 0x02b, .pdpt = 0x03c, .pd = 0x04d, .pt = 0x05e, .offset = 0x6f0 });
    const idx5 = try paging.linear.indices(try paging.linear.fromCanonical(raw5, .level5), .level5);
    try testing.expectEqual(@as(u9, 0x01a), idx5.pml5.raw());
    try testing.expectEqual(@as(u9, 0x02b), idx5.pml4.raw());
    try testing.expectEqual(@as(u9, 0x03c), idx5.pdpt.raw());
    try testing.expectEqual(@as(u9, 0x04d), idx5.pd.raw());
    try testing.expectEqual(@as(u9, 0x05e), idx5.pt.raw());
    try testing.expectEqual(@as(u12, 0x6f0), idx5.offset_4kib);
    try testing.expectEqual(idx5.pml5.raw(), idx5.at(.pml5).raw());
}

test "unit: Config.validate rejects physical widths outside the architectural range" {
    var cfg = config4();

    cfg.physical_bits = 31;
    try testing.expectError(error.InvalidPhysicalWidth, cfg.validate());

    cfg.physical_bits = 53;
    try testing.expectError(error.InvalidPhysicalWidth, cfg.validate());

    cfg.physical_bits = 32;
    try cfg.validate();

    cfg.physical_bits = 52;
    try cfg.validate();
}

test "unit: Root.fromCr3 decodes PCID and non-PCID low bits and rejects reserved roots" {
    const pcid_cfg = config(.level4, 52, full_features);
    const pcid_root = try paging.Root.fromCr3(0x0000_0000_1234_5000 | 0x0abc, pcid_cfg);
    try testing.expectEqual(@as(u64, 0x0000_0000_1234_5000), pcid_root.frame.addressInt());
    try testing.expectEqual(@as(u12, 0x0abc), pcid_root.pcid);
    try testing.expect(!pcid_root.write_through);
    try testing.expect(!pcid_root.cache_disable);

    const non_pcid_cfg = config(.level4, 52, no_pcid_features);
    const non_pcid_root = try paging.Root.fromCr3(0x0000_0000_2234_5000 | (1 << 3) | (1 << 4), non_pcid_cfg);
    try testing.expectEqual(@as(u64, 0x0000_0000_2234_5000), non_pcid_root.frame.addressInt());
    try testing.expectEqual(@as(u12, 0), non_pcid_root.pcid);
    try testing.expect(non_pcid_root.write_through);
    try testing.expect(non_pcid_root.cache_disable);

    try testing.expectError(error.ReservedBits, paging.Root.fromCr3(0x3000 | 0x1, non_pcid_cfg));

    const narrow_cfg = config(.level4, 32, full_features);
    try testing.expectError(error.PhysicalAddressTooWide, paging.Root.fromCr3(0x0000_0001_0000_0000, narrow_cfg));
}

test "unit: Root.toCr3 round-trips PCID and cache-control encodings" {
    const pcid_cfg = config(.level4, 52, full_features);
    const pcid_root = paging.Root{
        .frame = try frame4k(0x0000_0000_0000_4000),
        .pcid = 0x345,
        .write_through = false,
        .cache_disable = false,
    };
    const pcid_raw = try pcid_root.toCr3(pcid_cfg);
    try testing.expectEqual(@as(u64, 0x4345), pcid_raw);
    const pcid_decoded = try paging.Root.fromCr3(pcid_raw, pcid_cfg);
    try testing.expectEqual(pcid_root.frame.addressInt(), pcid_decoded.frame.addressInt());
    try testing.expectEqual(pcid_root.pcid, pcid_decoded.pcid);

    const non_pcid_cfg = config(.level4, 52, no_pcid_features);
    const non_pcid_root = paging.Root{
        .frame = try frame4k(0x0000_0000_0000_8000),
        .pcid = 0,
        .write_through = true,
        .cache_disable = true,
    };
    const non_pcid_raw = try non_pcid_root.toCr3(non_pcid_cfg);
    try testing.expectEqual(@as(u64, 0x8018), non_pcid_raw);
    const non_pcid_decoded = try paging.Root.fromCr3(non_pcid_raw, non_pcid_cfg);
    try testing.expectEqual(non_pcid_root.frame.addressInt(), non_pcid_decoded.frame.addressInt());
    try testing.expect(non_pcid_decoded.write_through);
    try testing.expect(non_pcid_decoded.cache_disable);
}

test "unit: Entry raw values round-trip and kind is structural at every level" {
    const raws = [_]u64{ 0, 1, 0x8000_0000_0000_0001, 0xffff_ffff_ffff_ffff, 0x0123_4567_89ab_cdef };
    for (raws) |raw| {
        try testing.expectEqual(raw, paging.Entry.fromRaw(raw).raw());
    }

    try testing.expectEqual(paging.Entry.Kind.not_present, paging.Entry.fromRaw(0).kind(.pml5));
    try testing.expectEqual(paging.Entry.Kind.not_present, paging.Entry.fromRaw(0).kind(.pml4));
    try testing.expectEqual(paging.Entry.Kind.not_present, paging.Entry.fromRaw(0).kind(.pdpt));
    try testing.expectEqual(paging.Entry.Kind.not_present, paging.Entry.fromRaw(0).kind(.pd));
    try testing.expectEqual(paging.Entry.Kind.not_present, paging.Entry.fromRaw(0).kind(.pt));

    const present_table = paging.Entry.fromRaw(0x1000 | 1);
    try testing.expectEqual(paging.Entry.Kind.table, present_table.kind(.pml5));
    try testing.expectEqual(paging.Entry.Kind.table, present_table.kind(.pml4));
    try testing.expectEqual(paging.Entry.Kind.table, present_table.kind(.pdpt));
    try testing.expectEqual(paging.Entry.Kind.table, present_table.kind(.pd));
    try testing.expectEqual(paging.Entry.Kind.leaf, present_table.kind(.pt));

    const large = paging.Entry.fromRaw(0x80 | 1);
    try testing.expectEqual(paging.Entry.Kind.table, large.kind(.pml5));
    try testing.expectEqual(paging.Entry.Kind.table, large.kind(.pml4));
    try testing.expectEqual(paging.Entry.Kind.leaf, large.kind(.pdpt));
    try testing.expectEqual(paging.Entry.Kind.leaf, large.kind(.pd));
}

test "unit: Entry.reservedBits reports architectural reserved-bit categories" {
    const nx_enabled = config(.level4, 52, full_features);
    const nx_disabled = config(.level4, 52, nx_disabled_features);
    const no_1g = config(.level4, 52, no_1g_features);
    const phys40 = config(.level4, 40, full_features);

    const not_present_mask = paging.Entry.fromRaw(std.math.maxInt(u64) & ~@as(u64, 1))
        .reservedBits(.pml4, nx_enabled).mask;
    try testing.expectEqual(@as(u64, 0), not_present_mask);

    const bit7 = paging.Entry.fromRaw((1 << 7) | 1);
    try testing.expect((bit7.reservedBits(.pml4, nx_enabled).mask & (1 << 7)) != 0);
    try testing.expect((bit7.reservedBits(.pml5, nx_enabled).mask & (1 << 7)) != 0);

    const nx = paging.Entry.fromRaw((@as(u64, 1) << 63) | 1);
    try testing.expect((nx.reservedBits(.pt, nx_disabled).mask & (@as(u64, 1) << 63)) != 0);

    const too_wide = paging.Entry.fromRaw((@as(u64, 1) << 40) | 1);
    try testing.expect((too_wide.reservedBits(.pml4, phys40).mask & (@as(u64, 1) << 40)) != 0);

    const misaligned_2m = paging.Entry.fromRaw((1 << 7) | (1 << 12) | 1);
    try testing.expect((misaligned_2m.reservedBits(.pd, nx_enabled).mask & (1 << 12)) != 0);

    const misaligned_1g = paging.Entry.fromRaw((1 << 7) | (1 << 21) | 1);
    try testing.expect((misaligned_1g.reservedBits(.pdpt, nx_enabled).mask & (1 << 21)) != 0);

    const one_gib_leaf = paging.Entry.fromRaw((1 << 7) | 1);
    try testing.expect(one_gib_leaf.reservedBits(.pdpt, no_1g).any());
}

test "unit: paging table types have 512 raw-preserving entries in one page" {
    inline for (.{
        paging.table.Pml5,
        paging.table.Pml4,
        paging.table.Pdpt,
        paging.table.Pd,
        paging.table.Pt,
    }) |Table| {
        try testing.expectEqual(@as(usize, 4096), @sizeOf(Table));
        try testing.expectEqual(@as(usize, 512), @typeInfo(@FieldType(Table, "entries")).array.len);
    }
}

test "unit: table init fills entries empty and get/set/clear only touch the selected index" {
    try expectTableInitEmpty(.pml5);
    try expectTableInitEmpty(.pml4);
    try expectTableInitEmpty(.pdpt);
    try expectTableInitEmpty(.pd);
    try expectTableInitEmpty(.pt);

    var table_value = paging.table.Pt.init();
    const target = paging.Index.fromInt(7);
    const before = paging.Index.fromInt(6);
    const after = paging.Index.fromInt(8);
    const entry = paging.Entry.fromRaw(0x0000_0000_dead_b001);

    table_value.set(target, entry);
    try testing.expectEqual(paging.Entry.empty().raw(), table_value.get(before).raw());
    try testing.expectEqual(entry.raw(), table_value.get(target).raw());
    try testing.expectEqual(paging.Entry.empty().raw(), table_value.get(after).raw());

    table_value.clear(target);
    try testing.expectEqual(paging.Entry.empty().raw(), table_value.get(target).raw());
    try testing.expectEqual(paging.Entry.empty().raw(), table_value.get(before).raw());
    try testing.expectEqual(paging.Entry.empty().raw(), table_value.get(after).raw());
}

test "unit: table entries round-trip 4 KiB frames" {
    const cfg = config4();
    const frame = try frame4k(0x0000_0000_0045_6000);
    const entry = paging.table.entry(frame, .{ .writable = true, .user = true, .no_execute = true });

    try testing.expectEqual(paging.Entry.Kind.table, entry.kind(.pml4));
    const extracted = try paging.table.frame(entry, .pml4, cfg);
    try testing.expectEqual(frame.addressInt(), extracted.addressInt());
}

test "unit: leaf entries and helpers round-trip typed page frames" {
    const cfg = config4();

    const frame_4k = try frame4k(0x0000_0000_0000_9000);
    const entry_4k = paging.leaf.page4kib(frame_4k, user_leaf_flags);
    const extracted_4k = try paging.leaf.frame(entry_4k, .pt, cfg);
    try testing.expectEqual(paging.Level.pt, extracted_4k.level());
    try testing.expectEqual(frame_4k.addressInt(), extracted_4k.addressInt());

    const frame_2m = try frame2m(0x0000_0000_0040_0000);
    const entry_2m = paging.leaf.page2mib(frame_2m, user_leaf_flags);
    const extracted_2m = try paging.leaf.frame(entry_2m, .pd, cfg);
    try testing.expectEqual(paging.Level.pd, extracted_2m.level());
    try testing.expectEqual(frame_2m.addressInt(), extracted_2m.addressInt());

    const frame_1g = try frame1g(0x0000_0000_4000_0000);
    const entry_1g = paging.leaf.page1gib(frame_1g, user_leaf_flags);
    const extracted_1g = try paging.leaf.frame(entry_1g, .pdpt, cfg);
    try testing.expectEqual(paging.Level.pdpt, extracted_1g.level());
    try testing.expectEqual(frame_1g.addressInt(), extracted_1g.addressInt());
}

test "unit: leaf offset and mapping methods report page size geometry" {
    try testing.expectEqual(@as(?u6, 12), paging.leaf.offsetBits(.pt));
    try testing.expectEqual(@as(?u6, 21), paging.leaf.offsetBits(.pd));
    try testing.expectEqual(@as(?u6, 30), paging.leaf.offsetBits(.pdpt));
    try testing.expectEqual(@as(?u6, null), paging.leaf.offsetBits(.pml4));
    try testing.expectEqual(@as(?u6, null), paging.leaf.offsetBits(.pml5));

    try testing.expectEqual(@as(?u64, 4096), paging.leaf.sizeBytes(.pt));
    try testing.expectEqual(@as(?u64, 2 * 1024 * 1024), paging.leaf.sizeBytes(.pd));
    try testing.expectEqual(@as(?u64, 1024 * 1024 * 1024), paging.leaf.sizeBytes(.pdpt));

    try testing.expectEqual(@as(?u64, 0x0000_0000_0000_0fff), paging.leaf.offsetMask(.pt));
    try testing.expectEqual(@as(?u64, 0x0000_0000_001f_ffff), paging.leaf.offsetMask(.pd));
    try testing.expectEqual(@as(?u64, 0x0000_0000_3fff_ffff), paging.leaf.offsetMask(.pdpt));

    const frame = paging.leaf.Frame{ .page2mib = try frame2m(0x0000_0000_0060_0000) };
    try testing.expectEqual(paging.Level.pd, frame.level());
    try testing.expectEqual(@as(u64, 0x0000_0000_0060_0000), frame.addressInt());
    try testing.expectEqual(@as(u64, 2 * 1024 * 1024), frame.sizeBytes());
    try testing.expectEqual(@as(u6, 21), frame.offsetBits());
    try testing.expectEqual(@as(u64, 0x0000_0000_001f_ffff), frame.offsetMask());

    const mapping = paging.leaf.Mapping{
        .level = .pd,
        .frame = frame,
        .entry_address = phys(0x0000_0000_0000_3018),
        .entry = paging.leaf.page2mib(try frame2m(0x0000_0000_0060_0000), user_leaf_flags),
    };
    try testing.expectEqual(frame.addressInt(), mapping.base().raw());
    try testing.expectEqual(frame.sizeBytes(), mapping.sizeBytes());
    try testing.expectEqual(frame.offsetBits(), mapping.offsetBits());
    try testing.expectEqual(frame.offsetMask(), mapping.offsetMask());
}

test "unit: Walker.walkRaw translates 4 KiB mappings through an in-memory reader" {
    const cfg = config4();
    const raw = linear4();
    const slots = [_]Slot{
        .{ .address = entryAddress(0x1000, 1), .entry = try tableEntry(0x2000, user_table_flags) },
        .{ .address = entryAddress(0x2000, 2), .entry = try tableEntry(0x3000, user_table_flags) },
        .{ .address = entryAddress(0x3000, 3), .entry = try tableEntry(0x4000, user_table_flags) },
        .{ .address = entryAddress(0x4000, 4), .entry = try leaf4kEntry(0x9000, user_leaf_flags) },
    };

    const mapping = try expectMapped(try runWalk(cfg, &slots, try rootAt(0x1000), raw, paging.walk.Access.read(.user)));
    try testing.expectEqual(@as(u64, 0x905a), mapping.physical.raw());
    try testing.expectEqual(paging.Level.pt, mapping.leaf.level);
    try testing.expect(mapping.attributes.writable);
    try testing.expect(mapping.attributes.user);
    try testing.expect(mapping.attributes.executable);
}

test "unit: Walker.walkRaw translates 2 MiB mappings with the linear offset preserved" {
    const cfg = config4();
    const raw = linear4();
    const slots = [_]Slot{
        .{ .address = entryAddress(0x1000, 1), .entry = try tableEntry(0x2000, user_table_flags) },
        .{ .address = entryAddress(0x2000, 2), .entry = try tableEntry(0x3000, user_table_flags) },
        .{ .address = entryAddress(0x3000, 3), .entry = try leaf2mEntry(0x0040_0000, user_leaf_flags) },
    };

    const mapping = try expectMapped(try runWalk(cfg, &slots, try rootAt(0x1000), raw, paging.walk.Access.read(.user)));
    try testing.expectEqual(@as(u64, 0x0040_0000 + (4 << 12) + 0x05a), mapping.physical.raw());
    try testing.expectEqual(paging.Level.pd, mapping.leaf.level);
}

test "unit: Walker.walkRaw translates 1 GiB mappings when supported" {
    const cfg = config4();
    const raw = linear4();
    const slots = [_]Slot{
        .{ .address = entryAddress(0x1000, 1), .entry = try tableEntry(0x2000, user_table_flags) },
        .{ .address = entryAddress(0x2000, 2), .entry = try leaf1gEntry(0x4000_0000, user_leaf_flags) },
    };

    const mapping = try expectMapped(try runWalk(cfg, &slots, try rootAt(0x1000), raw, paging.walk.Access.read(.user)));
    try testing.expectEqual(@as(u64, 0x4000_0000 + (3 << 21) + (4 << 12) + 0x05a), mapping.physical.raw());
    try testing.expectEqual(paging.Level.pdpt, mapping.leaf.level);
}

test "unit: Walker.walkRaw returns NonCanonical before reading memory" {
    const cfg = config4();
    const slots = [_]Slot{};
    try testing.expectError(
        error.NonCanonical,
        runWalk(cfg, &slots, try rootAt(0x1000), 0x0000_8000_0000_0000, paging.walk.Access.read(.supervisor)),
    );
}

test "unit: Walker.walkRaw reports not-present faults at each paging level" {
    const raw4 = linear4();
    const table_entry = try tableEntry(0x2000, user_table_flags);
    const table_entry_2 = try tableEntry(0x3000, user_table_flags);
    const table_entry_3 = try tableEntry(0x4000, user_table_flags);

    const pml4_missing = [_]Slot{
        .{ .address = entryAddress(0x1000, 1), .entry = paging.Entry.empty() },
    };
    const pml4_result = try runWalk(config4(), &pml4_missing, try rootAt(0x1000), raw4, paging.walk.Access.read(.user));
    const pml4_fault = try expectFault(pml4_result);
    try testing.expectEqual(paging.walk.Fault.Reason.not_present, pml4_fault.reason);
    try testing.expectEqual(paging.Level.pml4, pml4_fault.step.level);
    try testing.expect(!pml4_fault.code.present);

    const pdpt_missing = [_]Slot{
        .{ .address = entryAddress(0x1000, 1), .entry = table_entry },
        .{ .address = entryAddress(0x2000, 2), .entry = paging.Entry.empty() },
    };
    const pdpt_result = try runWalk(config4(), &pdpt_missing, try rootAt(0x1000), raw4, paging.walk.Access.read(.user));
    const pdpt_fault = try expectFault(pdpt_result);
    try testing.expectEqual(paging.walk.Fault.Reason.not_present, pdpt_fault.reason);
    try testing.expectEqual(paging.Level.pdpt, pdpt_fault.step.level);

    const pd_missing = [_]Slot{
        .{ .address = entryAddress(0x1000, 1), .entry = table_entry },
        .{ .address = entryAddress(0x2000, 2), .entry = table_entry_2 },
        .{ .address = entryAddress(0x3000, 3), .entry = paging.Entry.empty() },
    };
    const pd_result = try runWalk(config4(), &pd_missing, try rootAt(0x1000), raw4, paging.walk.Access.read(.user));
    const pd_fault = try expectFault(pd_result);
    try testing.expectEqual(paging.walk.Fault.Reason.not_present, pd_fault.reason);
    try testing.expectEqual(paging.Level.pd, pd_fault.step.level);

    const pt_missing = [_]Slot{
        .{ .address = entryAddress(0x1000, 1), .entry = table_entry },
        .{ .address = entryAddress(0x2000, 2), .entry = table_entry_2 },
        .{ .address = entryAddress(0x3000, 3), .entry = table_entry_3 },
        .{ .address = entryAddress(0x4000, 4), .entry = paging.Entry.empty() },
    };
    const pt_result = try runWalk(config4(), &pt_missing, try rootAt(0x1000), raw4, paging.walk.Access.read(.user));
    const pt_fault = try expectFault(pt_result);
    try testing.expectEqual(paging.walk.Fault.Reason.not_present, pt_fault.reason);
    try testing.expectEqual(paging.Level.pt, pt_fault.step.level);

    const raw5 = linear5();
    const cfg5 = config(.level5, 52, full_features);
    const pml5_missing = [_]Slot{
        .{ .address = entryAddress(0x5000, 5), .entry = paging.Entry.empty() },
    };
    const pml5_result = try runWalk(cfg5, &pml5_missing, try rootAt(0x5000), raw5, paging.walk.Access.read(.user));
    const pml5_fault = try expectFault(pml5_result);
    try testing.expectEqual(paging.walk.Fault.Reason.not_present, pml5_fault.reason);
    try testing.expectEqual(paging.Level.pml5, pml5_fault.step.level);
}

test "unit: Walker.walkRaw returns reserved-bit faults before using a bad entry as a table" {
    const cfg = config4();
    const raw = linear4();
    const slots = [_]Slot{
        .{ .address = entryAddress(0x1000, 1), .entry = paging.Entry.fromRaw((1 << 7) | 1) },
    };

    const fault = try expectFault(try runWalk(cfg, &slots, try rootAt(0x1000), raw, paging.walk.Access.read(.user)));
    try testing.expectEqual(paging.walk.Fault.Reason.reserved_bits, fault.reason);
    try testing.expectEqual(paging.Level.pml4, fault.step.level);
    try testing.expect(fault.code.present);
    try testing.expect(fault.code.reserved);
}

test "unit: Walker.walkRaw reports write faults for read-only effective mappings" {
    const cfg = config4();
    const raw = linear4();
    const slots = [_]Slot{
        .{ .address = entryAddress(0x1000, 1), .entry = try tableEntry(0x2000, readonly_user_table_flags) },
        .{ .address = entryAddress(0x2000, 2), .entry = try tableEntry(0x3000, user_table_flags) },
        .{ .address = entryAddress(0x3000, 3), .entry = try tableEntry(0x4000, user_table_flags) },
        .{ .address = entryAddress(0x4000, 4), .entry = try leaf4kEntry(0x9000, user_leaf_flags) },
    };

    const fault = try expectFault(try runWalk(cfg, &slots, try rootAt(0x1000), raw, paging.walk.Access.write(.user)));
    try testing.expectEqual(paging.walk.Fault.Reason.write_to_read_only, fault.reason);
    try testing.expect(fault.code.present);
    try testing.expect(fault.code.write);
    try testing.expect(fault.code.user);
}

test "unit: Walker.walkRaw reports user faults for supervisor-only effective mappings" {
    const cfg = config4();
    const raw = linear4();
    const slots = [_]Slot{
        .{ .address = entryAddress(0x1000, 1), .entry = try tableEntry(0x2000, supervisor_table_flags) },
        .{ .address = entryAddress(0x2000, 2), .entry = try tableEntry(0x3000, user_table_flags) },
        .{ .address = entryAddress(0x3000, 3), .entry = try tableEntry(0x4000, user_table_flags) },
        .{ .address = entryAddress(0x4000, 4), .entry = try leaf4kEntry(0x9000, user_leaf_flags) },
    };

    const fault = try expectFault(try runWalk(cfg, &slots, try rootAt(0x1000), raw, paging.walk.Access.read(.user)));
    try testing.expectEqual(paging.walk.Fault.Reason.user_to_supervisor, fault.reason);
    try testing.expect(fault.code.present);
    try testing.expect(fault.code.user);
}

test "unit: Walker.walkRaw reports execute faults for NX effective mappings" {
    const cfg = config4();
    const raw = linear4();
    const slots = [_]Slot{
        .{ .address = entryAddress(0x1000, 1), .entry = try tableEntry(0x2000, user_table_flags) },
        .{ .address = entryAddress(0x2000, 2), .entry = try tableEntry(0x3000, user_table_flags) },
        .{ .address = entryAddress(0x3000, 3), .entry = try tableEntry(0x4000, user_table_flags) },
        .{ .address = entryAddress(0x4000, 4), .entry = try leaf4kEntry(0x9000, nx_user_leaf_flags) },
    };

    const result = try runWalk(cfg, &slots, try rootAt(0x1000), raw, paging.walk.Access.execute(.supervisor));
    const fault = try expectFault(result);
    try testing.expectEqual(paging.walk.Fault.Reason.execute_disabled, fault.reason);
    try testing.expect(fault.code.present);
    try testing.expect(fault.code.instruction_fetch);
}

test "unit: Walker.walkRaw honors disabled supervisor write protection" {
    const cfg = config(.level4, 52, no_write_protect_features);
    const raw = linear4();
    const slots = [_]Slot{
        .{ .address = entryAddress(0x1000, 1), .entry = try tableEntry(0x2000, readonly_user_table_flags) },
        .{ .address = entryAddress(0x2000, 2), .entry = try tableEntry(0x3000, readonly_user_table_flags) },
        .{ .address = entryAddress(0x3000, 3), .entry = try tableEntry(0x4000, readonly_user_table_flags) },
        .{ .address = entryAddress(0x4000, 4), .entry = try leaf4kEntry(0x9000, readonly_user_leaf_flags) },
    };

    const result = try runWalk(cfg, &slots, try rootAt(0x1000), raw, paging.walk.Access.write(.supervisor));
    const mapping = try expectMapped(result);
    try testing.expectEqual(@as(u64, 0x905a), mapping.physical.raw());
    try testing.expect(!mapping.attributes.writable);
}

test "unit: Walker.walkRaw propagates reader errors as Zig errors" {
    const cfg = config4();
    const slots = [_]Slot{};
    try testing.expectError(
        error.MissingEntry,
        runWalk(cfg, &slots, try rootAt(0x1000), linear4(), paging.walk.Access.read(.user)),
    );
}

comptime {
    _ = paging.Mode;
    _ = paging.Level;
    _ = paging.Index;
    _ = paging.Indices;
    _ = paging.LinearAddr;
    _ = paging.PhysAddr;
    _ = paging.Phys4K;
    _ = paging.Phys2M;
    _ = paging.Phys1G;
    _ = paging.Root;
    _ = paging.Entry;
    _ = paging.table.Pml5;
    _ = paging.table.Pml4;
    _ = paging.table.Pdpt;
    _ = paging.table.Pd;
    _ = paging.table.Pt;
    _ = paging.leaf.Frame;
    _ = paging.leaf.Mapping;
    _ = paging.walk.Access;
    _ = paging.walk.Mapping;
    _ = paging.walk.Fault;
    _ = paging.Walker(MemoryReader);
}
