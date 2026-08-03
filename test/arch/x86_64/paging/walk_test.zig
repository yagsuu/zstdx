//! x86_64 paging walker contract tests.
//! Spec: docs/specs/arch/x86_64/paging.md.

const std = @import("std");
const builtin = @import("builtin");
const x86 = @import("stdx").arch.x86_64;
const paging = x86.paging;

const testing = std.testing;

const Slot = struct {
    level: paging.Level,
    address: paging.PhysAddr,
    entry: paging.PagingStructureEntry,
};

const MemoryReader = struct {
    slots: []const Slot,
    calls: usize = 0,
    fail_at: ?usize = null,

    pub const Error = error{
        MissingEntry,
        Unavailable,
    };

    pub fn readEntry(
        self: *MemoryReader,
        address: paging.PhysAddr,
    ) Error!paging.PagingStructureEntry {
        if (self.fail_at == self.calls) return error.Unavailable;
        self.calls += 1;
        for (self.slots) |slot| {
            if (slot.address == address) return slot.entry;
        }
        return error.MissingEntry;
    }
};

const PageWalker = paging.Walker(MemoryReader);

const EntryPermissions = struct {
    writable: bool = true,
    user: bool = true,
    no_execute: bool = false,
};

const LeafAttributes = struct {
    accessed: bool = false,
    dirty: bool = false,
    global: bool = false,
    write_through: bool = false,
    cache_disable: bool = false,
    pat: bool = false,
};

const Fixture = struct {
    slots: [5]Slot = undefined,
    count: usize = 0,

    fn slice(self: *const Fixture) []const Slot {
        return self.slots[0..self.count];
    }

    fn at(self: *Fixture, level: paging.Level) *Slot {
        for (self.slots[0..self.count]) |*slot| {
            if (slot.level == level) return slot;
        }
        unreachable;
    }
};

const Observed = struct {
    result: paging.walk.Result,
    calls: usize,
};

fn phys(raw: u64) paging.PhysAddr {
    return paging.PhysAddr.fromInt(raw);
}

fn levelIndex(level: paging.Level) usize {
    return @intFromEnum(level) - 1;
}

fn tableBase(level: paging.Level) u64 {
    return switch (level) {
        .pml5 => 0x1000,
        .pml4 => 0x2000,
        .pdpt => 0x3000,
        .pd => 0x4000,
        .pt => 0x5000,
    };
}

fn indexAt(level: paging.Level) u9 {
    return switch (level) {
        .pml5 => 5,
        .pml4 => 1,
        .pdpt => 2,
        .pd => 3,
        .pt => 4,
    };
}

fn linearRaw(mode: paging.Mode) u64 {
    const lower = (@as(u64, indexAt(.pml4)) << paging.Level.pml4.indexShift()) |
        (@as(u64, indexAt(.pdpt)) << paging.Level.pdpt.indexShift()) |
        (@as(u64, indexAt(.pd)) << paging.Level.pd.indexShift()) |
        (@as(u64, indexAt(.pt)) << paging.Level.pt.indexShift()) |
        0xabc;
    return if (mode == .level5)
        lower | (@as(u64, indexAt(.pml5)) << paging.Level.pml5.indexShift())
    else
        lower;
}

fn permissionBits(value: EntryPermissions) u64 {
    return (@as(u64, @intFromBool(value.writable)) << 1) |
        (@as(u64, @intFromBool(value.user)) << 2) |
        (@as(u64, @intFromBool(value.no_execute)) << 63);
}

fn buildFixture(
    mode: paging.Mode,
    leaf_level: paging.Level,
    frame_base: u64,
    permissions: [5]EntryPermissions,
    attributes: LeafAttributes,
) Fixture {
    var fixture = Fixture{};
    var level = mode.rootLevel();

    while (true) {
        const entry_address = tableBase(level) + @as(u64, indexAt(level)) * 8;
        var raw = @as(u64, 1) | permissionBits(permissions[levelIndex(level)]);
        if (level == leaf_level) {
            raw |= frame_base;
            raw |= @as(u64, @intFromBool(attributes.write_through)) << 3;
            raw |= @as(u64, @intFromBool(attributes.cache_disable)) << 4;
            raw |= @as(u64, @intFromBool(attributes.accessed)) << 5;
            raw |= @as(u64, @intFromBool(attributes.dirty)) << 6;
            raw |= @as(u64, @intFromBool(attributes.global)) << 8;
            switch (level) {
                .pt => raw |= @as(u64, @intFromBool(attributes.pat)) << 7,
                .pd, .pdpt => {
                    raw |= @as(u64, 1) << 7;
                    raw |= @as(u64, @intFromBool(attributes.pat)) << 12;
                },
                .pml4, .pml5 => unreachable,
            }
        } else {
            const next = level.next().?;
            raw |= tableBase(next);
        }

        fixture.slots[fixture.count] = .{
            .level = level,
            .address = phys(entry_address),
            .entry = .fromRaw(raw),
        };
        fixture.count += 1;
        if (level == leaf_level) break;
        level = level.next().?;
    }
    return fixture;
}

fn defaultPermissions() [5]EntryPermissions {
    return [_]EntryPermissions{.{}} ** 5;
}

fn walkerInput(
    mode: paging.Mode,
    width: paging.PhysicalAddressWidth,
    flags: PageWalker.Flags,
) PageWalker.Input {
    return .{
        .root_table_base = phys(tableBase(mode.rootLevel())),
        .mode = mode,
        .physical_address_width = width,
        .flags = flags,
    };
}

fn translate(
    fixture: *const Fixture,
    mode: paging.Mode,
    width: paging.PhysicalAddressWidth,
    flags: PageWalker.Flags,
    access: paging.walk.Access,
) !Observed {
    var reader = MemoryReader{ .slots = fixture.slice() };
    const walker = try PageWalker.init(walkerInput(mode, width, flags), &reader);
    const linear = try paging.LinearAddress.fromCanonical(linearRaw(mode), mode);
    return .{
        .result = try walker.translate(linear, access),
        .calls = reader.calls,
    };
}

fn expectFault(result: paging.walk.Result, reason: paging.walk.Fault.Reason) !paging.walk.Fault {
    return switch (result) {
        .mapped => error.ExpectedFault,
        .fault => |fault| if (fault.reason == reason) fault else error.UnexpectedFault,
    };
}

fn expectMapped(result: paging.walk.Result) !paging.walk.MappedPage {
    return switch (result) {
        .mapped => |mapped| mapped,
        .fault => error.ExpectedMapping,
    };
}

test "unit: initialization validates and transactionally replaces the root" {
    const no_slots = [_]Slot{};
    var reader = MemoryReader{ .slots = &no_slots };
    var walker = try PageWalker.init(.{
        .root_table_base = phys(0x1000),
        .mode = .level5,
        .physical_address_width = .bits_48,
    }, &reader);
    try testing.expectEqual(@as(u64, 0x1000), walker.root_table_base.addressInt());
    try testing.expectEqual(PageWalker.Flags{}, walker.flags);

    try testing.expectError(
        error.Misaligned,
        PageWalker.init(.{
            .root_table_base = phys(1),
            .mode = .level4,
            .physical_address_width = .bits_52,
        }, &reader),
    );
    try testing.expectError(
        error.PhysicalAddressTooWide,
        PageWalker.init(.{
            .root_table_base = phys(@as(u64, 1) << 48),
            .mode = .level4,
            .physical_address_width = .bits_48,
        }, &reader),
    );

    try testing.expectError(error.Misaligned, walker.updateRootTable(phys(3)));
    try testing.expectEqual(@as(u64, 0x1000), walker.root_table_base.addressInt());
    try walker.updateRootTable(phys(0x9000));
    try testing.expectEqual(@as(u64, 0x9000), walker.root_table_base.addressInt());
}

test "model: every page size and root depth preserves offsets within reader bounds" {
    const cases = [_]struct {
        mode: paging.Mode,
        leaf: paging.Level,
        frame: u64,
        calls: usize,
    }{
        .{ .mode = .level4, .leaf = .pt, .frame = 0x8000, .calls = 4 },
        .{ .mode = .level5, .leaf = .pt, .frame = 0x8000, .calls = 5 },
        .{ .mode = .level4, .leaf = .pd, .frame = 0x20_0000, .calls = 3 },
        .{ .mode = .level4, .leaf = .pdpt, .frame = 0x4000_0000, .calls = 2 },
    };
    const attributes = LeafAttributes{
        .accessed = true,
        .dirty = true,
        .global = true,
        .write_through = true,
        .cache_disable = true,
        .pat = true,
    };
    const flags = PageWalker.Flags{
        .page_1gib_supported = true,
        .execute_disable_enabled = true,
    };

    for (cases) |case| {
        var fixture = buildFixture(
            case.mode,
            case.leaf,
            case.frame,
            defaultPermissions(),
            attributes,
        );
        const before = fixture.slots;
        const observed = try translate(
            &fixture,
            case.mode,
            .bits_48,
            flags,
            .read(.user),
        );
        const mapped = try expectMapped(observed.result);
        try testing.expectEqual(
            case.frame | (linearRaw(case.mode) & case.leaf.pageOffsetMask().?),
            mapped.physical.raw(),
        );
        try testing.expectEqual(case.leaf, mapped.frame.level());
        try testing.expectEqual(case.leaf, mapped.step.level);
        try testing.expectEqual(case.calls, observed.calls);
        try testing.expect(mapped.attributes.accessed);
        try testing.expect(mapped.attributes.dirty);
        try testing.expect(mapped.attributes.global);
        try testing.expect(mapped.attributes.write_through);
        try testing.expect(mapped.attributes.cache_disable);
        try testing.expect(mapped.attributes.pat);
        try testing.expect(mapped.permissions.writable);
        try testing.expect(mapped.permissions.user);
        try testing.expect(mapped.permissions.executable);
        try testing.expectEqualSlices(Slot, before[0..fixture.count], fixture.slice());
    }
}

test "model: permissions accumulate at every level with architectural precedence" {
    const flags = PageWalker.Flags{
        .page_1gib_supported = true,
        .supervisor_write_protect = true,
        .execute_disable_enabled = true,
    };
    const levels = [_]paging.Level{ .pml5, .pml4, .pdpt, .pd, .pt };

    for (levels) |restricted_level| {
        var permissions = defaultPermissions();
        permissions[levelIndex(restricted_level)].writable = false;
        const fixture = buildFixture(.level5, .pt, 0x8000, permissions, .{});
        const observed = try translate(&fixture, .level5, .bits_48, flags, .write(.user));
        _ = try expectFault(observed.result, .write_to_read_only);
    }

    var combined = defaultPermissions();
    combined[levelIndex(.pml5)].writable = false;
    combined[levelIndex(.pdpt)].user = false;
    combined[levelIndex(.pd)].no_execute = true;
    const combined_fixture = buildFixture(.level5, .pt, 0x8000, combined, .{});
    const inspected = try expectMapped((try translate(
        &combined_fixture,
        .level5,
        .bits_48,
        flags,
        .read(.supervisor),
    )).result);
    try testing.expect(!inspected.permissions.writable);
    try testing.expect(!inspected.permissions.user);
    try testing.expect(!inspected.permissions.executable);

    const user_write = try translate(
        &combined_fixture,
        .level5,
        .bits_48,
        flags,
        .write(.user),
    );
    _ = try expectFault(user_write.result, .user_to_supervisor);

    var nx_only = defaultPermissions();
    nx_only[levelIndex(.pml4)].no_execute = true;
    const nx_fixture = buildFixture(.level5, .pt, 0x8000, nx_only, .{});
    _ = try expectFault(
        (try translate(&nx_fixture, .level5, .bits_48, flags, .execute(.supervisor))).result,
        .execute_disabled,
    );

    var readonly = defaultPermissions();
    readonly[levelIndex(.pt)].writable = false;
    const readonly_fixture = buildFixture(.level4, .pt, 0x8000, readonly, .{});
    const wp_disabled = PageWalker.Flags{ .execute_disable_enabled = true };
    _ = try expectMapped((try translate(
        &readonly_fixture,
        .level4,
        .bits_48,
        wp_disabled,
        .write(.supervisor),
    )).result);
    _ = try expectFault(
        (try translate(&readonly_fixture, .level4, .bits_48, flags, .write(.supervisor))).result,
        .write_to_read_only,
    );
}

test "model: not-present and reserved encodings have deterministic faults" {
    const enabled = PageWalker.Flags{
        .page_1gib_supported = true,
        .supervisor_write_protect = true,
        .execute_disable_enabled = true,
    };

    var absent = buildFixture(.level4, .pt, 0x8000, defaultPermissions(), .{});
    absent.at(.pml4).entry = .fromRaw((@as(u64, 1) << 63) | (@as(u64, 1) << 7));
    const absent_fault = try expectFault(
        (try translate(&absent, .level4, .bits_48, enabled, .execute(.user))).result,
        .not_present,
    );
    try testing.expect(!absent_fault.code.present);
    try testing.expect(!absent_fault.code.write);
    try testing.expect(absent_fault.code.user);
    try testing.expect(!absent_fault.code.reserved);
    try testing.expect(absent_fault.code.instruction_fetch);

    const ReservedCase = struct {
        mode: paging.Mode,
        leaf: paging.Level,
        mutate_level: paging.Level,
        extra_bits: u64,
        width: paging.PhysicalAddressWidth = .bits_48,
        flags: PageWalker.Flags = enabled,
    };
    const cases = [_]ReservedCase{
        .{ .mode = .level5, .leaf = .pt, .mutate_level = .pml5, .extra_bits = @as(u64, 1) << 7 },
        .{ .mode = .level4, .leaf = .pt, .mutate_level = .pml4, .extra_bits = @as(u64, 1) << 7 },
        .{ .mode = .level4, .leaf = .pdpt, .mutate_level = .pdpt, .extra_bits = 0, .flags = .{ .execute_disable_enabled = true } },
        .{ .mode = .level4, .leaf = .pt, .mutate_level = .pml4, .extra_bits = @as(u64, 1) << 39, .width = .bits_39 },
        .{ .mode = .level4, .leaf = .pd, .mutate_level = .pd, .extra_bits = @as(u64, 1) << 13 },
        .{ .mode = .level4, .leaf = .pdpt, .mutate_level = .pdpt, .extra_bits = @as(u64, 1) << 13 },
        .{ .mode = .level4, .leaf = .pt, .mutate_level = .pml4, .extra_bits = @as(u64, 1) << 63, .flags = .{ .page_1gib_supported = true } },
    };

    for (cases) |case| {
        var fixture = buildFixture(case.mode, case.leaf, 0x4000_0000, defaultPermissions(), .{});
        const slot = fixture.at(case.mutate_level);
        slot.entry = .fromRaw(slot.entry.raw() | case.extra_bits);
        const fault = try expectFault(
            (try translate(&fixture, case.mode, case.width, case.flags, .write(.user))).result,
            .reserved_bits,
        );
        try testing.expect(fault.code.present);
        try testing.expect(fault.code.write);
        try testing.expect(fault.code.user);
        try testing.expect(fault.code.reserved);
        try testing.expect(!fault.code.instruction_fetch);
        try testing.expectEqual(case.mutate_level, fault.step.level);
    }
}

test "unit: reader errors propagate without becoming page faults" {
    var fixture = buildFixture(.level4, .pt, 0x8000, defaultPermissions(), .{});
    var reader = MemoryReader{
        .slots = fixture.slice(),
        .fail_at = 2,
    };
    const walker = try PageWalker.init(
        walkerInput(.level4, .bits_48, .{ .execute_disable_enabled = true }),
        &reader,
    );
    const linear = try paging.LinearAddress.fromCanonical(linearRaw(.level4), .level4);
    try testing.expectError(
        error.Unavailable,
        walker.translate(linear, .read(.supervisor)),
    );
    try testing.expectEqual(@as(usize, 2), reader.calls);
}

test "integration: current CPU construction runs only when CPL 0 is available" {
    if (builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    if (x86.privilege.currentLevel() != 0) return error.SkipZigTest;

    const no_slots = [_]Slot{};
    var reader = MemoryReader{ .slots = &no_slots };
    _ = try PageWalker.initCurrentCPU(&reader);
}
