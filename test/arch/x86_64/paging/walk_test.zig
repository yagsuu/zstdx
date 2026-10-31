const std = @import("std");
const paging = @import("stdx").arch.x86_64.paging;

const testing = std.testing;

const Storage = struct {
    pml5: paging.PML5.Storage = .init(),
    pml4: paging.PML4.Storage = .init(),
    pdpt: paging.PDPT.Storage = .init(),
    pd: paging.PD.Storage = .init(),
    pt: paging.PT.Storage = .init(),
};

const StorageReader = struct {
    storage: *const Storage,
    reads: usize = 0,

    pub const Error = error{UnmappedTable};

    pub fn readEntry(self: *StorageReader, address: paging.PhysAddr) Error!paging.Entry {
        const raw = address.raw();
        const index = paging.Index.from(@intCast((raw & 0xfff) / 8));
        const payload = switch (raw & ~@as(u64, 0xfff)) {
            0x1000 => self.storage.pml5.get(index).raw(),
            0x2000 => self.storage.pml4.get(index).raw(),
            0x3000 => self.storage.pdpt.get(index).raw(),
            0x4000 => self.storage.pd.get(index).raw(),
            0x5000 => self.storage.pt.get(index).raw(),
            else => return error.UnmappedTable,
        };
        self.reads += 1;
        return .from(payload);
    }
};

test "integration: typed caller storage translates all leaf sizes without mutation" {
    const cases = [_]struct {
        mode: paging.Mode = .level4,
        leaf: paging.Level,
        frame: u64,
        reads: usize,
    }{
        .{ .leaf = .pt, .frame = 0x8000, .reads = 4 },
        .{ .mode = .level5, .leaf = .pt, .frame = 0x8000, .reads = 5 },
        .{ .leaf = .pd, .frame = 0x20_0000, .reads = 3 },
        .{ .leaf = .pdpt, .frame = 0x4000_0000, .reads = 2 },
    };
    const raw_linear = (@as(u64, 5) << 48) |
        (@as(u64, 1) << 39) |
        (@as(u64, 2) << 30) |
        (@as(u64, 3) << 21) |
        (@as(u64, 4) << 12) |
        0xabc;
    const page_flags = paging.PageFlags{
        .user = true,
        .pat = true,
        .global = true,
        .available_low = 0b101,
        .available_high = 0x155,
    };

    for (cases) |case| {
        var storage = Storage{};
        const pml4 = try paging.PML4.init(try paging.Phys4K.Base.fromInt(0x2000));
        const pdpt = try paging.PDPT.init(try paging.Phys4K.Base.fromInt(0x3000));
        const pd = try paging.PD.init(try paging.Phys4K.Base.fromInt(0x4000));
        const pt = try paging.PT.init(try paging.Phys4K.Base.fromInt(0x5000));
        const table_flags = paging.TableFlags{ .writable = true, .user = true };
        storage.pml5.set(.from(5), paging.PML5.tableEntry(pml4, table_flags));
        storage.pml4.set(.from(1), paging.PML4.tableEntry(pdpt, table_flags));
        storage.pdpt.set(.from(2), paging.PDPT.tableEntry(pd, table_flags));
        storage.pd.set(.from(3), paging.PD.tableEntry(pt, table_flags));
        const leaf_payload = switch (case.leaf) {
            .pt => blk: {
                const entry = try paging.PT.pageEntry(try paging.Phys4K.Base.fromInt(case.frame), page_flags);
                storage.pt.set(.from(4), entry);
                break :blk entry.raw();
            },
            .pd => blk: {
                const entry = try paging.PD.pageEntry(try paging.Phys2M.Base.fromInt(case.frame), page_flags);
                storage.pd.set(.from(3), entry);
                break :blk entry.raw();
            },
            .pdpt => blk: {
                const entry = try paging.PDPT.pageEntry(try paging.Phys1G.Base.fromInt(case.frame), page_flags);
                storage.pdpt.set(.from(2), entry);
                break :blk entry.raw();
            },
            else => unreachable,
        };
        const before = storage;
        var reader = StorageReader{ .storage = &storage };
        const walker = try paging.Walker(StorageReader).init(.{
            .root = .from(if (case.mode == .level5) 0x1000 else 0x2000),
            .mode = case.mode,
            .physical_width = .bits_48,
            .allow_1gib = true,
            .write_protect = true,
        }, &reader);
        const linear = try paging.LinearAddr.fromCanonical(
            if (case.mode == .level5) raw_linear else raw_linear & ((@as(u64, 1) << 48) - 1),
            case.mode,
        );

        const result = try walker.translate(linear, .read(.user));

        const mapped = switch (result) {
            .mapped => |mapping| mapping,
            .fault => return error.ExpectedMapping,
        };
        try testing.expectEqual(case.frame + (linear.raw() & case.leaf.offsetMask().?), mapped.physical.raw());
        try testing.expectEqual(case.frame, mapped.frame.addressInt());
        try testing.expectEqual(case.leaf, mapped.frame.level());
        try testing.expectEqual(leaf_payload, mapped.step.entry.raw());
        try testing.expect(mapped.attributes.pat);
        try testing.expect(mapped.attributes.global);
        try testing.expect(!mapped.permissions.writable);
        try testing.expectEqual(case.reads, reader.reads);

        const write_result = try walker.translate(linear, .write(.user));

        switch (write_result) {
            .mapped => return error.ExpectedFault,
            .fault => |fault| try testing.expectEqual(.write_to_read_only, fault.reason),
        }
        try testing.expectEqualSlices(u8, std.mem.asBytes(&before), std.mem.asBytes(&storage));
    }
}
