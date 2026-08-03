//! x86_64 paging geometry, structures, entries, and mapped frames.
//! `Memory` values do not own physical frames.
//! Mutation uses plain stores; callers own synchronization, publication, and invalidation.

const std = @import("std");

const addr = @import("../../../addr.zig");
const bits = @import("../../../bits.zig");

const PhysAddr = addr.PhysAddr;
const Phys4K = addr.Page(PhysAddr, addr.pages._4kib);
const Phys2M = addr.Page(PhysAddr, addr.pages._2mib);
const Phys1G = addr.Page(PhysAddr, addr.pages._1gib);

const entry_count = 512;
const entry_size_bytes = @sizeOf(u64);
const table_alignment_bytes = addr.pages._4kib;
const architectural_address_bits = 52;

pub const PhysicalAddressWidth = enum(u8) {
    bits_32 = 32,
    bits_36 = 36,
    bits_39 = 39,
    bits_40 = 40,
    bits_46 = 46,
    bits_48 = 48,
    bits_52 = 52,

    pub const Error = error{UnsupportedPhysicalAddressWidth};

    pub fn fromBits(physical_address_bits: u8) Error!PhysicalAddressWidth {
        return switch (physical_address_bits) {
            32 => .bits_32,
            36 => .bits_36,
            39 => .bits_39,
            40 => .bits_40,
            46 => .bits_46,
            48 => .bits_48,
            52 => .bits_52,
            else => error.UnsupportedPhysicalAddressWidth,
        };
    }

    pub fn bits(self: PhysicalAddressWidth) u6 {
        return @intCast(@intFromEnum(self));
    }
};

pub const Level = enum(u3) {
    pt = 1,
    pd = 2,
    pdpt = 3,
    pml4 = 4,
    pml5 = 5,

    pub fn indexShift(self: Level) u6 {
        return switch (self) {
            .pt => 12,
            .pd => 21,
            .pdpt => 30,
            .pml4 => 39,
            .pml5 => 48,
        };
    }

    pub fn next(self: Level) ?Level {
        return switch (self) {
            .pml5 => .pml4,
            .pml4 => .pdpt,
            .pdpt => .pd,
            .pd => .pt,
            .pt => null,
        };
    }

    pub fn pageOffsetBits(self: Level) ?u6 {
        return switch (self) {
            .pt => 12,
            .pd => 21,
            .pdpt => 30,
            .pml4, .pml5 => null,
        };
    }

    pub fn pageSizeBytes(self: Level) ?u64 {
        const offset_bits = self.pageOffsetBits() orelse return null;
        return @as(u64, 1) << offset_bits;
    }

    pub fn pageOffsetMask(self: Level) ?u64 {
        const offset_bits = self.pageOffsetBits() orelse return null;
        return bits.mask.low(u64, offset_bits);
    }
};

pub const Index = enum(u9) {
    _,

    pub fn fromInt(value: u9) Index {
        return @enumFromInt(value);
    }

    pub fn raw(self: Index) u9 {
        return @intFromEnum(self);
    }
};

pub const Indices = struct {
    pml5: Index,
    pml4: Index,
    pdpt: Index,
    pd: Index,
    pt: Index,

    pub fn at(self: Indices, level: Level) Index {
        return switch (level) {
            .pml5 => self.pml5,
            .pml4 => self.pml4,
            .pdpt => self.pdpt,
            .pd => self.pd,
            .pt => self.pt,
        };
    }
};

pub const PagingStructureEntry = packed struct(u64) {
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
    physical_address_bits: u40 = 0,
    available_high: u11 = 0,
    no_execute: bool = false,

    const Self = @This();

    pub fn empty() PagingStructureEntry {
        return .{};
    }

    pub fn fromRaw(raw_entry: u64) PagingStructureEntry {
        return @bitCast(raw_entry);
    }

    pub fn raw(self: PagingStructureEntry) u64 {
        return @bitCast(self);
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
        std.debug.assert(@bitOffsetOf(Self, "physical_address_bits") == 12);
        std.debug.assert(@bitOffsetOf(Self, "available_high") == 52);
        std.debug.assert(@bitOffsetOf(Self, "no_execute") == 63);
    }
};

pub const TableEntryFlags = struct {
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
    pub const Entry = EntryType(@This());
    pub const Memory = MemoryType(Entry);

    pub fn init(base_frame: Phys4K.Frame) InitError!PML5 {
        try validateAddressWidth(base_frame.addressInt());
        return @enumFromInt(base_frame.addressInt());
    }

    pub fn base(self: PML5) Phys4K.Frame {
        return Phys4K.Frame.fromAddressInt(@intFromEnum(self)) catch unreachable;
    }

    pub fn entryAddress(self: PML5, index: Index) PhysAddr {
        return producerEntryAddress(self.base(), index);
    }

    pub fn tableEntry(
        child: PML4,
        flags: TableEntryFlags,
    ) Entry {
        const raw: u64 = @bitCast(TableEntry.init(child.base(), flags));
        return @enumFromInt(raw);
    }
};

pub const PML4 = enum(u64) {
    _,

    pub const InitError = error{PhysicalAddressTooWide};
    pub const Entry = EntryType(@This());
    pub const Memory = MemoryType(Entry);

    pub fn init(base_frame: Phys4K.Frame) InitError!PML4 {
        try validateAddressWidth(base_frame.addressInt());
        return @enumFromInt(base_frame.addressInt());
    }

    pub fn base(self: PML4) Phys4K.Frame {
        return Phys4K.Frame.fromAddressInt(@intFromEnum(self)) catch unreachable;
    }

    pub fn entryAddress(self: PML4, index: Index) PhysAddr {
        return producerEntryAddress(self.base(), index);
    }

    pub fn tableEntry(
        child: PDPT,
        flags: TableEntryFlags,
    ) Entry {
        const raw: u64 = @bitCast(TableEntry.init(child.base(), flags));
        return @enumFromInt(raw);
    }
};

pub const PDPT = enum(u64) {
    _,

    pub const InitError = error{PhysicalAddressTooWide};
    pub const PageEntryError = error{PhysicalAddressTooWide};
    pub const Entry = EntryType(@This());
    pub const Memory = MemoryType(Entry);

    pub fn init(base_frame: Phys4K.Frame) InitError!PDPT {
        try validateAddressWidth(base_frame.addressInt());
        return @enumFromInt(base_frame.addressInt());
    }

    pub fn base(self: PDPT) Phys4K.Frame {
        return Phys4K.Frame.fromAddressInt(@intFromEnum(self)) catch unreachable;
    }

    pub fn entryAddress(self: PDPT, index: Index) PhysAddr {
        return producerEntryAddress(self.base(), index);
    }

    pub fn tableEntry(
        child: PD,
        flags: TableEntryFlags,
    ) Entry {
        const raw: u64 = @bitCast(TableEntry.init(child.base(), flags));
        return @enumFromInt(raw);
    }

    pub fn pageEntry(
        frame: Phys1G.Frame,
        flags: PageFlags,
    ) PageEntryError!Entry {
        try validateAddressWidth(frame.addressInt());
        const raw: u64 = @bitCast(PageEntry1G.init(frame, flags));
        return @enumFromInt(raw);
    }
};

pub const PD = enum(u64) {
    _,

    pub const InitError = error{PhysicalAddressTooWide};
    pub const PageEntryError = error{PhysicalAddressTooWide};
    pub const Entry = EntryType(@This());
    pub const Memory = MemoryType(Entry);

    pub fn init(base_frame: Phys4K.Frame) InitError!PD {
        try validateAddressWidth(base_frame.addressInt());
        return @enumFromInt(base_frame.addressInt());
    }

    pub fn base(self: PD) Phys4K.Frame {
        return Phys4K.Frame.fromAddressInt(@intFromEnum(self)) catch unreachable;
    }

    pub fn entryAddress(self: PD, index: Index) PhysAddr {
        return producerEntryAddress(self.base(), index);
    }

    pub fn tableEntry(
        child: PT,
        flags: TableEntryFlags,
    ) Entry {
        const raw: u64 = @bitCast(TableEntry.init(child.base(), flags));
        return @enumFromInt(raw);
    }

    pub fn pageEntry(
        frame: Phys2M.Frame,
        flags: PageFlags,
    ) PageEntryError!Entry {
        try validateAddressWidth(frame.addressInt());
        const raw: u64 = @bitCast(PageEntry2M.init(frame, flags));
        return @enumFromInt(raw);
    }
};

pub const PT = enum(u64) {
    _,

    pub const InitError = error{PhysicalAddressTooWide};
    pub const PageEntryError = error{PhysicalAddressTooWide};
    pub const Entry = EntryType(@This());
    pub const Memory = MemoryType(Entry);

    pub fn init(base_frame: Phys4K.Frame) InitError!PT {
        try validateAddressWidth(base_frame.addressInt());
        return @enumFromInt(base_frame.addressInt());
    }

    pub fn base(self: PT) Phys4K.Frame {
        return Phys4K.Frame.fromAddressInt(@intFromEnum(self)) catch unreachable;
    }

    pub fn entryAddress(self: PT, index: Index) PhysAddr {
        return producerEntryAddress(self.base(), index);
    }

    pub fn pageEntry(
        frame: Phys4K.Frame,
        flags: PageFlags,
    ) PageEntryError!Entry {
        try validateAddressWidth(frame.addressInt());
        const raw: u64 = @bitCast(PageEntry4K.init(frame, flags));
        return @enumFromInt(raw);
    }
};

pub const PageFrame = union(enum) {
    page4kib: Phys4K.Frame,
    page2mib: Phys2M.Frame,
    page1gib: Phys1G.Frame,

    pub fn level(self: PageFrame) Level {
        return switch (self) {
            .page4kib => .pt,
            .page2mib => .pd,
            .page1gib => .pdpt,
        };
    }

    pub fn address(self: PageFrame) PhysAddr {
        return switch (self) {
            inline else => |frame| frame.address(),
        };
    }

    pub fn addressInt(self: PageFrame) u64 {
        return self.address().raw();
    }

    pub fn sizeBytes(self: PageFrame) u64 {
        return self.level().pageSizeBytes().?;
    }

    pub fn offsetBits(self: PageFrame) u6 {
        return self.level().pageOffsetBits().?;
    }

    pub fn offsetMask(self: PageFrame) u64 {
        return self.level().pageOffsetMask().?;
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

fn EntryType(comptime Tag: type) type {
    return enum(u64) {
        _,

        const Self = @This();

        pub const TagType = Tag;
        pub const Raw = u64;
        pub const NonPresentError = error{Present};

        pub fn empty() Self {
            return @enumFromInt(0);
        }

        pub fn nonPresent(raw_entry: Raw) NonPresentError!Self {
            if ((raw_entry & 1) != 0) return error.Present;
            return @enumFromInt(raw_entry);
        }

        pub fn raw(self: Self) Raw {
            return @intFromEnum(self);
        }
    };
}

fn MemoryType(comptime Entry: type) type {
    return extern struct {
        /// Hardware-visible entries in caller-owned storage.
        entries: [entry_count]Entry align(table_alignment_bytes),

        const Self = @This();

        pub fn init() Self {
            return .{
                .entries = [_]Entry{Entry.empty()} ** entry_count,
            };
        }

        pub fn get(self: *const Self, index: Index) Entry {
            return self.entries[index.raw()];
        }

        /// Plain store; the caller owns synchronization, publication, and invalidation.
        pub fn set(self: *Self, index: Index, entry: Entry) void {
            self.entries[index.raw()] = entry;
        }

        /// Plain store; the caller owns synchronization, publication, and invalidation.
        pub fn clear(self: *Self, index: Index) void {
            self.entries[index.raw()] = Entry.empty();
        }

        comptime {
            std.debug.assert(@sizeOf(Self) == table_alignment_bytes);
            std.debug.assert(@alignOf(Self) == table_alignment_bytes);
        }
    };
}

fn validateAddressWidth(address_value: u64) error{PhysicalAddressTooWide}!void {
    if ((address_value >> architectural_address_bits) != 0) {
        return error.PhysicalAddressTooWide;
    }
}

fn producerEntryAddress(base: Phys4K.Frame, index: Index) PhysAddr {
    std.debug.assert(base.isValid());
    std.debug.assert(base.addressInt() >> architectural_address_bits == 0);
    const offset_bytes = @as(u64, index.raw()) * entry_size_bytes;
    std.debug.assert(offset_bytes < table_alignment_bytes);
    return PhysAddr.fromInt(base.addressInt() + offset_bytes);
}

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

    fn init(child: Phys4K.Frame, flags: TableEntryFlags) TableEntry {
        std.debug.assert(child.isValid());
        std.debug.assert(child.addressInt() >> architectural_address_bits == 0);
        return .{
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .accessed = flags.accessed,
            .available_low = flags.available_low,
            .child_frame_index = @intCast(child.frameIndex()),
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

    fn init(frame: Phys4K.Frame, flags: PageFlags) PageEntry4K {
        std.debug.assert(frame.isValid());
        std.debug.assert(frame.addressInt() >> architectural_address_bits == 0);
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
            .frame_index = @intCast(frame.frameIndex()),
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

    fn init(frame: Phys2M.Frame, flags: PageFlags) PageEntry2M {
        std.debug.assert(frame.isValid());
        std.debug.assert(frame.addressInt() >> architectural_address_bits == 0);
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
            .frame_index = @intCast(frame.frameIndex()),
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

    fn init(frame: Phys1G.Frame, flags: PageFlags) PageEntry1G {
        std.debug.assert(frame.isValid());
        std.debug.assert(frame.addressInt() >> architectural_address_bits == 0);
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
            .frame_index = @intCast(frame.frameIndex()),
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
