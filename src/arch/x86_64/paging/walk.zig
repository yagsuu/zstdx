//! x86_64 page-walk state, results, and faults.

const std = @import("std");

const cpuid = @import("../cpuid.zig");
const registers = @import("../registers.zig");

const address = @import("address.zig");
const table = @import("table.zig");

const Mode = address.Mode;
const LinearAddress = address.LinearAddress;

const PhysAddr = address.PhysAddr;
const Phys4K = address.Phys4K;
const Phys2M = address.Phys2M;
const Phys1G = address.Phys1G;

const PhysicalAddressWidth = table.PhysicalAddressWidth;
const Level = table.Level;
const Index = table.Index;

const PagingStructureEntry = table.PagingStructureEntry;
const PageFrame = table.PageFrame;
const PageAttributes = table.PageAttributes;

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

pub const EffectivePermissions = struct {
    writable: bool,
    user: bool,
    executable: bool,

    fn intersect(
        self: *EffectivePermissions,
        entry: PagingStructureEntry,
    ) void {
        self.writable = self.writable and entry.writable;
        self.user = self.user and entry.user;
        self.executable = self.executable and !entry.no_execute;
    }
};

pub const Step = struct {
    level: Level,
    index: Index,
    entry_address: PhysAddr,
    entry: PagingStructureEntry,
};

pub const MappedPage = struct {
    linear: LinearAddress,
    physical: PhysAddr,
    frame: PageFrame,
    attributes: PageAttributes,
    permissions: EffectivePermissions,
    step: Step,

    fn init(
        linear: LinearAddress,
        page: ResolvedPage,
        permissions: EffectivePermissions,
        step: Step,
    ) MappedPage {
        std.debug.assert(page.frame.level() == step.level);
        std.debug.assert(step.entry.present);

        return .{
            .linear = linear,
            .physical = PhysAddr.fromInt(
                page.frame.addressInt() |
                    (linear.raw() & page.frame.offsetMask()),
            ),
            .frame = page.frame,
            .attributes = page.attributes,
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

    fn init(
        reason: Reason,
        access: Access,
        execute_disable_enabled: bool,
        step: Step,
    ) Fault {
        const entry_present = step.entry.present;
        std.debug.assert(reason != .not_present or !entry_present);
        std.debug.assert(reason == .not_present or entry_present);

        return .{
            .reason = reason,
            .code = .{
                .present = reason != .not_present,
                .write = access.operation == .write,
                .user = access.privilege == .user,
                .reserved = reason == .reserved_bits,
                .instruction_fetch = execute_disable_enabled and
                    access.operation == .execute,
            },
            .step = step,
        };
    }
};

pub const Result = union(enum) {
    mapped: MappedPage,
    fault: Fault,
};

pub fn Walker(comptime Reader: type) type {
    return struct {
        root_table_base: Phys4K.Frame,
        mode: Mode,
        physical_address_width: PhysicalAddressWidth,
        flags: Flags,
        reader: *Reader,

        const Self = @This();

        pub const Flags = packed struct(u3) {
            page_1gib_supported: bool = false,
            supervisor_write_protect: bool = false,
            execute_disable_enabled: bool = false,

            fn permissionFault(
                self: Flags,
                access: Access,
                permissions: EffectivePermissions,
                step: Step,
            ) ?Fault {
                if (access.privilege == .user and !permissions.user) {
                    return Fault.init(
                        .user_to_supervisor,
                        access,
                        self.execute_disable_enabled,
                        step,
                    );
                }

                if (access.operation == .write and !permissions.writable and
                    (access.privilege == .user or self.supervisor_write_protect))
                {
                    return Fault.init(
                        .write_to_read_only,
                        access,
                        self.execute_disable_enabled,
                        step,
                    );
                }

                if (access.operation == .execute and !permissions.executable) {
                    return Fault.init(
                        .execute_disabled,
                        access,
                        self.execute_disable_enabled,
                        step,
                    );
                }

                return null;
            }
        };

        pub const Input = struct {
            root_table_base: PhysAddr,
            mode: Mode,
            physical_address_width: PhysicalAddressWidth,
            flags: Flags = .{},
        };

        pub const InitError = error{
            Misaligned,
            PhysicalAddressTooWide,
        };

        pub const InitCurrentCPUError =
            InitError ||
            PhysicalAddressWidth.Error ||
            registers.cr3.CR3.LowError ||
            registers.cr4.PCIDError ||
            registers.cr4.Level5Error ||
            registers.efer.Error ||
            error{
                InvalidLinearWidth,
                InvalidNoFlush,
                InvalidPagingState,
                ReservedBits,
            };

        pub fn init(input: Input, reader: *Reader) InitError!Self {
            return .{
                .root_table_base = try rootTableFrame(
                    input.root_table_base,
                    input.physical_address_width,
                ),
                .mode = input.mode,
                .physical_address_width = input.physical_address_width,
                .flags = input.flags,
                .reader = reader,
            };
        }

        /// Capture paging state from the current logical CPU at CPL 0.
        pub fn initCurrentCPU(reader: *Reader) InitCurrentCPUError!Self {
            const sizes = cpuid.addressSizes();
            const features = cpuid.features();
            const cr0 = registers.cr0.read();
            const cr3 = registers.cr3.read();
            const cr4 = registers.cr4.read();
            const efer = registers.efer.read();

            if (!cr0.protection_enable or !cr0.paging or
                !cr4.physical_address_extension or
                !efer.long_mode_enable or !efer.long_mode_active)
            {
                return error.InvalidPagingState;
            }

            const physical_address_width =
                try PhysicalAddressWidth.fromBits(sizes.physical_bits);
            const level5_enabled =
                try cr4.level5Enabled(features.structured.ecx.la57);
            const mode: Mode = if (level5_enabled) .level5 else .level4;

            if (sizes.linear_bits < mode.linearBits()) {
                return error.InvalidLinearWidth;
            }

            const pcid_enabled = try cr4.pcidEnabled(features.basic.ecx.pcid);
            _ = try cr3.low(pcid_enabled);
            if (cr3.no_flush and !pcid_enabled) return error.InvalidNoFlush;

            const root_table_base =
                cr3.tableBaseAddress(physical_address_width.bits()) catch |err| {
                    return switch (err) {
                        error.InvalidPhysicalAddressWidth => unreachable,
                        error.PhysicalAddressTooWide => error.PhysicalAddressTooWide,
                        error.ReservedBits => error.ReservedBits,
                    };
                };

            return Self.init(.{
                .root_table_base = root_table_base,
                .mode = mode,
                .physical_address_width = physical_address_width,
                .flags = .{
                    .page_1gib_supported = features.extended.edx.pdpe1gb,
                    .supervisor_write_protect = cr0.write_protect,
                    .execute_disable_enabled = try efer.executeDisableEnabled(
                        features.extended.edx.nx,
                    ),
                },
            }, reader);
        }

        pub fn updateRootTable(
            self: *Self,
            root_table_base: PhysAddr,
        ) InitError!void {
            const replacement = try rootTableFrame(
                root_table_base,
                self.physical_address_width,
            );

            self.root_table_base = replacement;
        }

        pub fn translate(
            self: *const Self,
            linear_address: LinearAddress,
            access: Access,
        ) Reader.Error!Result {
            std.debug.assert(linear_address.isCanonical(self.mode));

            const indices = linear_address.indices(self.mode);
            const root_level = self.mode.rootLevel();
            const execute_disable_enabled = self.flags.execute_disable_enabled;

            var permissions = EffectivePermissions{
                .writable = true,
                .user = true,
                .executable = true,
            };

            var current_table = WalkTable{
                .base = self.root_table_base,
                .level = root_level,
            };

            for (0..@intFromEnum(root_level)) |_| {
                const index = indices.at(current_table.level);
                const entry_address = PhysAddr.fromInt(
                    current_table.base.addressInt() +
                        @as(u64, index.raw()) * @sizeOf(u64),
                );

                const entry = try self.reader.readEntry(entry_address);
                const step = Step{
                    .level = current_table.level,
                    .index = index,
                    .entry_address = entry_address,
                    .entry = entry,
                };

                if (!entry.present) {
                    return .{ .fault = Fault.init(.not_present, access, execute_disable_enabled, step) };
                }

                if (self.hasReservedBits(entry, current_table.level)) {
                    return .{ .fault = Fault.init(.reserved_bits, access, execute_disable_enabled, step) };
                }

                permissions.intersect(entry);

                if (current_table.nextTable(entry)) |next_table| {
                    current_table = next_table;
                    continue;
                }

                if (self.flags.permissionFault(access, permissions, step)) |fault| {
                    return .{ .fault = fault };
                }

                const page = ResolvedPage.fromEntry(entry, current_table.level);
                return .{ .mapped = MappedPage.init(linear_address, page, permissions, step) };
            }

            unreachable;
        }

        fn rootTableFrame(
            root_table_base: PhysAddr,
            physical_address_width: PhysicalAddressWidth,
        ) InitError!Phys4K.Frame {
            const frame = Phys4K.Frame.fromAddress(root_table_base) catch |err| {
                return switch (err) {
                    error.Misaligned => error.Misaligned,
                    error.OutOfBounds, error.Overflow => unreachable,
                };
            };

            if ((root_table_base.raw() >> physical_address_width.bits()) != 0) {
                return error.PhysicalAddressTooWide;
            }

            return frame;
        }

        fn hasReservedBits(
            self: *const Self,
            entry: PagingStructureEntry,
            level: Level,
        ) bool {
            std.debug.assert(entry.present);

            if (!self.flags.execute_disable_enabled and entry.no_execute) {
                return true;
            }

            const physical_address_bits = entry.physical_address_bits;
            const physical_bits = self.physical_address_width.bits();

            if (physical_bits < 52 and
                physical_address_bits >> (physical_bits - 12) != 0)
            {
                return true;
            }

            return switch (level) {
                .pml4, .pml5 => entry.page_size_or_pat,
                .pdpt => entry.page_size_or_pat and
                    (!self.flags.page_1gib_supported or
                        (physical_address_bits & ((@as(u40, 1) << 18) - 2)) != 0),
                .pd => entry.page_size_or_pat and
                    (physical_address_bits & ((@as(u40, 1) << 9) - 2)) != 0,
                .pt => false,
            };
        }
    };
}

const WalkTable = struct {
    base: Phys4K.Frame,
    level: Level,

    fn nextTable(
        self: WalkTable,
        entry: PagingStructureEntry,
    ) ?WalkTable {
        std.debug.assert(self.base.isValid());
        std.debug.assert(entry.present);

        const references_table = switch (self.level) {
            .pml5, .pml4 => true,
            .pdpt, .pd => !entry.page_size_or_pat,
            .pt => false,
        };

        if (!references_table) return null;

        const base_address = @as(u64, entry.physical_address_bits) << 12;
        return .{
            .base = Phys4K.Frame.fromAddressInt(base_address) catch unreachable,
            .level = self.level.next() orelse unreachable,
        };
    }
};

const ResolvedPage = struct {
    frame: PageFrame,
    attributes: PageAttributes,

    fn fromEntry(
        entry: PagingStructureEntry,
        level: Level,
    ) ResolvedPage {
        std.debug.assert(entry.present);
        std.debug.assert(
            level == .pt or
                ((level == .pd or level == .pdpt) and entry.page_size_or_pat),
        );

        const offset_bits = level.pageOffsetBits() orelse unreachable;
        const base = @as(u64, entry.physical_address_bits >> (offset_bits - 12)) << offset_bits;

        return .{
            .frame = switch (level) {
                .pt => .{
                    .page4kib = Phys4K.Frame.fromAddressInt(base) catch unreachable,
                },
                .pd => .{
                    .page2mib = Phys2M.Frame.fromAddressInt(base) catch unreachable,
                },
                .pdpt => .{
                    .page1gib = Phys1G.Frame.fromAddressInt(base) catch unreachable,
                },
                .pml4, .pml5 => unreachable,
            },
            .attributes = .{
                .accessed = entry.accessed,
                .dirty = entry.dirty,
                .global = entry.global_or_ignored,
                .write_through = entry.write_through,
                .cache_disable = entry.cache_disable,
                .pat = switch (level) {
                    .pt => entry.page_size_or_pat,
                    .pd, .pdpt => (entry.physical_address_bits & 1) != 0,
                    .pml4, .pml5 => unreachable,
                },
            },
        };
    }
};
