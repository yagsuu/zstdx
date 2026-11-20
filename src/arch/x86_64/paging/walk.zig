const std = @import("std");

const cpuid = @import("../cpuid.zig");
const registers = @import("../registers.zig");
const address = @import("address.zig");
const table = @import("table.zig");

const Mode = address.Mode;
const LinearAddr = address.LinearAddr;
const PhysAddr = address.PhysAddr;
const Phys4K = address.Phys4K;
const PhysWidth = table.PhysWidth;
const Level = table.Level;
const Index = table.Index;

pub const Access = struct {
    operation: Operation,
    privilege: Privilege,

    pub const Operation = enum { read, write, execute };
    pub const Privilege = enum { supervisor, user };

    pub fn read(privilege: Privilege) Access {
        return .{ .operation = .read, .privilege = privilege };
    }

    pub fn write(privilege: Privilege) Access {
        return .{ .operation = .write, .privilege = privilege };
    }

    pub fn execute(privilege: Privilege) Access {
        return .{ .operation = .execute, .privilege = privilege };
    }
};

pub const Permissions = struct {
    writable: bool = true,
    user: bool = true,
    executable: bool = true,

    fn intersect(self: *Permissions, entry: table.Entry) void {
        self.writable = self.writable and entry.writable;
        self.user = self.user and entry.user;
        self.executable = self.executable and !entry.no_execute;
    }

    fn fault(self: Permissions, access: Access, write_protect: bool) ?Fault.Reason {
        if (access.privilege == .user and !self.user) {
            return .user_to_supervisor;
        }

        if (access.operation == .write and !self.writable) {
            if (access.privilege == .user or write_protect) {
                return .write_to_read_only;
            }
        }

        if (access.operation == .execute and !self.executable) {
            return .execute_disabled;
        }

        return null;
    }
};

pub const Step = struct {
    level: Level,
    index: Index,
    address: PhysAddr,
    entry: table.Entry,
};

pub const Mapping = struct {
    linear: LinearAddr,
    physical: PhysAddr,
    frame: table.PageFrame,
    attributes: table.PageAttributes,
    permissions: Permissions,
    step: Step,

    fn init(linear: LinearAddr, leaf: table.Leaf, permissions: Permissions, step: Step) Mapping {
        std.debug.assert(leaf.frame.level() == step.level);
        std.debug.assert(step.entry.present);
        return .{
            .linear = linear,
            .physical = PhysAddr.from(leaf.frame.addressInt() | (linear.raw() & leaf.frame.offsetMask())),
            .frame = leaf.frame,
            .attributes = leaf.attributes,
            .permissions = permissions,
            .step = step,
        };
    }
};

pub const Fault = struct {
    reason: Reason,
    code: Code,
    step: Step,

    pub const Reason = enum {
        not_present,
        reserved_bits,
        write_to_read_only,
        user_to_supervisor,
        execute_disabled,
    };

    pub const Code = packed struct(u16) {
        present: bool,
        write: bool,
        user: bool,
        reserved: bool,
        instruction_fetch: bool,
        _reserved_5_15: u11 = 0,
    };

    fn init(reason: Reason, access: Access, nxe: bool, step: Step) Fault {
        std.debug.assert(step.entry.present == (reason != .not_present));
        return .{
            .reason = reason,
            .code = .{
                .present = reason != .not_present,
                .write = access.operation == .write,
                .user = access.privilege == .user,
                .reserved = reason == .reserved_bits,
                // instruction-fetch faults require NXE when SMEP is disabled.
                .instruction_fetch = nxe and access.operation == .execute,
            },
            .step = step,
        };
    }
};

pub const Result = union(enum) {
    mapped: Mapping,
    fault: Fault,
};

pub fn Walker(comptime Reader: type) type {
    return struct {
        root: Phys4K.Base,
        mode: Mode,
        physical_width: PhysWidth,
        allow_1gib: bool,
        write_protect: bool,
        nxe: bool,
        reader: *Reader,

        pub const Config = Impl.Config;
        pub const InitError = Impl.InitError;
        pub const TranslateError = Reader.Error || error{NonCanonical};
        pub const CaptureError = Impl.CaptureError;

        const Self = @This();

        pub fn init(config: Config, reader: *Reader) InitError!Self {
            return .{
                .root = try Impl.rootBase(config.root, config.physical_width),
                .mode = config.mode,
                .physical_width = config.physical_width,
                .allow_1gib = config.allow_1gib,
                .write_protect = config.write_protect,
                .nxe = config.nxe,
                .reader = reader,
            };
        }

        /// capture paging state at CPL 0; the register reads do not form an atomic snapshot.
        pub fn initCurrent(reader: *Reader) CaptureError!Self {
            const sizes = cpuid.addressSizes();
            const features = cpuid.features();
            const cr0 = registers.CR0.read();
            const cr3 = registers.CR3.read();
            const cr4 = registers.CR4.read();
            const efer = registers.EFER.read();

            if (!cr0.protection_enable or !cr0.paging) {
                return error.InvalidPagingState;
            }

            if (!cr4.physical_address_extension) {
                return error.InvalidPagingState;
            }

            if (!efer.long_mode_enable or !efer.long_mode_active) {
                return error.InvalidPagingState;
            }

            try Impl.requireSupportedControls(cr3, cr4);

            const physical_width = try PhysWidth.from(sizes.physical_bits);
            const level5 = try registers.CR4.level5Enabled(cr4, features.structured.ecx.la57);
            const mode: Mode = if (level5) .level5 else .level4;

            if (sizes.linear_bits < mode.linearBits()) {
                return error.InvalidLinearWidth;
            }

            const pcid = try registers.CR4.pcidEnabled(cr4, features.basic.ecx.pcid);
            _ = try registers.CR3.low(cr3, pcid);

            if (cr3.no_flush and !pcid) {
                return error.InvalidNoFlush;
            }

            const root = registers.CR3.base(cr3, physical_width.bits()) catch |err| {
                return switch (err) {
                    error.InvalidPhysicalAddressWidth => unreachable,
                    error.PhysicalAddressTooWide => error.PhysicalAddressTooWide,
                    error.ReservedBits => error.ReservedBits,
                };
            };

            return Self.init(.{
                .root = root,
                .mode = mode,
                .physical_width = physical_width,
                .allow_1gib = features.extended.edx.pdpe1gb,
                .write_protect = cr0.write_protect,
                .nxe = try registers.EFER.executeDisableEnabled(efer, features.extended.edx.nx),
            }, reader);
        }

        pub fn setRoot(self: *Self, root: PhysAddr) InitError!void {
            self.root = try Impl.rootBase(root, self.physical_width);
        }

        pub fn translate(self: *const Self, linear: LinearAddr, access: Access) TranslateError!Result {
            return Impl.translate(self, linear, access);
        }
    };
}

const Impl = struct {
    const Config = struct {
        root: PhysAddr,
        mode: Mode,
        physical_width: PhysWidth,
        allow_1gib: bool = false,
        write_protect: bool = false,
        nxe: bool = false,
    };

    const InitError = error{ Misaligned, PhysicalAddressTooWide };
    const ControlError = error{
        UnsupportedSMEP,
        UnsupportedSMAP,
        UnsupportedPKE,
        UnsupportedPKS,
        UnsupportedLAM,
    };

    const CaptureError = InitError ||
        ControlError ||
        PhysWidth.Error ||
        registers.CR3.LowError ||
        registers.CR4.PcidError ||
        registers.CR4.Level5Error ||
        registers.EFER.Error || error{
        InvalidLinearWidth,
        InvalidNoFlush,
        InvalidPagingState,
        ReservedBits,
    };

    fn translate(walker: anytype, linear: LinearAddr, access: Access) @TypeOf(walker.*).TranslateError!Result {
        if (!linear.isCanonical(walker.mode)) {
            return error.NonCanonical;
        }

        var node = table.Node{ .base = walker.root, .level = walker.mode.rootLevel() };
        var permissions = Permissions{};

        const config = table.DecodeConfig{
            .physical_width = walker.physical_width,
            .allow_1gib = walker.allow_1gib,
            .nxe = walker.nxe,
        };

        while (true) {
            const index = linear.index(node.level);
            const addr = node.entryAddress(index);
            const entry = try walker.reader.readEntry(addr);

            const step = Step{
                .level = node.level,
                .index = index,
                .address = addr,
                .entry = entry,
            };

            switch (entry.decode(node.level, config)) {
                .absent => {
                    return .{ .fault = Fault.init(.not_present, access, walker.nxe, step) };
                },
                .reserved => {
                    return .{ .fault = Fault.init(.reserved_bits, access, walker.nxe, step) };
                },
                .table => |child| {
                    permissions.intersect(entry);
                    node = child;
                    continue;
                },
                .page => |leaf| {
                    permissions.intersect(entry);

                    if (permissions.fault(access, walker.write_protect)) |reason| {
                        return .{ .fault = Fault.init(reason, access, walker.nxe, step) };
                    }

                    return .{ .mapped = Mapping.init(linear, leaf, permissions, step) };
                },
            }
        }
    }

    fn rootBase(root: PhysAddr, width: PhysWidth) InitError!Phys4K.Base {
        const base = Phys4K.Base.from(root) catch |err| {
            return switch (err) {
                error.Misaligned => error.Misaligned,
                error.OutOfBounds, error.Overflow => unreachable,
            };
        };

        try width.checkAddress(root.raw());
        return base;
    }

    fn requireSupportedControls(cr3: registers.CR3.Word, cr4: registers.CR4.Word) ControlError!void {
        if (cr4.smep) {
            return error.UnsupportedSMEP;
        }

        if (cr4.smap) {
            return error.UnsupportedSMAP;
        }

        if (cr4.pke) {
            return error.UnsupportedPKE;
        }

        // the CR4 type has no named field for PKS, bit 24.
        if (registers.CR4.raw(cr4) & (@as(u64, 1) << 24) != 0) {
            return error.UnsupportedPKS;
        }

        if (cr3.lam_u48 or cr3.lam_u57) {
            return error.UnsupportedLAM;
        }

        if (cr4.lam_supervisor) {
            return error.UnsupportedLAM;
        }
    }
};

pub const unit = struct {
    const testing = std.testing;

    const TranslationCase = struct {
        mode: Mode,
        leaf: Level,
        frame: u64,
        reads: usize,
    };

    const FaultCase = struct {
        slot: usize,
        raw: u64,
        nxe: bool,
        reason: Fault.Reason,
    };

    const Storage = struct {
        pml5: table.PML5.Storage = .init(),
        pml4: table.PML4.Storage = .init(),
        pdpt: table.PDPT.Storage = .init(),
        pd: table.PD.Storage = .init(),
        pt: table.PT.Storage = .init(),
    };

    const StorageReader = struct {
        storage: *const Storage,
        reads: usize = 0,

        pub const Error = error{UnmappedTable};

        pub fn readEntry(self: *StorageReader, entry_address: PhysAddr) Error!table.Entry {
            const raw = entry_address.raw();
            const index = Index.from(@intCast((raw & 0xfff) / 8));

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

    const Fixture = struct {
        entries: [5]table.Entry = undefined,
        addresses: [5]PhysAddr = undefined,
        count: usize = 0,
        calls: usize = 0,
        fail_at: ?usize = null,

        const Error = error{ Unavailable, UnexpectedRead };

        fn init(mode: Mode, leaf: Level) Fixture {
            var fixture = Fixture{};
            var level = mode.rootLevel();

            while (true) {
                const slot = fixture.count;
                const base = @as(u64, @intCast(slot + 1)) << 12;
                const index = testLinear(mode).index(level);

                fixture.addresses[slot] = .from(base + @as(u64, index.raw()) * @sizeOf(table.Entry));

                const target: u64 = if (level == leaf) 0x4000_0000 else base + 0x1000;
                fixture.entries[slot] = .from(target | 7);

                if (level == leaf and leaf != .pt) {
                    fixture.entries[slot].page_size_or_pat = true;
                }

                fixture.count += 1;
                if (level == leaf) {
                    break;
                }

                level = level.child().?;
            }

            return fixture;
        }

        fn readEntry(self: *Fixture, entry_address: PhysAddr) Error!table.Entry {
            const slot = self.calls;
            self.calls += 1;

            if (self.fail_at == slot) {
                return error.Unavailable;
            }

            if (slot >= self.count or self.addresses[slot] != entry_address) {
                return error.UnexpectedRead;
            }

            return self.entries[slot];
        }
    };

    fn testLinear(mode: Mode) LinearAddr {
        const low: u64 = (@as(u64, 1) << 39) | (@as(u64, 2) << 30) | (@as(u64, 3) << 21) |
            (@as(u64, 4) << 12) | 0xabc;

        return .from(low | (if (mode == .level5) @as(u64, 5) << 48 else 0));
    }

    fn testWalker(fixture: *Fixture, mode: Mode) Walker(Fixture).InitError!Walker(Fixture) {
        return Walker(Fixture).init(.{
            .root = .from(0x1000),
            .mode = mode,
            .physical_width = .bits_48,
            .allow_1gib = true,
            .nxe = true,
        }, fixture);
    }

    test "unit: radix paths preserve page offsets at both depths" {
        for ([_]Mode{ .level4, .level5 }) |mode| {
            for ([_]Level{ .pt, .pd, .pdpt }) |leaf| {
                var fixture = Fixture.init(mode, leaf);
                fixture.fail_at = fixture.count;
                const walker = try testWalker(&fixture, mode);
                const result = try Impl.translate(&walker, testLinear(mode), .read(.user));

                const physical = @as(u64, 0x4000_0000) | (testLinear(mode).raw() & leaf.offsetMask().?);
                try testing.expectEqual(physical, result.mapped.physical.raw());
                try testing.expectEqual(leaf, result.mapped.frame.level());
                try testing.expectEqual(fixture.count, fixture.calls);
                try testing.expectEqual(fixture.addresses[fixture.count - 1], result.mapped.step.address);
            }
        }
    }

    test "unit: permissions accumulate with user write and execute precedence" {
        var fixture = Fixture.init(.level5, .pt);
        fixture.entries[0].writable = false;
        fixture.entries[2].user = false;
        fixture.entries[3].no_execute = true;
        var walker = try testWalker(&fixture, .level5);
        const inspected = (try Impl.translate(&walker, testLinear(.level5), .read(.supervisor))).mapped;

        try testing.expectEqual(Permissions{
            .writable = false,
            .user = false,
            .executable = false,
        }, inspected.permissions);

        fixture.calls = 0;
        const user_write = try Impl.translate(&walker, testLinear(.level5), .write(.user));

        try testing.expectEqual(Fault.Reason.user_to_supervisor, user_write.fault.reason);

        fixture.calls = 0;
        const execute = try Impl.translate(&walker, testLinear(.level5), .execute(.supervisor));

        try testing.expectEqual(Fault.Reason.execute_disabled, execute.fault.reason);

        fixture.calls = 0;
        _ = (try Impl.translate(&walker, testLinear(.level5), .write(.supervisor))).mapped;

        walker.write_protect = true;
        fixture.calls = 0;
        const supervisor_write = try Impl.translate(&walker, testLinear(.level5), .write(.supervisor));

        try testing.expectEqual(Fault.Reason.write_to_read_only, supervisor_write.fault.reason);

        for (0..5) |slot| {
            fixture = Fixture.init(.level5, .pt);
            fixture.entries[slot].writable = false;
            const result = try Impl.translate(&walker, testLinear(.level5), .write(.user));

            try testing.expectEqual(Fault.Reason.write_to_read_only, result.fault.reason);
            try testing.expectEqual(@as(usize, 5), fixture.calls);
        }
    }

    test "unit: absence and reserved encodings stop reads and preserve fault codes" {
        const cases = [_]FaultCase{
            .{ .slot = 0, .raw = 0x8000_0000_0000_0080, .nxe = false, .reason = .not_present },
            .{ .slot = 0, .raw = 0x2087, .nxe = true, .reason = .reserved_bits },
            .{ .slot = 1, .raw = 0x8000_0000_0000_3007, .nxe = false, .reason = .reserved_bits },
            .{ .slot = 2, .raw = 0x4000_2087, .nxe = true, .reason = .reserved_bits },
        };

        for (cases) |case| {
            var fixture = Fixture.init(.level4, .pt);
            fixture.entries[0].user = false;
            fixture.entries[case.slot] = .from(case.raw);
            fixture.fail_at = case.slot + 1;

            var walker = try testWalker(&fixture, .level4);
            walker.nxe = case.nxe;

            const fault = (try Impl.translate(&walker, testLinear(.level4), .execute(.user))).fault;

            try testing.expectEqual(case.reason, fault.reason);
            try testing.expectEqual(case.slot + 1, fixture.calls);
            try testing.expectEqual(case.reason != .not_present, fault.code.present);
            try testing.expectEqual(case.reason == .reserved_bits, fault.code.reserved);
            try testing.expectEqual(case.nxe, fault.code.instruction_fetch);
            try testing.expect(fault.code.user);
            try testing.expect(!fault.code.write);
        }
    }

    test "unit: translation errors do not become paging faults" {
        var fixture = Fixture.init(.level5, .pt);
        const walker = try testWalker(&fixture, .level5);

        try testing.expectError(error.NonCanonical, walker.translate(.from(@as(u64, 1) << 57), .read(.supervisor)));
        try testing.expectEqual(@as(usize, 0), fixture.calls);

        for ([_]usize{ 0, 4 }) |slot| {
            fixture.calls = 0;
            fixture.fail_at = slot;

            try testing.expectError(
                error.Unavailable,
                Impl.translate(&walker, testLinear(.level5), .read(.supervisor)),
            );

            try testing.expectEqual(slot + 1, fixture.calls);
        }
    }

    test "unit: root validation accepts every supported width transactionally" {
        var fixture = Fixture.init(.level4, .pt);
        var walker = try testWalker(&fixture, .level4);
        const before = walker.root;

        try testing.expectError(error.Misaligned, walker.setRoot(.from(3)));
        try testing.expectEqual(before, walker.root);
        try testing.expectError(error.PhysicalAddressTooWide, walker.setRoot(.from(@as(u64, 1) << 48)));
        try testing.expectEqual(before, walker.root);

        try walker.setRoot(.from(0x9000));
        try testing.expectEqual(@as(u64, 0x9000), walker.root.raw());

        for (32..53) |bits| {
            const width = try PhysWidth.from(@intCast(bits));
            const limit = @as(u64, 1) << @intCast(bits);

            _ = try Impl.rootBase(.from(limit - 0x1000), width);
            try testing.expectError(error.PhysicalAddressTooWide, Impl.rootBase(.from(limit), width));
        }
    }

    test "unit: capture rejects unsupported permission and address controls" {
        const cases = .{
            .{ @as(u6, 20), error.UnsupportedSMEP },
            .{ @as(u6, 21), error.UnsupportedSMAP },
            .{ @as(u6, 22), error.UnsupportedPKE },
            .{ @as(u6, 24), error.UnsupportedPKS },
            .{ @as(u6, 28), error.UnsupportedLAM },
        };

        inline for (cases) |case| {
            const cr4 = registers.CR4.from(@as(u64, 1) << case[0]);
            try testing.expectError(case[1], Impl.requireSupportedControls(registers.CR3.from(0), cr4));
        }

        for ([_]u6{ 61, 62 }) |bit| {
            const cr3 = registers.CR3.from(@as(u64, 1) << bit);
            try testing.expectError(error.UnsupportedLAM, Impl.requireSupportedControls(cr3, registers.CR4.from(0)));
        }

        try Impl.requireSupportedControls(registers.CR3.from(0), registers.CR4.from(0));

        comptime {
            _ = &Walker(Fixture).initCurrent;
        }
    }

    test "unit: typed caller storage translates every leaf size without mutation" {
        const cases = [_]TranslationCase{
            .{ .mode = .level4, .leaf = .pt, .frame = 0x8000, .reads = 4 },
            .{ .mode = .level5, .leaf = .pt, .frame = 0x8000, .reads = 5 },
            .{ .mode = .level4, .leaf = .pd, .frame = 0x20_0000, .reads = 3 },
            .{ .mode = .level4, .leaf = .pdpt, .frame = 0x4000_0000, .reads = 2 },
        };

        const raw_linear = (@as(u64, 5) << 48) |
            (@as(u64, 1) << 39) |
            (@as(u64, 2) << 30) |
            (@as(u64, 3) << 21) |
            (@as(u64, 4) << 12) |
            0xabc;

        const page_flags = table.PageFlags{
            .user = true,
            .pat = true,
            .global = true,
            .available_low = 0b101,
            .available_high = 0x155,
        };

        for (cases) |case| {
            var storage = Storage{};

            const leaf_payload = try populateStorage(&storage, case.leaf, case.frame, page_flags);
            const before = storage;

            var reader = StorageReader{ .storage = &storage };
            const walker = try Walker(StorageReader).init(.{
                .root = .from(if (case.mode == .level5) 0x1000 else 0x2000),
                .mode = case.mode,
                .physical_width = .bits_48,
                .allow_1gib = true,
                .write_protect = true,
            }, &reader);

            const linear = try LinearAddr.fromCanonical(
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

    fn populateStorage(storage: *Storage, leaf: Level, frame: u64, page_flags: table.PageFlags) !u64 {
        const pml4 = try table.PML4.init(try Phys4K.Base.fromInt(0x2000));
        const pdpt = try table.PDPT.init(try Phys4K.Base.fromInt(0x3000));
        const pd = try table.PD.init(try Phys4K.Base.fromInt(0x4000));
        const pt = try table.PT.init(try Phys4K.Base.fromInt(0x5000));
        const table_flags = table.TableFlags{ .writable = true, .user = true };

        storage.pml5.set(.from(5), table.PML5.tableEntry(pml4, table_flags));
        storage.pml4.set(.from(1), table.PML4.tableEntry(pdpt, table_flags));
        storage.pdpt.set(.from(2), table.PDPT.tableEntry(pd, table_flags));
        storage.pd.set(.from(3), table.PD.tableEntry(pt, table_flags));

        return switch (leaf) {
            .pt => blk: {
                const entry = try table.PT.pageEntry(try Phys4K.Base.fromInt(frame), page_flags);
                storage.pt.set(.from(4), entry);
                break :blk entry.raw();
            },
            .pd => blk: {
                const entry = try table.PD.pageEntry(try address.Phys2M.Base.fromInt(frame), page_flags);
                storage.pd.set(.from(3), entry);
                break :blk entry.raw();
            },
            .pdpt => blk: {
                const entry = try table.PDPT.pageEntry(try address.Phys1G.Base.fromInt(frame), page_flags);
                storage.pdpt.set(.from(2), entry);
                break :blk entry.raw();
            },
            else => unreachable,
        };
    }
};
