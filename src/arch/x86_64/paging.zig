//! x86_64 paging data formats and read-only walker. Spec: docs/specs/arch/x86_64/paging.md.

const std = @import("std");

const addr = @import("../../addr.zig");
const cpuid = @import("cpuid.zig");

pub const LinearTag = opaque {};
pub const LinearAddr = addr.Address(LinearTag, u64);

pub const PhysAddr = addr.PhysAddr;
pub const Phys4K = addr.Page(PhysAddr, addr.pages._4kib);
pub const Phys2M = addr.Page(PhysAddr, addr.pages._2mib);
pub const Phys1G = addr.Page(PhysAddr, addr.pages._1gib);

pub const Mode = enum {
    level4,
    level5,

    pub fn rootLevel(self: Mode) Level {
        return switch (self) {
            .level4 => .pml4,
            .level5 => .pml5,
        };
    }

    pub fn linearBits(self: Mode) u8 {
        return switch (self) {
            .level4 => 48,
            .level5 => 57,
        };
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
    offset_4kib: u12,

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

pub const linear = struct {
    pub const Error = error{NonCanonical};

    pub fn isCanonical(raw: u64, mode: Mode) bool {
        return signExtend(raw, mode).raw() == raw;
    }

    pub fn fromCanonical(raw: u64, mode: Mode) Error!LinearAddr {
        if (!isCanonical(raw, mode)) return error.NonCanonical;
        return LinearAddr.fromInt(raw);
    }

    pub fn signExtend(raw: u64, mode: Mode) LinearAddr {
        const bits: u6 = @intCast(mode.linearBits());
        const sign_bit = @as(u64, 1) << (bits - 1);
        const low_mask = (@as(u64, 1) << bits) - 1;
        const low = raw & low_mask;
        if ((low & sign_bit) != 0) return LinearAddr.fromInt(low | ~low_mask);
        return LinearAddr.fromInt(low);
    }

    pub fn indices(addr_value: LinearAddr, mode: Mode) Error!Indices {
        const raw_value = addr_value.raw();
        if (!isCanonical(raw_value, mode)) return error.NonCanonical;
        return .{
            .pml5 = if (mode == .level5) indexAt(raw_value, .pml5) else Index.fromInt(0),
            .pml4 = indexAt(raw_value, .pml4),
            .pdpt = indexAt(raw_value, .pdpt),
            .pd = indexAt(raw_value, .pd),
            .pt = indexAt(raw_value, .pt),
            .offset_4kib = @truncate(raw_value),
        };
    }

    fn indexAt(raw_value: u64, level: Level) Index {
        return Index.fromInt(@truncate((raw_value >> level.indexShift()) & table.index_mask));
    }
};

pub const Features = struct {
    pcid: bool = false,
    no_execute: bool = false,
    page_1gib: bool = false,
    supervisor_write_protect: bool = true,
};

pub const Config = struct {
    mode: Mode,
    physical_bits: u8,
    features: Features = .{},

    pub const Error = error{InvalidPhysicalWidth};

    pub fn fromAddressSizes(mode: Mode, sizes: cpuid.AddressSizes, features: Features) Config {
        return .{
            .mode = mode,
            .physical_bits = sizes.physical_bits,
            .features = features,
        };
    }

    pub fn linearBits(self: Config) u8 {
        return self.mode.linearBits();
    }

    pub fn validate(self: Config) Error!void {
        if (self.physical_bits < 32 or self.physical_bits > 52) return error.InvalidPhysicalWidth;
    }

    pub fn assertValid(self: Config) void {
        self.validate() catch unreachable;
    }
};

pub const Root = struct {
    frame: Phys4K.Frame,
    pcid: u12 = 0,
    write_through: bool = false,
    cache_disable: bool = false,

    pub const Error = error{
        Misaligned,
        ReservedBits,
        PhysicalAddressTooWide,
        InvalidPhysicalWidth,
    };

    pub fn fromCr3(raw: u64, config: Config) Error!Root {
        try config.validate();
        const frame_raw = raw & ~@as(u64, Phys4K.Size.mask);
        try requirePhysicalAddress(frame_raw, config.physical_bits);

        if (config.features.pcid) {
            return .{
                .frame = Phys4K.Frame.fromAddressInt(frame_raw) catch return error.Misaligned,
                .pcid = @truncate(raw & Phys4K.Size.mask),
            };
        }

        const low = raw & Phys4K.Size.mask;
        if ((low & ~@as(u64, 0b11000)) != 0) return error.ReservedBits;
        return .{
            .frame = Phys4K.Frame.fromAddressInt(frame_raw) catch return error.Misaligned,
            .write_through = (raw & bit(3)) != 0,
            .cache_disable = (raw & bit(4)) != 0,
        };
    }

    pub fn toCr3(self: Root, config: Config) Error!u64 {
        try config.validate();
        const frame_raw = self.frame.addressInt();
        try requirePhysicalAddress(frame_raw, config.physical_bits);

        if (config.features.pcid) return frame_raw | self.pcid;

        var raw: u64 = frame_raw;
        if (self.write_through) raw |= bit(3);
        if (self.cache_disable) raw |= bit(4);
        return raw;
    }
};

pub const Entry = enum(u64) {
    _,

    pub const Error = error{
        NotPresent,
        WrongKind,
        ReservedBits,
        Misaligned,
        PhysicalAddressTooWide,
        UnsupportedPageSize,
        InvalidPhysicalWidth,
    };

    pub const Kind = enum {
        not_present,
        table,
        leaf,
    };

    pub const ReservedBits = struct {
        mask: u64,

        pub fn any(self: ReservedBits) bool {
            return self.mask != 0;
        }
    };

    pub fn empty() Entry {
        return fromRaw(0);
    }

    pub fn fromRaw(raw_value: u64) Entry {
        return @enumFromInt(raw_value);
    }

    pub fn raw(self: Entry) u64 {
        return @intFromEnum(self);
    }

    pub fn isPresent(self: Entry) bool {
        return (self.raw() & bit(0)) != 0;
    }

    pub fn kind(self: Entry, level: Level) Kind {
        if (!self.isPresent()) return .not_present;
        return switch (level) {
            .pt => .leaf,
            .pd, .pdpt => if ((self.raw() & bit(7)) != 0) .leaf else .table,
            .pml4, .pml5 => .table,
        };
    }

    pub fn isLeaf(self: Entry, level: Level) bool {
        return self.kind(level) == .leaf;
    }

    pub fn reservedBits(self: Entry, level: Level, config: Config) ReservedBits {
        if (!self.isPresent()) return .{ .mask = 0 };

        var mask: u64 = 0;
        if (config.physical_bits < 32 or config.physical_bits > 52) {
            mask |= physicalFieldMask();
        } else if (config.physical_bits < 52) {
            mask |= maskRange(.{ .first = config.physical_bits, .last = 51 });
        }

        if (!config.features.no_execute) mask |= self.raw() & bit(63);

        switch (level) {
            .pml4, .pml5 => mask |= self.raw() & bit(7),
            .pdpt => if ((self.raw() & bit(7)) != 0) {
                if (!config.features.page_1gib) mask |= bit(7);
                mask |= self.raw() & maskRange(.{ .first = 12, .last = 29 });
            },
            .pd => if ((self.raw() & bit(7)) != 0) {
                mask |= self.raw() & maskRange(.{ .first = 12, .last = 20 });
            },
            .pt => {},
        }

        return .{ .mask = mask & self.raw() };
    }

    pub fn hasReserved(self: Entry, level: Level, config: Config) bool {
        return self.reservedBits(level, config).any();
    }
};

pub const table = struct {
    pub const index_bits: u8 = 9;
    pub const index_mask: u64 = 0x1ff;
    pub const entry_count: usize = 512;
    pub const alignment: usize = addr.pages._4kib;

    pub const Flags = struct {
        present: bool = true,
        writable: bool = false,
        user: bool = false,
        write_through: bool = false,
        cache_disable: bool = false,
        accessed: bool = false,
        no_execute: bool = false,
        available_low: u3 = 0,
        available_high: u11 = 0,
    };

    pub fn Type(comptime level: Level) type {
        return extern struct {
            entries: [entry_count]Entry,

            pub const table_level = level;

            pub fn init() @This() {
                return .{ .entries = [_]Entry{Entry.empty()} ** entry_count };
            }

            pub fn get(self: *const @This(), index: Index) Entry {
                return self.entries[index.raw()];
            }

            pub fn set(self: *@This(), index: Index, entry_value: Entry) void {
                self.entries[index.raw()] = entry_value;
            }

            pub fn clear(self: *@This(), index: Index) void {
                self.entries[index.raw()] = Entry.empty();
            }
        };
    }

    pub const Pml5 = Type(.pml5);
    pub const Pml4 = Type(.pml4);
    pub const Pdpt = Type(.pdpt);
    pub const Pd = Type(.pd);
    pub const Pt = Type(.pt);

    pub fn entry(frame_value: Phys4K.Frame, flags: Flags) Entry {
        return Entry.fromRaw(frame_value.addressInt() | tableFlagBits(flags));
    }

    pub fn frame(entry_value: Entry, level: Level, config: Config) Entry.Error!Phys4K.Frame {
        config.validate() catch return error.InvalidPhysicalWidth;
        if (!entry_value.isPresent()) return error.NotPresent;
        if (entry_value.kind(level) != .table) return error.WrongKind;
        if (entry_value.hasReserved(level, config)) return error.ReservedBits;
        const frame_raw = entry_value.raw() & physicalFieldMask();
        requirePhysicalAddress(frame_raw, config.physical_bits) catch return error.PhysicalAddressTooWide;
        return Phys4K.Frame.fromAddressInt(frame_raw) catch return error.Misaligned;
    }
};

pub const leaf = struct {
    pub const Flags = struct {
        present: bool = true,
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

    pub const Frame = union(enum) {
        page4kib: Phys4K.Frame,
        page2mib: Phys2M.Frame,
        page1gib: Phys1G.Frame,

        pub fn level(self: Frame) Level {
            return switch (self) {
                .page4kib => .pt,
                .page2mib => .pd,
                .page1gib => .pdpt,
            };
        }

        pub fn address(self: Frame) PhysAddr {
            return switch (self) {
                .page4kib => |frame_value| frame_value.address(),
                .page2mib => |frame_value| frame_value.address(),
                .page1gib => |frame_value| frame_value.address(),
            };
        }

        pub fn addressInt(self: Frame) u64 {
            return self.address().raw();
        }

        pub fn sizeBytes(self: Frame) u64 {
            return switch (self) {
                .page4kib => addr.pages._4kib,
                .page2mib => addr.pages._2mib,
                .page1gib => addr.pages._1gib,
            };
        }

        pub fn offsetBits(self: Frame) u6 {
            return switch (self) {
                .page4kib => 12,
                .page2mib => 21,
                .page1gib => 30,
            };
        }

        pub fn offsetMask(self: Frame) u64 {
            return (@as(u64, 1) << self.offsetBits()) - 1;
        }
    };

    pub const Mapping = struct {
        level: Level,
        frame: Frame,
        entry_address: PhysAddr,
        entry: Entry,

        pub fn base(self: Mapping) PhysAddr {
            return self.frame.address();
        }

        pub fn sizeBytes(self: Mapping) u64 {
            return leaf.sizeBytes(self.level).?;
        }

        pub fn offsetBits(self: Mapping) u6 {
            return leaf.offsetBits(self.level).?;
        }

        pub fn offsetMask(self: Mapping) u64 {
            return leaf.offsetMask(self.level).?;
        }
    };

    pub fn offsetBits(level: Level) ?u6 {
        return switch (level) {
            .pt => 12,
            .pd => 21,
            .pdpt => 30,
            .pml4, .pml5 => null,
        };
    }

    pub fn sizeBytes(level: Level) ?u64 {
        return switch (level) {
            .pt => addr.pages._4kib,
            .pd => addr.pages._2mib,
            .pdpt => addr.pages._1gib,
            .pml4, .pml5 => null,
        };
    }

    pub fn offsetMask(level: Level) ?u64 {
        const bits = offsetBits(level) orelse return null;
        return (@as(u64, 1) << bits) - 1;
    }

    pub fn entry(frame_value: Frame, flags: Flags) Entry {
        return switch (frame_value) {
            .page4kib => |frame_4kib| page4kib(frame_4kib, flags),
            .page2mib => |frame_2mib| page2mib(frame_2mib, flags),
            .page1gib => |frame_1gib| page1gib(frame_1gib, flags),
        };
    }

    pub fn page4kib(frame_value: Phys4K.Frame, flags: Flags) Entry {
        return Entry.fromRaw(frame_value.addressInt() | leafFlagBits(flags, .pt));
    }

    pub fn page2mib(frame_value: Phys2M.Frame, flags: Flags) Entry {
        return Entry.fromRaw(frame_value.addressInt() | bit(7) | leafFlagBits(flags, .pd));
    }

    pub fn page1gib(frame_value: Phys1G.Frame, flags: Flags) Entry {
        return Entry.fromRaw(frame_value.addressInt() | bit(7) | leafFlagBits(flags, .pdpt));
    }

    pub fn frame(entry_value: Entry, level: Level, config: Config) Entry.Error!Frame {
        config.validate() catch return error.InvalidPhysicalWidth;
        if (!entry_value.isPresent()) return error.NotPresent;
        if (entry_value.kind(level) != .leaf) return error.WrongKind;
        if (entry_value.hasReserved(level, config)) return error.ReservedBits;
        const base = entry_value.raw() & leafAddressMask(level);
        requirePhysicalAddress(base, config.physical_bits) catch return error.PhysicalAddressTooWide;
        return switch (level) {
            .pt => .{ .page4kib = Phys4K.Frame.fromAddressInt(base) catch return error.Misaligned },
            .pd => .{ .page2mib = Phys2M.Frame.fromAddressInt(base) catch return error.Misaligned },
            .pdpt => .{ .page1gib = Phys1G.Frame.fromAddressInt(base) catch return error.Misaligned },
            .pml4, .pml5 => error.UnsupportedPageSize,
        };
    }
};

pub const walk = struct {
    pub const Access = struct {
        operation: Operation,
        privilege: Privilege,

        pub const Operation = enum {
            read,
            write,
            execute,
        };

        pub const Privilege = enum {
            supervisor,
            user,
        };

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

    pub const Attributes = struct {
        writable: bool,
        user: bool,
        executable: bool,
        global: bool,
        write_through: bool,
        cache_disable: bool,
        pat: bool,
    };

    pub const Step = struct {
        level: Level,
        index: Index,
        entry_address: PhysAddr,
        entry: Entry,
    };

    pub const Mapping = struct {
        linear: LinearAddr,
        physical: PhysAddr,
        leaf: leaf.Mapping,
        attributes: Attributes,
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
    };

    pub const Result = union(enum) {
        mapped: Mapping,
        fault: Fault,
    };
};
const Walk = walk;

pub fn Walker(comptime Reader: type) type {
    const ErrorSet = walkerError(Reader);

    return struct {
        config: Config,
        reader: Reader,

        const Self = @This();

        pub const Error = ErrorSet;

        pub fn init(config: Config, reader: Reader) Self {
            config.assertValid();
            return .{ .config = config, .reader = reader };
        }

        pub fn walk(self: *Self, root: Root, linear_addr: LinearAddr, access: Walk.Access) Error!Walk.Result {
            return walkImpl(Reader, self.config, &self.reader, root, linear_addr, access);
        }

        pub fn walkRaw(self: *Self, root: Root, raw_linear: u64, access: Walk.Access) Error!Walk.Result {
            return self.walk(root, try linear.fromCanonical(raw_linear, self.config.mode), access);
        }
    };
}

fn walkerError(comptime Reader: type) type {
    const ReaderDecl = readerDecl(Reader);
    return ReaderDecl.Error || Entry.Error || error{
        NonCanonical,
        InvalidConfig,
    };
}

fn walkImpl(
    comptime Reader: type,
    config: Config,
    reader: *Reader,
    root: Root,
    linear_addr: LinearAddr,
    access: Walk.Access,
) walkerError(Reader)!Walk.Result {
    if (!linear.isCanonical(linear_addr.raw(), config.mode)) return error.NonCanonical;

    var effective = initialWalkAttributes();
    var table_frame = root.frame;
    var level = config.mode.rootLevel();
    const idx = try linear.indices(linear_addr, config.mode);

    while (true) {
        const index = idx.at(level);
        const entry_address = walkEntryAddress(table_frame, index);
        const entry_value = try reader.*.readEntry(entry_address);
        const step = Walk.Step{
            .level = level,
            .index = index,
            .entry_address = entry_address,
            .entry = entry_value,
        };

        if (!entry_value.isPresent()) return .{ .fault = makeFault(.not_present, access, false, step) };
        if (entry_value.hasReserved(level, config)) return .{ .fault = makeFault(.reserved_bits, access, true, step) };

        applyEntryAttributes(&effective, entry_value, config);

        switch (entry_value.kind(level)) {
            .not_present => unreachable,
            .table => {
                table_frame = try table.frame(entry_value, level, config);
                level = level.next() orelse return .{ .fault = makeFault(.reserved_bits, access, true, step) };
            },
            .leaf => {
                const leaf_frame = try leaf.frame(entry_value, level, config);
                const page_offset = linear_addr.raw() & leaf_frame.offsetMask();
                const physical = PhysAddr.fromInt(leaf_frame.addressInt() + page_offset);
                const leaf_mapping = leaf.Mapping{
                    .level = level,
                    .frame = leaf_frame,
                    .entry_address = entry_address,
                    .entry = entry_value,
                };

                applyLeafAttributes(&effective, entry_value, level);

                if (permissionFaultReason(effective, access, config)) |reason| {
                    return .{ .fault = makeFault(reason, access, true, step) };
                }

                return .{ .mapped = .{
                    .linear = linear_addr,
                    .physical = physical,
                    .leaf = leaf_mapping,
                    .attributes = effective,
                } };
            },
        }
    }
}

fn initialWalkAttributes() Walk.Attributes {
    return .{
        .writable = true,
        .user = true,
        .executable = true,
        .global = false,
        .write_through = false,
        .cache_disable = false,
        .pat = false,
    };
}

fn walkEntryAddress(table_frame: Phys4K.Frame, index: Index) PhysAddr {
    const offset = @as(u64, index.raw()) * @sizeOf(Entry);
    return PhysAddr.fromInt(table_frame.addressInt() + offset);
}

fn applyEntryAttributes(effective: *Walk.Attributes, entry_value: Entry, config: Config) void {
    effective.writable = effective.writable and flag(entry_value, 1);
    effective.user = effective.user and flag(entry_value, 2);
    if (config.features.no_execute and flag(entry_value, 63)) effective.executable = false;
}

fn applyLeafAttributes(effective: *Walk.Attributes, entry_value: Entry, level: Level) void {
    effective.global = flag(entry_value, 8);
    effective.write_through = flag(entry_value, 3);
    effective.cache_disable = flag(entry_value, 4);
    effective.pat = leafPat(entry_value, level);
}

fn permissionFaultReason(effective: Walk.Attributes, access: Walk.Access, config: Config) ?Walk.Fault.Reason {
    if (access.privilege == .user and !effective.user) return .user_to_supervisor;

    if (access.operation == .write and !effective.writable) {
        const write_protects = access.privilege == .user or config.features.supervisor_write_protect;
        if (write_protects) return .write_to_read_only;
    }

    if (access.operation == .execute and !effective.executable) return .execute_disabled;
    return null;
}

fn readerDecl(comptime Reader: type) type {
    return switch (@typeInfo(Reader)) {
        .pointer => |ptr| ptr.child,
        else => Reader,
    };
}

fn bit(comptime index: u6) u64 {
    return @as(u64, 1) << index;
}

fn flag(entry_value: Entry, comptime index: u6) bool {
    return (entry_value.raw() & bit(index)) != 0;
}

fn maskRange(bounds: struct { first: u8, last: u8 }) u64 {
    std.debug.assert(bounds.first <= bounds.last);
    std.debug.assert(bounds.last < 64);
    const width = bounds.last - bounds.first + 1;
    if (width == 64) return std.math.maxInt(u64);
    return ((@as(u64, 1) << @intCast(width)) - 1) << @intCast(bounds.first);
}

fn physicalFieldMask() u64 {
    return maskRange(.{ .first = 12, .last = 51 });
}

fn leafAddressMask(level: Level) u64 {
    return switch (level) {
        .pt => maskRange(.{ .first = 12, .last = 51 }),
        .pd => maskRange(.{ .first = 21, .last = 51 }),
        .pdpt => maskRange(.{ .first = 30, .last = 51 }),
        .pml4, .pml5 => 0,
    };
}

fn requirePhysicalAddress(raw: u64, physical_bits: u8) Root.Error!void {
    if (physical_bits < 32 or physical_bits > 52) return error.InvalidPhysicalWidth;
    if ((raw >> @intCast(physical_bits)) != 0) return error.PhysicalAddressTooWide;
}

fn tableFlagBits(flags: table.Flags) u64 {
    var raw: u64 = 0;
    if (flags.present) raw |= bit(0);
    if (flags.writable) raw |= bit(1);
    if (flags.user) raw |= bit(2);
    if (flags.write_through) raw |= bit(3);
    if (flags.cache_disable) raw |= bit(4);
    if (flags.accessed) raw |= bit(5);
    raw |= @as(u64, flags.available_low) << 9;
    raw |= @as(u64, flags.available_high) << 52;
    if (flags.no_execute) raw |= bit(63);
    return raw;
}

fn leafFlagBits(flags: leaf.Flags, level: Level) u64 {
    var raw: u64 = 0;
    if (flags.present) raw |= bit(0);
    if (flags.writable) raw |= bit(1);
    if (flags.user) raw |= bit(2);
    if (flags.write_through) raw |= bit(3);
    if (flags.cache_disable) raw |= bit(4);
    if (flags.accessed) raw |= bit(5);
    if (flags.dirty) raw |= bit(6);
    if (flags.pat) raw |= if (level == .pt) bit(7) else bit(12);
    if (flags.global) raw |= bit(8);
    raw |= @as(u64, flags.available_low) << 9;
    raw |= @as(u64, flags.available_high) << 52;
    if (flags.no_execute) raw |= bit(63);
    return raw;
}

fn leafPat(entry_value: Entry, level: Level) bool {
    return switch (level) {
        .pt => flag(entry_value, 7),
        .pd, .pdpt => flag(entry_value, 12),
        .pml4, .pml5 => false,
    };
}

fn makeFault(reason: walk.Fault.Reason, access: walk.Access, present: bool, step: walk.Step) walk.Fault {
    return .{
        .reason = reason,
        .code = .{
            .present = present,
            .write = access.operation == .write,
            .user = access.privilege == .user,
            .reserved = reason == .reserved_bits,
            .instruction_fetch = access.operation == .execute,
        },
        .step = step,
    };
}
