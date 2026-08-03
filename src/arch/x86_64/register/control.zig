//! x86_64 control-register access. Spec: docs/specs/arch/x86_64/register.md.

const std = @import("std");

const addr = @import("../../../addr.zig");
const target = @import("../target.zig");

/// `CR0` access (`mov rNN, cr0` / `mov cr0, rNN`).
/// Privilege: CPL 0.
pub const cr0 = struct {
    pub const CR0 = packed struct(u64) {
        protection_enable: bool,
        monitor_coprocessor: bool,
        emulation: bool,
        task_switched: bool,
        extension_type: bool,
        numeric_error: bool,
        _reserved0: u10,
        write_protect: bool,
        _reserved1: bool,
        alignment_mask: bool,
        _reserved2: u10,
        not_write_through: bool,
        cache_disable: bool,
        paging: bool,
        _reserved3: u32,

        const Self = @This();

        pub fn init() Self {
            return fromInt(1 << 4);
        }

        pub fn fromInt(value: u64) Self {
            return @bitCast(value);
        }

        pub fn raw(self: Self) u64 {
            return @bitCast(self);
        }

        comptime {
            std.debug.assert(@bitSizeOf(Self) == 64);
            std.debug.assert(@sizeOf(Self) == 8);
        }
    };

    /// Execute `mov rNN, cr0` and return the value.
    /// Privilege: CPL 0.
    pub fn read() CR0 {
        target.ensureSupported();
        return CR0.fromInt(asm volatile ("mov %%cr0, %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// Execute `mov cr0, rNN` writing `value`.
    /// Privilege: CPL 0.
    /// Clobbers: `memory`.
    pub fn write(value: CR0) void {
        target.ensureSupported();
        asm volatile ("mov %[v], %%cr0"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

/// `CR2` access. Writes are architecturally legal and are used by exception
/// injection or recovery paths; this wrapper exposes raw access only.
pub const cr2 = struct {
    pub const CR2 = packed struct(u64) {
        linear_address: u64,

        const Self = @This();

        pub fn init() Self {
            return fromInt(0);
        }

        pub fn fromInt(value: u64) Self {
            return @bitCast(value);
        }

        pub fn raw(self: Self) u64 {
            return @bitCast(self);
        }

        comptime {
            std.debug.assert(@bitSizeOf(Self) == 64);
            std.debug.assert(@sizeOf(Self) == 8);
        }
    };

    /// Execute `mov rNN, cr2` and return the page-fault linear address.
    /// Privilege: CPL 0.
    pub fn read() CR2 {
        target.ensureSupported();
        return CR2.fromInt(asm volatile ("mov %%cr2, %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// Execute `mov cr2, rNN` writing `value`.
    /// Privilege: CPL 0.
    /// Clobbers: `memory`.
    pub fn write(value: CR2) void {
        target.ensureSupported();
        asm volatile ("mov %[v], %%cr2"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

/// `CR3` access (paging root).
/// Privilege: CPL 0.
/// Notes: `write` may invalidate TLB entries per architectural rules.
pub const cr3 = struct {
    pub const CR3 = packed struct(u64) {
        low_bits: u12,
        page_table_base: u40,
        _reserved0: u9,
        lam_u57: bool,
        lam_u48: bool,
        no_flush: bool,

        const Self = @This();

        pub const TableBaseError = error{
            InvalidPhysicalAddressWidth,
            PhysicalAddressTooWide,
            ReservedBits,
        };

        pub const LowError = error{ReservedLowBits};
        pub const LAMError = error{UnsupportedLAM};

        pub const LAMMode = enum {
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
            return fromInt(0);
        }

        pub fn fromInt(value: u64) Self {
            return @bitCast(value);
        }

        pub fn raw(self: Self) u64 {
            return @bitCast(self);
        }

        pub fn tableBaseAddress(
            self: Self,
            physical_address_bits: u8,
        ) TableBaseError!addr.PhysAddr {
            if (physical_address_bits < 32 or physical_address_bits > 52) {
                return error.InvalidPhysicalAddressWidth;
            }
            if (self._reserved0 != 0) return error.ReservedBits;

            const base = @as(u64, self.page_table_base) << @ctz(@as(u64, addr.pages._4kib));
            if ((base >> @intCast(physical_address_bits)) != 0) {
                return error.PhysicalAddressTooWide;
            }

            return addr.PhysAddr.fromInt(base);
        }

        pub fn low(self: Self, pcid_enabled: bool) LowError!Low {
            if (pcid_enabled) return .{ .pcid = self.low_bits };
            if ((self.low_bits & ~@as(u12, 0b1_1000)) != 0) return error.ReservedLowBits;

            return .{ .cache = .{
                .write_through = (self.low_bits & (1 << 3)) != 0,
                .cache_disable = (self.low_bits & (1 << 4)) != 0,
            } };
        }

        pub fn userLAM(self: Self, lam_supported: bool) LAMError!LAMMode {
            const mode: LAMMode = if (self.lam_u57)
                .u57
            else if (self.lam_u48)
                .u48
            else
                .disabled;

            if (mode != .disabled and !lam_supported) return error.UnsupportedLAM;
            return mode;
        }

        comptime {
            std.debug.assert(@bitSizeOf(Self) == 64);
            std.debug.assert(@sizeOf(Self) == 8);
        }
    };

    /// Execute `mov rNN, cr3` and return the value.
    /// Privilege: CPL 0.
    pub fn read() CR3 {
        target.ensureSupported();
        return CR3.fromInt(asm volatile ("mov %%cr3, %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// Execute `mov cr3, rNN` writing `value`.
    /// Privilege: CPL 0.
    /// Notes: may invalidate TLB entries per architectural rules.
    /// Clobbers: `memory`.
    pub fn write(value: CR3) void {
        target.ensureSupported();
        asm volatile ("mov %[v], %%cr3"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

/// `CR4` access (architectural feature enables).
/// Privilege: CPL 0.
pub const cr4 = struct {
    pub const PCIDError = error{UnsupportedPCID};
    pub const Level5Error = error{UnsupportedFiveLevelPaging};
    pub const SupervisorLAMError = error{UnsupportedLAM};

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
        _reserved0: bool,
        fsgsbase_enable: bool,
        pcid_enable: bool,
        osxsave: bool,
        _reserved1: bool,
        smep: bool,
        smap: bool,
        pke: bool,
        cet: bool,
        _reserved2: u3,
        lass: bool,
        lam_supervisor: bool,
        _reserved3: u3,
        fred: bool,
        _reserved4: u31,

        const Self = @This();

        pub fn init() Self {
            return fromInt(0);
        }

        pub fn fromInt(value: u64) Self {
            return @bitCast(value);
        }

        pub fn raw(self: Self) u64 {
            return @bitCast(self);
        }

        pub fn pcidEnabled(self: Self, pcid_supported: bool) PCIDError!bool {
            if (self.pcid_enable and !pcid_supported) return error.UnsupportedPCID;
            return self.pcid_enable;
        }

        pub fn level5Enabled(self: Self, level5_supported: bool) Level5Error!bool {
            if (self.la57 and !level5_supported) return error.UnsupportedFiveLevelPaging;
            return self.la57;
        }

        pub fn supervisorLAM(
            self: Self,
            lam_supported: bool,
        ) SupervisorLAMError!cr3.CR3.LAMMode {
            if (!self.lam_supervisor) return .disabled;
            if (!lam_supported) return error.UnsupportedLAM;
            return if (self.la57) .u57 else .u48;
        }

        comptime {
            std.debug.assert(@bitSizeOf(Self) == 64);
            std.debug.assert(@sizeOf(Self) == 8);
        }
    };

    /// Execute `mov rNN, cr4` and return the value.
    /// Privilege: CPL 0.
    pub fn read() CR4 {
        target.ensureSupported();
        return CR4.fromInt(asm volatile ("mov %%cr4, %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// Execute `mov cr4, rNN` writing `value`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` on reserved-bit violations.
    /// Clobbers: `memory`.
    pub fn write(value: CR4) void {
        target.ensureSupported();
        asm volatile ("mov %[v], %%cr4"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

/// `CR8` access (task priority register).
/// Privilege: CPL 0.
pub const cr8 = struct {
    pub const CR8 = packed struct(u64) {
        task_priority: u4,
        _reserved0: u60,

        const Self = @This();

        pub fn init() Self {
            return fromInt(0);
        }

        pub fn fromInt(value: u64) Self {
            return @bitCast(value);
        }

        pub fn raw(self: Self) u64 {
            return @bitCast(self);
        }

        comptime {
            std.debug.assert(@bitSizeOf(Self) == 64);
            std.debug.assert(@sizeOf(Self) == 8);
        }
    };

    /// Execute `mov rNN, cr8` and return the value.
    /// Privilege: CPL 0.
    pub fn read() CR8 {
        target.ensureSupported();
        return CR8.fromInt(asm volatile ("mov %%cr8, %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// Execute `mov cr8, rNN` writing `value`.
    /// Privilege: CPL 0.
    /// Clobbers: `memory`.
    pub fn write(value: CR8) void {
        target.ensureSupported();
        asm volatile ("mov %[v], %%cr8"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

/// Extended control register 0 access via `xgetbv`/`xsetbv` with `ecx = 0`.
/// Privilege: CPL 0.
/// Requirements: `CR4.osxsave`.
pub const xcr0 = struct {
    pub const XCR0 = packed struct(u64) {
        x87: bool,
        sse: bool,
        avx: bool,
        bndregs: bool,
        bndcsr: bool,
        opmask: bool,
        zmm_hi256: bool,
        hi16_zmm: bool,
        _reserved0: bool,
        pkru: bool,
        _reserved1: u7,
        tile_config: bool,
        tile_data: bool,
        apx: bool,
        _reserved2: u44,

        const Self = @This();

        pub fn init() Self {
            return fromInt(1);
        }

        pub fn fromInt(value: u64) Self {
            return @bitCast(value);
        }

        pub fn raw(self: Self) u64 {
            return @bitCast(self);
        }

        comptime {
            std.debug.assert(@bitSizeOf(Self) == 64);
            std.debug.assert(@sizeOf(Self) == 8);
        }
    };

    /// Execute `xgetbv` with `ecx = 0` and return the combined `edx:eax` as `u64`.
    /// Requirements: `CR4.osxsave`.
    pub fn read() XCR0 {
        target.ensureSupported();

        var lo: u32 = undefined;
        var hi: u32 = undefined;

        asm volatile ("xgetbv"
            : [lo] "={eax}" (lo),
              [hi] "={edx}" (hi),
            : [c] "{ecx}" (@as(u32, 0)),
        );

        return XCR0.fromInt((@as(u64, hi) << 32) | @as(u64, lo));
    }

    /// Execute `xsetbv` with `ecx = 0` and `edx:eax` split from `value.raw()`.
    /// Privilege: CPL 0.
    /// Requirements: `CR4.osxsave`.
    /// Faults: `#GP` when bits violate CPU support.
    /// Clobbers: `memory`.
    pub fn write(value: XCR0) void {
        target.ensureSupported();

        const lo: u32 = @truncate(value.raw());
        const hi: u32 = @truncate(value.raw() >> 32);

        asm volatile ("xsetbv"
            :
            : [c] "{ecx}" (@as(u32, 0)),
              [lo] "{eax}" (lo),
              [hi] "{edx}" (hi),
            : .{ .memory = true });
    }
};
