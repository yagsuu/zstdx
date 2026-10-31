//! x86_64 paging geometry, structures, entries, and mapped frames.

const std = @import("std");

const addr = @import("addr");
const bits = @import("bits");

const PhysAddr = addr.PhysAddr;
const Phys4K = addr.Page(PhysAddr, addr.pages._4kib);
const Phys2M = addr.Page(PhysAddr, addr.pages._2mib);
const Phys1G = addr.Page(PhysAddr, addr.pages._1gib);

pub const PhysWidth = enum(u6) {
    bits_32 = 32,
    bits_36 = 36,
    bits_39 = 39,
    bits_40 = 40,
    bits_46 = 46,
    bits_48 = 48,
    bits_52 = 52,
    _,

    pub const Error = error{UnsupportedPhysicalAddressWidth};

    pub const min: u6 = @intFromEnum(PhysWidth.bits_32);
    pub const max: u6 = @intFromEnum(PhysWidth.bits_52);

    pub fn from(width: u8) Error!PhysWidth {
        if (width < min or width > max) {
            return error.UnsupportedPhysicalAddressWidth;
        }
        return @enumFromInt(width);
    }

    pub fn bits(self: PhysWidth) u6 {
        return @intFromEnum(self);
    }

    pub fn checkAddress(self: PhysWidth, address: u64) error{PhysicalAddressTooWide}!void {
        if (address >> self.bits() != 0) {
            return error.PhysicalAddressTooWide;
        }
    }
};

pub const Level = enum(u3) {
    pt = 1,
    pd = 2,
    pdpt = 3,
    pml4 = 4,
    pml5 = 5,

    pub fn shift(self: Level) u6 {
        return switch (self) {
            .pt => 12,
            .pd => 21,
            .pdpt => 30,
            .pml4 => 39,
            .pml5 => 48,
        };
    }

    pub fn child(self: Level) ?Level {
        return switch (self) {
            .pml5 => .pml4,
            .pml4 => .pdpt,
            .pdpt => .pd,
            .pd => .pt,
            .pt => null,
        };
    }

    pub fn offsetBits(self: Level) ?u6 {
        return switch (self) {
            .pt, .pd, .pdpt => self.shift(),
            .pml4, .pml5 => null,
        };
    }

    pub fn pageSize(self: Level) ?u64 {
        const offset_bits = self.offsetBits() orelse return null;
        return @as(u64, 1) << offset_bits;
    }

    pub fn offsetMask(self: Level) ?u64 {
        const offset_bits = self.offsetBits() orelse return null;
        return bits.mask.low(u64, offset_bits);
    }
};

pub const Index = enum(u9) {
    _,

    pub const count: usize = @as(usize, 1) << @bitSizeOf(Index);

    pub fn from(value: u9) Index {
        return @enumFromInt(value);
    }

    pub fn raw(self: Index) u9 {
        return @intFromEnum(self);
    }
};

pub const Entry = packed struct(u64) {
    present: bool = false,
    writable: bool = false,
    user: bool = false,
    write_through: bool = false,
    cache_disable: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    page_size_or_pat: bool = false,
    global_or_ignored: bool = false,
    available_low: u3 = 0,
    address_bits: u40 = 0,
    available_high: u11 = 0,
    no_execute: bool = false,

    const Self = @This();

    pub fn from(value: u64) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u64 {
        return @bitCast(self);
    }

    /// non-present entries ignore all other bits, including reserved bits.
    pub fn decode(self: Self, level: Level, config: DecodeConfig) Edge {
        if (!self.present) {
            return .absent;
        }

        const width = config.physical_width.bits();
        if (width < PhysWidth.min or width > PhysWidth.max) {
            return .reserved;
        }

        if (!config.nxe and self.no_execute) {
            return .reserved;
        }

        if (width < PhysWidth.max) {
            if (self.address_bits >> (width - 12) != 0) {
                return .reserved;
            }
        }

        if (self.page_size_or_pat) {
            switch (level) {
                .pml5, .pml4 => return .reserved,
                .pdpt => {
                    if (!config.allow_1gib) {
                        return .reserved;
                    }
                },
                .pd, .pt => {},
            }
        }

        const address = @as(u64, self.address_bits) << 12;
        switch (level) {
            .pml5, .pml4, .pdpt, .pd => {
                if (!self.page_size_or_pat) {
                    return .{ .table = .{
                        .base = Phys4K.Base.fromInt(address) catch unreachable,
                        .level = level.child().?,
                    } };
                }
            },
            .pt => {},
        }

        const offset_bits = level.offsetBits().?;
        // bit 12 is PAT for huge pages, not part of the frame address.
        const reserved_mask = bits.mask.low(u64, offset_bits) & ~bits.mask.low(u64, 13);
        if ((address & reserved_mask) != 0) {
            return .reserved;
        }

        const base = address & ~bits.mask.low(u64, offset_bits);
        return .{ .page = .{
            .frame = switch (level) {
                .pt => .{ .page4kib = Phys4K.Base.fromInt(base) catch unreachable },
                .pd => .{ .page2mib = Phys2M.Base.fromInt(base) catch unreachable },
                .pdpt => .{ .page1gib = Phys1G.Base.fromInt(base) catch unreachable },
                .pml4, .pml5 => unreachable,
            },
            .attributes = .{
                .accessed = self.accessed,
                .dirty = self.dirty,
                .global = self.global_or_ignored,
                .write_through = self.write_through,
                .cache_disable = self.cache_disable,
                .pat = if (level == .pt) self.page_size_or_pat else (self.address_bits & 1) != 0,
            },
        } };
    }

    comptime {
        std.debug.assert(@bitSizeOf(Self) == 64);
        std.debug.assert(@bitOffsetOf(Self, "present") == 0);
        std.debug.assert(@bitOffsetOf(Self, "writable") == 1);
        std.debug.assert(@bitOffsetOf(Self, "user") == 2);
        std.debug.assert(@bitOffsetOf(Self, "write_through") == 3);
        std.debug.assert(@bitOffsetOf(Self, "cache_disable") == 4);
        std.debug.assert(@bitOffsetOf(Self, "accessed") == 5);
        std.debug.assert(@bitOffsetOf(Self, "dirty") == 6);
        std.debug.assert(@bitOffsetOf(Self, "page_size_or_pat") == 7);
        std.debug.assert(@bitOffsetOf(Self, "global_or_ignored") == 8);
        std.debug.assert(@bitOffsetOf(Self, "available_low") == 9);
        std.debug.assert(@bitOffsetOf(Self, "address_bits") == 12);
        std.debug.assert(@bitOffsetOf(Self, "available_high") == 52);
        std.debug.assert(@bitOffsetOf(Self, "no_execute") == 63);
    }
};

pub const DecodeConfig = struct {
    physical_width: PhysWidth,
    allow_1gib: bool = false,
    nxe: bool = false,
};

pub const Node = struct {
    base: Phys4K.Base,
    level: Level,

    pub fn entryAddress(self: Node, index: Index) PhysAddr {
        return Impl.entryAddress(self.base, index);
    }
};

pub const Edge = union(enum) {
    absent,
    reserved,
    table: Node,
    page: Leaf,
};

pub const Leaf = struct {
    frame: PageFrame,
    attributes: PageAttributes,
};

pub const TableFlags = struct {
    writable: bool = false,
    user: bool = false,
    write_through: bool = false,
    cache_disable: bool = false,
    accessed: bool = false,
    no_execute: bool = false,
    available_low: u3 = 0,
    available_high: u11 = 0,
};

pub const PageFlags = struct {
    writable: bool = false,
    user: bool = false,
    write_through: bool = false,
    cache_disable: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    global: bool = false,
    pat: bool = false,
    no_execute: bool = false,
    available_low: u3 = 0,
    available_high: u11 = 0,
};

pub const PML5 = enum(u64) {
    _,

    pub const InitError = error{PhysicalAddressTooWide};
    pub const Entry = TypedEntry(@This());
    pub const Storage = TableStorage(PML5.Entry);

    pub fn init(frame: Phys4K.Base) InitError!PML5 {
        try PhysWidth.bits_52.checkAddress(frame.raw());
        return @enumFromInt(frame.raw());
    }

    pub fn base(self: PML5) Phys4K.Base {
        return Phys4K.Base.fromInt(@intFromEnum(self)) catch unreachable;
    }

    pub fn entryAddress(self: PML5, index: Index) PhysAddr {
        return Impl.entryAddress(self.base(), index);
    }

    pub fn tableEntry(
        child: PML4,
        flags: TableFlags,
    ) PML5.Entry {
        const raw: u64 = @bitCast(TableEntry.init(child.base(), flags));
        return @enumFromInt(raw);
    }
};

pub const PML4 = enum(u64) {
    _,

    pub const InitError = error{PhysicalAddressTooWide};
    pub const Entry = TypedEntry(@This());
    pub const Storage = TableStorage(PML4.Entry);

    pub fn init(frame: Phys4K.Base) InitError!PML4 {
        try PhysWidth.bits_52.checkAddress(frame.raw());
        return @enumFromInt(frame.raw());
    }

    pub fn base(self: PML4) Phys4K.Base {
        return Phys4K.Base.fromInt(@intFromEnum(self)) catch unreachable;
    }

    pub fn entryAddress(self: PML4, index: Index) PhysAddr {
        return Impl.entryAddress(self.base(), index);
    }

    pub fn tableEntry(
        child: PDPT,
        flags: TableFlags,
    ) PML4.Entry {
        const raw: u64 = @bitCast(TableEntry.init(child.base(), flags));
        return @enumFromInt(raw);
    }
};

pub const PDPT = enum(u64) {
    _,

    pub const InitError = error{PhysicalAddressTooWide};
    pub const PageEntryError = error{PhysicalAddressTooWide};
    pub const Entry = TypedEntry(@This());
    pub const Storage = TableStorage(PDPT.Entry);

    pub fn init(frame: Phys4K.Base) InitError!PDPT {
        try PhysWidth.bits_52.checkAddress(frame.raw());
        return @enumFromInt(frame.raw());
    }

    pub fn base(self: PDPT) Phys4K.Base {
        return Phys4K.Base.fromInt(@intFromEnum(self)) catch unreachable;
    }

    pub fn entryAddress(self: PDPT, index: Index) PhysAddr {
        return Impl.entryAddress(self.base(), index);
    }

    pub fn tableEntry(
        child: PD,
        flags: TableFlags,
    ) PDPT.Entry {
        const raw: u64 = @bitCast(TableEntry.init(child.base(), flags));
        return @enumFromInt(raw);
    }

    pub fn pageEntry(
        frame: Phys1G.Base,
        flags: PageFlags,
    ) PageEntryError!PDPT.Entry {
        try PhysWidth.bits_52.checkAddress(frame.raw());
        const raw: u64 = @bitCast(PageEntry1G.init(frame, flags));
        return @enumFromInt(raw);
    }
};

pub const PD = enum(u64) {
    _,

    pub const InitError = error{PhysicalAddressTooWide};
    pub const PageEntryError = error{PhysicalAddressTooWide};
    pub const Entry = TypedEntry(@This());
    pub const Storage = TableStorage(PD.Entry);

    pub fn init(frame: Phys4K.Base) InitError!PD {
        try PhysWidth.bits_52.checkAddress(frame.raw());
        return @enumFromInt(frame.raw());
    }

    pub fn base(self: PD) Phys4K.Base {
        return Phys4K.Base.fromInt(@intFromEnum(self)) catch unreachable;
    }

    pub fn entryAddress(self: PD, index: Index) PhysAddr {
        return Impl.entryAddress(self.base(), index);
    }

    pub fn tableEntry(
        child: PT,
        flags: TableFlags,
    ) PD.Entry {
        const raw: u64 = @bitCast(TableEntry.init(child.base(), flags));
        return @enumFromInt(raw);
    }

    pub fn pageEntry(
        frame: Phys2M.Base,
        flags: PageFlags,
    ) PageEntryError!PD.Entry {
        try PhysWidth.bits_52.checkAddress(frame.raw());
        const raw: u64 = @bitCast(PageEntry2M.init(frame, flags));
        return @enumFromInt(raw);
    }
};

pub const PT = enum(u64) {
    _,

    pub const InitError = error{PhysicalAddressTooWide};
    pub const PageEntryError = error{PhysicalAddressTooWide};
    pub const Entry = TypedEntry(@This());
    pub const Storage = TableStorage(PT.Entry);

    pub fn init(frame: Phys4K.Base) InitError!PT {
        try PhysWidth.bits_52.checkAddress(frame.raw());
        return @enumFromInt(frame.raw());
    }

    pub fn base(self: PT) Phys4K.Base {
        return Phys4K.Base.fromInt(@intFromEnum(self)) catch unreachable;
    }

    pub fn entryAddress(self: PT, index: Index) PhysAddr {
        return Impl.entryAddress(self.base(), index);
    }

    pub fn pageEntry(
        frame: Phys4K.Base,
        flags: PageFlags,
    ) PageEntryError!PT.Entry {
        try PhysWidth.bits_52.checkAddress(frame.raw());
        const raw: u64 = @bitCast(PageEntry4K.init(frame, flags));
        return @enumFromInt(raw);
    }
};

pub const PageFrame = union(enum) {
    page4kib: Phys4K.Base,
    page2mib: Phys2M.Base,
    page1gib: Phys1G.Base,

    pub fn level(self: PageFrame) Level {
        return switch (self) {
            .page4kib => .pt,
            .page2mib => .pd,
            .page1gib => .pdpt,
        };
    }

    pub fn address(self: PageFrame) PhysAddr {
        return switch (self) {
            inline else => |frame| frame.addr(),
        };
    }

    pub fn addressInt(self: PageFrame) u64 {
        return self.address().raw();
    }

    pub fn size(self: PageFrame) u64 {
        return self.level().pageSize().?;
    }

    pub fn offsetBits(self: PageFrame) u6 {
        return self.level().offsetBits().?;
    }

    pub fn offsetMask(self: PageFrame) u64 {
        return self.level().offsetMask().?;
    }
};

pub const PageAttributes = struct {
    accessed: bool,
    dirty: bool,
    global: bool,
    write_through: bool,
    cache_disable: bool,
    pat: bool,
};

fn TypedEntry(comptime Owner: type) type {
    return enum(u64) {
        _,

        const Self = @This();

        pub const TagType = Owner;
        pub const Raw = u64;
        pub const NonPresentError = error{Present};

        pub fn empty() Self {
            return @enumFromInt(0);
        }

        pub fn nonPresent(value: Raw) NonPresentError!Self {
            if ((value & 1) != 0) {
                return error.Present;
            }
            return @enumFromInt(value);
        }

        pub fn raw(self: Self) Raw {
            return @intFromEnum(self);
        }
    };
}

/// caller-owned hardware-visible storage; stores require caller-managed
/// synchronization, publication, and invalidation
fn TableStorage(comptime Item: type) type {
    return extern struct {
        entries: [Index.count]Item align(Phys4K.size),

        const Self = @This();

        pub fn init() Self {
            return .{
                .entries = [_]Item{Item.empty()} ** Index.count,
            };
        }

        pub fn get(self: *const Self, index: Index) Item {
            return self.entries[index.raw()];
        }

        pub fn set(self: *Self, index: Index, entry: Item) void {
            self.entries[index.raw()] = entry;
        }

        pub fn clear(self: *Self, index: Index) void {
            self.entries[index.raw()] = Item.empty();
        }

        comptime {
            std.debug.assert(@sizeOf(Self) == Phys4K.size);
            std.debug.assert(@alignOf(Self) == Phys4K.size);
        }
    };
}

const Impl = struct {
    fn entryAddress(base: Phys4K.Base, index: Index) PhysAddr {
        std.debug.assert(base.isValid());
        std.debug.assert(base.raw() >> PhysWidth.max == 0);
        const offset = @as(u64, index.raw()) * @sizeOf(Entry);
        return base.addr().offset(@intCast(offset)) catch unreachable;
    }
};

const TableEntry = packed struct(u64) {
    present: bool = true,
    writable: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    _reserved_6_8: u3 = 0,
    available_low: u3,
    child_frame_index: u40,
    available_high: u11,
    no_execute: bool,

    const Self = @This();

    fn init(child: Phys4K.Base, flags: TableFlags) TableEntry {
        std.debug.assert(child.isValid());
        std.debug.assert(child.raw() >> PhysWidth.max == 0);
        return .{
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .accessed = flags.accessed,
            .available_low = flags.available_low,
            .child_frame_index = @intCast(child.index()),
            .available_high = flags.available_high,
            .no_execute = flags.no_execute,
        };
    }

    comptime {
        std.debug.assert(@bitSizeOf(Self) == 64);
        std.debug.assert(@bitOffsetOf(Self, "child_frame_index") == 12);
        std.debug.assert(@bitOffsetOf(Self, "available_high") == 52);
        std.debug.assert(@bitOffsetOf(Self, "no_execute") == 63);
    }
};

const PageEntry4K = packed struct(u64) {
    present: bool = true,
    writable: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    dirty: bool,
    pat: bool,
    global: bool,
    available_low: u3,
    frame_index: u40,
    available_high: u11,
    no_execute: bool,

    const Self = @This();

    fn init(frame: Phys4K.Base, flags: PageFlags) PageEntry4K {
        std.debug.assert(frame.isValid());
        std.debug.assert(frame.raw() >> PhysWidth.max == 0);
        return .{
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .accessed = flags.accessed,
            .dirty = flags.dirty,
            .pat = flags.pat,
            .global = flags.global,
            .available_low = flags.available_low,
            .frame_index = @intCast(frame.index()),
            .available_high = flags.available_high,
            .no_execute = flags.no_execute,
        };
    }

    comptime {
        std.debug.assert(@bitSizeOf(Self) == 64);
        std.debug.assert(@bitOffsetOf(Self, "pat") == 7);
        std.debug.assert(@bitOffsetOf(Self, "frame_index") == 12);
        std.debug.assert(@bitOffsetOf(Self, "available_high") == 52);
        std.debug.assert(@bitOffsetOf(Self, "no_execute") == 63);
    }
};

const PageEntry2M = packed struct(u64) {
    present: bool = true,
    writable: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    dirty: bool,
    page_size: bool = true,
    global: bool,
    available_low: u3,
    pat: bool,
    _reserved_13_20: u8 = 0,
    frame_index: u31,
    available_high: u11,
    no_execute: bool,

    const Self = @This();

    fn init(frame: Phys2M.Base, flags: PageFlags) PageEntry2M {
        std.debug.assert(frame.isValid());
        std.debug.assert(frame.raw() >> PhysWidth.max == 0);
        return .{
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .accessed = flags.accessed,
            .dirty = flags.dirty,
            .global = flags.global,
            .available_low = flags.available_low,
            .pat = flags.pat,
            .frame_index = @intCast(frame.index()),
            .available_high = flags.available_high,
            .no_execute = flags.no_execute,
        };
    }

    comptime {
        std.debug.assert(@bitSizeOf(Self) == 64);
        std.debug.assert(@bitOffsetOf(Self, "page_size") == 7);
        std.debug.assert(@bitOffsetOf(Self, "pat") == 12);
        std.debug.assert(@bitOffsetOf(Self, "frame_index") == 21);
        std.debug.assert(@bitOffsetOf(Self, "available_high") == 52);
        std.debug.assert(@bitOffsetOf(Self, "no_execute") == 63);
    }
};

const PageEntry1G = packed struct(u64) {
    present: bool = true,
    writable: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    dirty: bool,
    page_size: bool = true,
    global: bool,
    available_low: u3,
    pat: bool,
    _reserved_13_29: u17 = 0,
    frame_index: u22,
    available_high: u11,
    no_execute: bool,

    const Self = @This();

    fn init(frame: Phys1G.Base, flags: PageFlags) PageEntry1G {
        std.debug.assert(frame.isValid());
        std.debug.assert(frame.raw() >> PhysWidth.max == 0);
        return .{
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .accessed = flags.accessed,
            .dirty = flags.dirty,
            .global = flags.global,
            .available_low = flags.available_low,
            .pat = flags.pat,
            .frame_index = @intCast(frame.index()),
            .available_high = flags.available_high,
            .no_execute = flags.no_execute,
        };
    }

    comptime {
        std.debug.assert(@bitSizeOf(Self) == 64);
        std.debug.assert(@bitOffsetOf(Self, "page_size") == 7);
        std.debug.assert(@bitOffsetOf(Self, "pat") == 12);
        std.debug.assert(@bitOffsetOf(Self, "frame_index") == 30);
        std.debug.assert(@bitOffsetOf(Self, "available_high") == 52);
        std.debug.assert(@bitOffsetOf(Self, "no_execute") == 63);
    }
};

pub const unit = struct {
    test "physical width accepts the architectural interval" {
        for (32..53) |width| {
            const value: u8 = @intCast(width);
            try std.testing.expectEqual(@as(u6, @intCast(width)), (try PhysWidth.from(value)).bits());
        }

        try std.testing.expectError(error.UnsupportedPhysicalAddressWidth, PhysWidth.from(31));
        try std.testing.expectError(error.UnsupportedPhysicalAddressWidth, PhysWidth.from(53));
        try std.testing.expectError(error.UnsupportedPhysicalAddressWidth, PhysWidth.from(255));
    }

    test "entry producers preserve flags and PAT across leaf sizes" {
        const config: DecodeConfig = .{ .physical_width = .bits_52, .allow_1gib = true, .nxe = true };

        {
            const flags: PageFlags = .{
                .writable = true,
                .user = true,
                .write_through = true,
                .cache_disable = true,
                .accessed = true,
                .dirty = true,
                .global = true,
                .pat = true,
                .available_low = 5,
                .available_high = 0x155,
                .no_execute = true,
            };

            const common: u64 = 0x17f | (@as(u64, 5) << 9) |
                (@as(u64, 0x155) << 52) | (@as(u64, 1) << 63);

            const cases = [_]struct { raw: u64, level: Level, base: u64, flags: u64 }{
                .{
                    .raw = (try PT.pageEntry(try Phys4K.Base.fromInt(0x1234_5000), flags)).raw(),
                    .level = .pt,
                    .base = 0x1234_5000,
                    .flags = common | 0x80,
                },
                .{
                    .raw = (try PD.pageEntry(try Phys2M.Base.fromInt(0x1220_0000), flags)).raw(),
                    .level = .pd,
                    .base = 0x1220_0000,
                    .flags = common | 0x1080,
                },
                .{
                    .raw = (try PDPT.pageEntry(try Phys1G.Base.fromInt(0x8000_0000), flags)).raw(),
                    .level = .pdpt,
                    .base = 0x8000_0000,
                    .flags = common | 0x1080,
                },
            };

            for (cases) |case| {
                const entry = Entry.from(case.raw);
                const leaf = entry.decode(case.level, config).page;

                try std.testing.expectEqual(case.base | case.flags, case.raw);
                try std.testing.expectEqual(case.raw, @as(u64, @bitCast(entry)));
                try std.testing.expectEqual(case.base, leaf.frame.addressInt());
                try std.testing.expectEqual(case.level, leaf.frame.level());
                try std.testing.expectEqual(PageAttributes{
                    .accessed = true,
                    .dirty = true,
                    .global = true,
                    .write_through = true,
                    .cache_disable = true,
                    .pat = true,
                }, leaf.attributes);
                try std.testing.expectEqual(leaf.frame.size() - 1, leaf.frame.offsetMask());
            }
        }

        {
            const child = try PDPT.init(try Phys4K.Base.fromInt(0x3000));
            const table_entry = PML4.tableEntry(child, .{
                .writable = true,
                .user = true,
                .write_through = true,
                .cache_disable = true,
                .accessed = true,
                .available_low = 5,
                .available_high = 0x155,
                .no_execute = true,
            });

            const table_bits: u64 = 0x303f | (@as(u64, 5) << 9) |
                (@as(u64, 0x155) << 52) | (@as(u64, 1) << 63);

            const node = Entry.from(table_entry.raw()).decode(.pml4, config).table;

            try std.testing.expectEqual(table_bits, table_entry.raw());
            try std.testing.expectEqual(Level.pdpt, node.level);
            try std.testing.expectEqual(@as(u64, 0x3ff8), node.entryAddress(.from(511)).raw());
        }
    }

    test "entry classification rejects reserved encodings before frame construction" {
        const config: DecodeConfig = .{ .physical_width = .bits_36, .allow_1gib = true, .nxe = true };
        const cases = [_]struct { raw: u64, level: Level }{
            .{ .raw = 0x81, .level = .pml5 },
            .{ .raw = 0x81, .level = .pml4 },
            .{ .raw = 0x2081, .level = .pd },
            .{ .raw = 0x2000_0081, .level = .pdpt },
            .{ .raw = (@as(u64, 1) << 36) | 1, .level = .pt },
        };

        for (cases) |case| {
            const present = Entry.from(case.raw).decode(case.level, config);
            const absent = Entry.from(case.raw & ~@as(u64, 1)).decode(case.level, config);

            try std.testing.expectEqual(@as(Edge, .reserved), present);
            try std.testing.expectEqual(@as(Edge, .absent), absent);
        }

        {
            const unsupported = Entry.from(0x81).decode(.pdpt, .{ .physical_width = .bits_52 });
            const nx_disabled = Entry.from(0x8000_0000_0000_0001).decode(.pt, .{
                .physical_width = .bits_52,
            });

            try std.testing.expectEqual(@as(Edge, .reserved), unsupported);
            try std.testing.expectEqual(@as(Edge, .reserved), nx_disabled);
        }

        for ([_]u6{ 0, 31, 53, 63 }) |width| {
            const invalid = Entry.from(1).decode(.pt, .{
                .physical_width = @enumFromInt(width),
            });

            try std.testing.expectEqual(@as(Edge, .reserved), invalid);
        }

        {
            const absent = Entry.from(0xffff_ffff_ffff_fffe).decode(.pt, config);
            const page2m = Entry.from(0x1081).decode(.pd, config).page;
            const page1g = Entry.from(0x1081).decode(.pdpt, config).page;
            const page4k = Entry.from(0x81).decode(.pt, config).page;
            const width_boundary = Entry.from(0xffff_f001).decode(.pt, .{ .physical_width = .bits_32 }).page;

            try std.testing.expectEqual(@as(Edge, .absent), absent);
            try std.testing.expectEqual(@as(u64, 0), page2m.frame.addressInt());
            try std.testing.expect(page1g.attributes.pat);
            try std.testing.expect(page4k.attributes.pat);
            try std.testing.expectEqual(@as(u64, 0xffff_f000), width_boundary.frame.addressInt());
        }

        {
            const child = Entry.from(1).decode(.pd, config).table;

            try std.testing.expectEqual(@as(u64, 0), child.base.raw());
        }
    }

    test "typed storage preserves metadata and producer overflow errors" {
        inline for (.{ PML5, PML4, PDPT, PD, PT }) |Producer| {
            var storage = Producer.Storage.init();
            const metadata = try Producer.Entry.nonPresent(0x1234_5678_9abc_def0);
            storage.set(.from(7), metadata);

            try std.testing.expectEqual(Producer.Entry.empty(), storage.get(.from(6)));
            try std.testing.expectEqual(metadata, storage.get(.from(7)));
            try std.testing.expectEqual(Producer.Entry.empty(), storage.get(.from(8)));

            storage.clear(.from(7));

            try std.testing.expectEqual(Producer.Entry.empty(), storage.get(.from(7)));
            try std.testing.expectError(error.Present, Producer.Entry.nonPresent(1));
            const too_wide = try Phys4K.Base.fromInt(@as(u64, 1) << 52);

            try std.testing.expectError(error.PhysicalAddressTooWide, Producer.init(too_wide));
        }

        const address = @as(u64, 1) << 52;
        const page4k = try Phys4K.Base.fromInt(address);
        const page2m = try Phys2M.Base.fromInt(address);
        const page1g = try Phys1G.Base.fromInt(address);

        try std.testing.expectError(error.PhysicalAddressTooWide, PT.pageEntry(page4k, .{}));
        try std.testing.expectError(error.PhysicalAddressTooWide, PD.pageEntry(page2m, .{}));
        try std.testing.expectError(error.PhysicalAddressTooWide, PDPT.pageEntry(page1g, .{}));
    }
};
