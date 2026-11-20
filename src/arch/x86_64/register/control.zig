const std = @import("std");

const addr = @import("addr");
const bits = @import("bits");
const target = @import("../target.zig");

pub const CR0 = struct {
    const Fields = bits.BitField(u64, .{
        .protection_enable = bool,
        .monitor_coprocessor = bool,
        .emulation = bool,
        .task_switched = bool,
        .extension_type = .{ .type = bool, .access = .reserved, .default = true },
        .numeric_error = bool,
        ._reserved_6 = .{ .type = u10, .access = .reserved },
        .write_protect = bool,
        ._reserved_17 = .{ .type = bool, .access = .reserved },
        .alignment_mask = bool,
        ._reserved_19 = .{ .type = u10, .access = .reserved },
        .not_write_through = bool,
        .cache_disable = bool,
        .paging = bool,
        ._reserved_32 = .{ .type = u32, .access = .reserved },
    });

    pub const __StdxBitField = Fields.Metadata;

    pub const Int = Fields.Int;
    pub const Word = Fields.Word;

    pub const masks = Fields.masks;

    pub const default = Fields.default;
    pub const init = Fields.init;
    pub const from = Fields.from;
    pub const raw = Fields.raw;
    pub const encode = Fields.encode;
    pub const replace = Fields.replace;
    pub const mask = Fields.mask;

    /// Privilege: CPL 0.
    pub fn read() Word {
        return from(Impl.read("cr0"));
    }

    /// Privilege: CPL 0.
    /// Ordering: Compiler memory barrier.
    pub fn write(word: Word) void {
        Impl.write("cr0", raw(word));
    }
};

pub const CR2 = enum(u64) {
    _,

    const Self = @This();

    pub fn init() Self {
        return Self.from(0);
    }

    pub fn from(value: u64) Self {
        return @fromBackingInt(value);
    }

    pub fn raw(self: Self) u64 {
        return @backingInt(self);
    }

    /// Privilege: CPL 0.
    pub fn read() Self {
        comptime target.require();
        return Self.from(asm volatile ("mov %%cr2, %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// Privilege: CPL 0.
    /// Ordering: Compiler memory barrier.
    pub fn write(self: Self) void {
        comptime target.require();
        asm volatile ("mov %[v], %%cr2"
            :
            : [v] "r" (self.raw()),
            : .{ .memory = true });
    }
};

pub const CR3 = struct {
    const Fields = bits.BitField(u64, .{
        .low_bits = u12,
        .page_index = u40,
        ._reserved_52 = .{ .type = u9, .access = .reserved },
        .lam_u57 = bool,
        .lam_u48 = bool,
        .no_flush = bool,
    });

    pub const __StdxBitField = Fields.Metadata;

    pub const Int = Fields.Int;
    pub const Word = Fields.Word;

    pub const masks = Fields.masks;

    pub const default = Fields.default;
    pub const init = Fields.init;
    pub const from = Fields.from;
    pub const raw = Fields.raw;
    pub const encode = Fields.encode;
    pub const replace = Fields.replace;
    pub const mask = Fields.mask;

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

    /// Privilege: CPL 0.
    pub fn read() Word {
        return from(Impl.read("cr3"));
    }

    /// Privilege: CPL 0.
    /// Ordering: Compiler memory barrier.
    /// Effects: May invalidate TLB entries.
    pub fn write(word: Word) void {
        Impl.write("cr3", raw(word));
    }

    pub fn base(self: Word, width: u8) BaseError!addr.PhysAddr {
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

    pub fn low(self: Word, pcide: bool) LowError!Low {
        if (pcide) {
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

    pub fn userLam(self: Word, supported: bool) LamError!LamMode {
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

pub const CR4 = struct {
    const Fields = bits.BitField(u64, .{
        .virtual_8086_mode_extensions = bool,
        .protected_mode_virtual_interrupts = bool,
        .time_stamp_disable = bool,
        .debug_extensions = bool,
        .page_size_extensions = bool,
        .physical_address_extension = bool,
        .machine_check_enable = bool,
        .page_global_enable = bool,
        .performance_monitoring_counter_enable = bool,
        .osfxsr = bool,
        .osxmmexcpt = bool,
        .umip = bool,
        .la57 = bool,
        .vmx_enable = bool,
        .smx_enable = bool,
        ._reserved_15 = .{ .type = bool, .access = .reserved },
        .fsgsbase_enable = bool,
        .pcid_enable = bool,
        .osxsave = bool,
        .smep = .{ .offset = 20, .type = bool },
        .smap = bool,
        .pke = bool,
        .cet = bool,
        ._reserved_26 = .{ .offset = 26, .type = bool, .access = .reserved },
        .lass = bool,
        .lam_supervisor = bool,
        ._reserved_29 = .{ .type = u3, .access = .reserved },
        .fred = bool,
        ._reserved_33 = .{ .type = u31, .access = .reserved },
    });

    pub const __StdxBitField = Fields.Metadata;

    pub const Int = Fields.Int;
    pub const Word = Fields.Word;

    pub const masks = Fields.masks;

    pub const default = Fields.default;
    pub const init = Fields.init;
    pub const from = Fields.from;
    pub const raw = Fields.raw;
    pub const encode = Fields.encode;
    pub const replace = Fields.replace;
    pub const mask = Fields.mask;

    pub const PcidError = error{UnsupportedPCID};
    pub const Level5Error = error{UnsupportedFiveLevelPaging};
    pub const LamError = error{UnsupportedLAM};

    /// Privilege: CPL 0.
    pub fn read() Word {
        return from(Impl.read("cr4"));
    }

    /// Privilege: CPL 0.
    /// Ordering: Compiler memory barrier.
    /// Faults: #GP on reserved-bit violations.
    pub fn write(word: Word) void {
        Impl.write("cr4", raw(word));
    }

    pub fn pcidEnabled(self: Word, supported: bool) PcidError!bool {
        if (self.pcid_enable and !supported) {
            return error.UnsupportedPCID;
        }
        return self.pcid_enable;
    }

    pub fn level5Enabled(self: Word, supported: bool) Level5Error!bool {
        if (self.la57 and !supported) {
            return error.UnsupportedFiveLevelPaging;
        }
        return self.la57;
    }

    pub fn supervisorLam(self: Word, supported: bool) LamError!CR3.LamMode {
        if (!self.lam_supervisor) {
            return .disabled;
        }

        if (!supported) {
            return error.UnsupportedLAM;
        }

        return if (self.la57) .u57 else .u48;
    }
};

pub const CR8 = struct {
    const Fields = bits.BitField(u64, .{
        .task_priority = u4,
        ._reserved_4 = .{ .type = u60, .access = .reserved },
    });

    pub const __StdxBitField = Fields.Metadata;

    pub const Int = Fields.Int;
    pub const Word = Fields.Word;

    pub const masks = Fields.masks;

    pub const default = Fields.default;
    pub const init = Fields.init;
    pub const from = Fields.from;
    pub const raw = Fields.raw;
    pub const encode = Fields.encode;
    pub const replace = Fields.replace;
    pub const mask = Fields.mask;

    /// Privilege: CPL 0.
    pub fn read() Word {
        return from(Impl.read("cr8"));
    }

    /// Privilege: CPL 0.
    /// Ordering: Compiler memory barrier.
    pub fn write(word: Word) void {
        Impl.write("cr8", raw(word));
    }
};

pub const XCR0 = struct {
    const Fields = bits.BitField(u64, .{
        .x87 = .{ .type = bool, .access = .reserved, .default = true },
        .sse = bool,
        .avx = bool,
        .bndregs = bool,
        .bndcsr = bool,
        .opmask = bool,
        .zmm_hi256 = bool,
        .hi16_zmm = bool,
        ._reserved_8 = .{ .type = bool, .access = .reserved },
        .pkru = bool,
        .tile_config = .{ .offset = 17, .type = bool },
        .tile_data = bool,
        .apx = bool,
        ._reserved_20 = .{ .type = u44, .access = .reserved },
    });

    pub const __StdxBitField = Fields.Metadata;

    pub const Int = Fields.Int;
    pub const Word = Fields.Word;

    pub const masks = Fields.masks;

    pub const default = Fields.default;
    pub const init = Fields.init;
    pub const from = Fields.from;
    pub const raw = Fields.raw;
    pub const encode = Fields.encode;
    pub const replace = Fields.replace;
    pub const mask = Fields.mask;

    /// Requires: CR4.OSXSAVE = 1.
    pub fn read() Word {
        comptime target.require();

        var lo: u32 = undefined;
        var hi: u32 = undefined;

        asm volatile ("xgetbv"
            : [lo] "={eax}" (lo),
              [hi] "={edx}" (hi),
            : [c] "{ecx}" (@as(u32, 0)),
        );

        return from((@as(u64, hi) << 32) | @as(u64, lo));
    }

    /// Requires: CR4.OSXSAVE = 1.
    /// Privilege: CPL 0.
    /// Ordering: Compiler memory barrier.
    /// Faults: #GP when bits violate CPU support.
    pub fn write(word: Word) void {
        comptime target.require();

        const lo: u32 = @truncate(raw(word));
        const hi: u32 = @truncate(raw(word) >> 32);

        asm volatile ("xsetbv"
            :
            : [c] "{ecx}" (@as(u32, 0)),
              [lo] "{eax}" (lo),
              [hi] "{edx}" (hi),
            : .{ .memory = true });
    }
};

const Impl = struct {
    fn read(comptime register: []const u8) u64 {
        comptime target.require();
        return asm volatile ("mov %%" ++ register ++ ", %[ret]"
            : [ret] "=r" (-> u64),
        );
    }

    fn write(comptime register: []const u8, value: u64) void {
        comptime target.require();
        asm volatile ("mov %[v], %%" ++ register
            :
            : [v] "r" (value),
            : .{ .memory = true });
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "CR3 interprets root, low-bit, LAM, and no-flush fields" {
        const value = CR3.from(0x0000_0001_1234_5018);
        const cache_controls = (try CR3.low(value, false)).cache;

        try testing.expectEqual(@as(u64, 0x0000_0001_1234_5018), CR3.raw(value));
        try testing.expectEqual(@as(u64, 0x0000_0001_1234_5000), (try CR3.base(value, 52)).raw());
        try testing.expectEqual(@as(u12, 0x18), (try CR3.low(value, true)).pcid);
        try testing.expect(cache_controls.write_through);
        try testing.expect(cache_controls.cache_disable);

        try testing.expectError(error.InvalidPhysicalAddressWidth, CR3.base(value, 31));
        try testing.expectError(error.InvalidPhysicalAddressWidth, CR3.base(value, 53));
        try testing.expectError(error.PhysicalAddressTooWide, CR3.base(value, 32));
        try testing.expectError(error.ReservedBits, CR3.base(CR3.from(1 << 52), 52));
        try testing.expectError(error.ReservedLowBits, CR3.low(CR3.from(1), false));

        const lam_u48 = CR3.from(1 << 62);
        const lam_u57 = CR3.from(1 << 61);
        const both_lam = CR3.from((1 << 62) | (1 << 61));

        try testing.expectEqual(.u48, try CR3.userLam(lam_u48, true));
        try testing.expectEqual(.u57, try CR3.userLam(lam_u57, true));
        try testing.expectEqual(.u57, try CR3.userLam(both_lam, true));
        try testing.expectError(error.UnsupportedLAM, CR3.userLam(lam_u48, false));
        try testing.expect(CR3.from(1 << 63).no_flush);
    }

    test "CR4 validates paging controls against capabilities" {
        const value = CR4.from((1 << 12) | (1 << 17) | (1 << 28));
        const disabled = CR4.default();
        const four_level_lam = CR4.from(1 << 28);

        try testing.expect(try CR4.pcidEnabled(value, true));
        try testing.expect(try CR4.level5Enabled(value, true));
        try testing.expectEqual(.u57, try CR4.supervisorLam(value, true));
        try testing.expectError(error.UnsupportedPCID, CR4.pcidEnabled(value, false));
        try testing.expectError(error.UnsupportedFiveLevelPaging, CR4.level5Enabled(value, false));
        try testing.expectError(error.UnsupportedLAM, CR4.supervisorLam(value, false));
        try testing.expect(!try CR4.pcidEnabled(disabled, false));
        try testing.expect(!try CR4.level5Enabled(disabled, false));
        try testing.expectEqual(.disabled, try CR4.supervisorLam(disabled, false));
        try testing.expectEqual(.u48, try CR4.supervisorLam(four_level_lam, true));
    }

    test "control replacement preserves fixed, reserved, and unknown snapshot bits" {
        const cr0 = CR0.replace(CR0.default(), .{ .paging = true });
        try testing.expectEqual(@as(u64, (1 << 31) | (1 << 4)), CR0.raw(cr0));
        const cr4 = CR4.replace(CR4.from((1 << 19) | (1 << 26)), .{ .smep = true });
        try testing.expectEqual(@as(u64, (1 << 19) | (1 << 20) | (1 << 26)), CR4.raw(cr4));
        const xcr0 = XCR0.replace(XCR0.default(), .{ .sse = true });
        try testing.expectEqual(@as(u64, 3), XCR0.raw(xcr0));
        const snapshot = XCR0.replace(XCR0.from(1 << 10), .{ .avx = true });
        try testing.expectEqual(@as(u64, (1 << 10) | (1 << 2)), XCR0.raw(snapshot));
    }
};
