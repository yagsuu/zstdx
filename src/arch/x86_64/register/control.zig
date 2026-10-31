const std = @import("std");

const addr = @import("addr");
const target = @import("../target.zig");

pub const CR0 = packed struct(u64) {
    protection_enable: bool,
    monitor_coprocessor: bool,
    emulation: bool,
    task_switched: bool,
    extension_type: bool,
    numeric_error: bool,
    _reserved_6: u10,
    write_protect: bool,
    _reserved_17: bool,
    alignment_mask: bool,
    _reserved_19: u10,
    not_write_through: bool,
    cache_disable: bool,
    paging: bool,
    _reserved_32: u32,

    const Self = @This();

    pub fn init() Self {
        return Self.from(1 << 4);
    }

    pub fn from(value: u64) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u64 {
        return @bitCast(self);
    }

    /// requires cpl 0.
    pub fn read() Self {
        comptime target.require();
        return Self.from(asm volatile ("mov %%cr0, %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// requires cpl 0.
    /// clobbers memory.
    pub fn write(self: Self) void {
        comptime target.require();
        asm volatile ("mov %[v], %%cr0"
            :
            : [v] "r" (self.raw()),
            : .{ .memory = true });
    }
};

pub const CR2 = enum(u64) {
    _,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @enumFromInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @intFromEnum(self);
    }

    /// requires cpl 0.
    pub fn read() Self {
        comptime target.require();
        return Self.from(asm volatile ("mov %%cr2, %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// requires cpl 0.
    /// clobbers memory.
    pub fn write(self: Self) void {
        comptime target.require();
        asm volatile ("mov %[v], %%cr2"
            :
            : [v] "r" (self.raw()),
            : .{ .memory = true });
    }
};

pub const CR3 = packed struct(u64) {
    low_bits: u12,
    page_index: u40,
    _reserved_52: u9,
    lam_u57: bool,
    lam_u48: bool,
    no_flush: bool,

    const Self = @This();

    pub const BaseError = error{
        InvalidPhysicalAddressWidth,
        PhysicalAddressTooWide,
        ReservedBits,
    };

    pub const LowError = error{ReservedLowBits};
    pub const LamError = error{UnsupportedLAM};

    pub const LamMode = enum {
        disabled,
        u48,
        u57,
    };

    pub const Cache = struct {
        write_through: bool,
        cache_disable: bool,
    };

    pub const Low = union(enum) {
        pcid: u12,
        cache: Cache,
    };

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u64 {
        return @bitCast(self);
    }

    /// requires cpl 0.
    pub fn read() Self {
        comptime target.require();
        return Self.from(asm volatile ("mov %%cr3, %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// requires cpl 0.
    /// may invalidate tlb entries.
    /// clobbers memory.
    pub fn write(self: Self) void {
        comptime target.require();
        asm volatile ("mov %[v], %%cr3"
            :
            : [v] "r" (self.raw()),
            : .{ .memory = true });
    }

    pub fn base(self: Self, width: u8) BaseError!addr.PhysAddr {
        if (width < 32 or width > 52) {
            return error.InvalidPhysicalAddressWidth;
        }
        if (self._reserved_52 != 0) {
            return error.ReservedBits;
        }

        const address = @as(u64, self.page_index) << @ctz(@as(u64, addr.pages._4kib));
        if ((address >> @intCast(width)) != 0) {
            return error.PhysicalAddressTooWide;
        }

        return addr.PhysAddr.from(address);
    }

    pub fn low(self: Self, pcid_enabled: bool) LowError!Low {
        if (pcid_enabled) {
            return .{ .pcid = self.low_bits };
        }

        if ((self.low_bits & ~@as(u12, 0b1_1000)) != 0) {
            return error.ReservedLowBits;
        }

        return .{ .cache = .{
            .write_through = (self.low_bits & (1 << 3)) != 0,
            .cache_disable = (self.low_bits & (1 << 4)) != 0,
        } };
    }

    pub fn userLam(self: Self, supported: bool) LamError!LamMode {
        const mode: LamMode = if (self.lam_u57)
            .u57
        else if (self.lam_u48)
            .u48
        else
            .disabled;

        if (mode != .disabled and !supported) {
            return error.UnsupportedLAM;
        }

        return mode;
    }
};

pub const CR4 = packed struct(u64) {
    virtual_8086_mode_extensions: bool,
    protected_mode_virtual_interrupts: bool,
    time_stamp_disable: bool,
    debug_extensions: bool,
    page_size_extensions: bool,
    physical_address_extension: bool,
    machine_check_enable: bool,
    page_global_enable: bool,
    performance_monitoring_counter_enable: bool,
    osfxsr: bool,
    osxmmexcpt: bool,
    umip: bool,
    la57: bool,
    vmx_enable: bool,
    smx_enable: bool,
    _reserved_15: bool,
    fsgsbase_enable: bool,
    pcid_enable: bool,
    osxsave: bool,
    _unknown_19: bool,
    smep: bool,
    smap: bool,
    pke: bool,
    cet: bool,
    _unknown_24: u2,
    _reserved_26: bool,
    lass: bool,
    lam_supervisor: bool,
    _reserved_29: u3,
    fred: bool,
    _reserved_33: u31,

    const Self = @This();

    pub const PcidError = error{UnsupportedPCID};
    pub const Level5Error = error{UnsupportedFiveLevelPaging};
    pub const LamError = error{UnsupportedLAM};

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u64 {
        return @bitCast(self);
    }

    /// requires cpl 0.
    pub fn read() Self {
        comptime target.require();
        return Self.from(asm volatile ("mov %%cr4, %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// requires cpl 0.
    /// faults with #GP on reserved-bit violations.
    /// clobbers memory.
    pub fn write(self: Self) void {
        comptime target.require();
        asm volatile ("mov %[v], %%cr4"
            :
            : [v] "r" (self.raw()),
            : .{ .memory = true });
    }

    pub fn pcidEnabled(self: Self, supported: bool) PcidError!bool {
        if (self.pcid_enable and !supported) {
            return error.UnsupportedPCID;
        }
        return self.pcid_enable;
    }

    pub fn level5Enabled(self: Self, supported: bool) Level5Error!bool {
        if (self.la57 and !supported) {
            return error.UnsupportedFiveLevelPaging;
        }
        return self.la57;
    }

    pub fn supervisorLam(self: Self, supported: bool) LamError!CR3.LamMode {
        if (!self.lam_supervisor) {
            return .disabled;
        }

        if (!supported) {
            return error.UnsupportedLAM;
        }

        return if (self.la57) .u57 else .u48;
    }
};

pub const CR8 = packed struct(u64) {
    task_priority: u4,
    _reserved_4: u60,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u64 {
        return @bitCast(self);
    }

    /// requires cpl 0.
    pub fn read() Self {
        comptime target.require();
        return Self.from(asm volatile ("mov %%cr8, %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// requires cpl 0.
    /// clobbers memory.
    pub fn write(self: Self) void {
        comptime target.require();
        asm volatile ("mov %[v], %%cr8"
            :
            : [v] "r" (self.raw()),
            : .{ .memory = true });
    }
};

pub const XCR0 = packed struct(u64) {
    x87: bool,
    sse: bool,
    avx: bool,
    bndregs: bool,
    bndcsr: bool,
    opmask: bool,
    zmm_hi256: bool,
    hi16_zmm: bool,
    _reserved_8: bool,
    pkru: bool,
    _unknown_10: u7,
    tile_config: bool,
    tile_data: bool,
    apx: bool,
    _reserved_20: u44,

    const Self = @This();

    pub fn init() Self {
        return Self.from(1);
    }

    pub fn from(value: u64) Self {
        return @bitCast(value);
    }

    pub fn raw(self: Self) u64 {
        return @bitCast(self);
    }

    /// requires CR4.osxsave.
    pub fn read() Self {
        comptime target.require();

        var lo: u32 = undefined;
        var hi: u32 = undefined;

        asm volatile ("xgetbv"
            : [lo] "={eax}" (lo),
              [hi] "={edx}" (hi),
            : [c] "{ecx}" (@as(u32, 0)),
        );

        return Self.from((@as(u64, hi) << 32) | @as(u64, lo));
    }

    /// requires cpl 0.
    /// requires CR4.osxsave.
    /// faults with #GP when bits violate cpu support.
    /// clobbers memory.
    pub fn write(self: Self) void {
        comptime target.require();

        const lo: u32 = @truncate(self.raw());
        const hi: u32 = @truncate(self.raw() >> 32);

        asm volatile ("xsetbv"
            :
            : [c] "{ecx}" (@as(u32, 0)),
              [lo] "{eax}" (lo),
              [hi] "{edx}" (hi),
            : .{ .memory = true });
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "CR3 interprets root, low-bit, LAM, and no-flush fields" {
        const value = CR3.from(0x0000_0001_1234_5018);
        const cache_controls = (try value.low(false)).cache;

        try testing.expectEqual(@as(u64, 0x0000_0001_1234_5018), value.raw());
        try testing.expectEqual(@as(u64, 0x0000_0001_1234_5000), (try value.base(52)).raw());
        try testing.expectEqual(@as(u12, 0x18), (try value.low(true)).pcid);
        try testing.expect(cache_controls.write_through);
        try testing.expect(cache_controls.cache_disable);

        try testing.expectError(error.InvalidPhysicalAddressWidth, value.base(31));
        try testing.expectError(error.InvalidPhysicalAddressWidth, value.base(53));
        try testing.expectError(error.PhysicalAddressTooWide, value.base(32));
        try testing.expectError(error.ReservedBits, CR3.from(1 << 52).base(52));
        try testing.expectError(error.ReservedLowBits, CR3.from(1).low(false));

        const lam_u48 = CR3.from(1 << 62);
        const lam_u57 = CR3.from(1 << 61);
        const both_lam = CR3.from((1 << 62) | (1 << 61));

        try testing.expectEqual(.u48, try lam_u48.userLam(true));
        try testing.expectEqual(.u57, try lam_u57.userLam(true));
        try testing.expectEqual(.u57, try both_lam.userLam(true));
        try testing.expectError(error.UnsupportedLAM, lam_u48.userLam(false));
        try testing.expect(CR3.from(1 << 63).no_flush);
    }

    test "CR4 validates paging controls against capabilities" {
        const value = CR4.from((1 << 12) | (1 << 17) | (1 << 28));
        const disabled = CR4.init();
        const four_level_lam = CR4.from(1 << 28);

        try testing.expect(try value.pcidEnabled(true));
        try testing.expect(try value.level5Enabled(true));
        try testing.expectEqual(.u57, try value.supervisorLam(true));
        try testing.expectError(error.UnsupportedPCID, value.pcidEnabled(false));
        try testing.expectError(error.UnsupportedFiveLevelPaging, value.level5Enabled(false));
        try testing.expectError(error.UnsupportedLAM, value.supervisorLam(false));
        try testing.expect(!try disabled.pcidEnabled(false));
        try testing.expect(!try disabled.level5Enabled(false));
        try testing.expectEqual(.disabled, try disabled.supervisorLam(false));
        try testing.expectEqual(.u48, try four_level_lam.supervisorLam(true));
    }
};
