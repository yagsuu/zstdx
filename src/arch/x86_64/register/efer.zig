//! x86_64 EFER access. See `docs/specs/arch/x86_64/registers.md`.

const std = @import("std");

const MSR = @import("../msr.zig").MSR;

pub const Error = error{UnsupportedExecuteDisable};

/// `IA32_EFER` extended feature enable register.
pub const EFER = packed struct(u64) {
    syscall_enable: bool,
    _reserved0: u7,
    long_mode_enable: bool,
    _reserved1: bool,
    long_mode_active: bool,
    execute_disable_enable: bool,
    secure_virtual_machine_enable: bool,
    long_mode_segment_limit_enable: bool,
    fast_fxsave_fxrstor: bool,
    translation_cache_extension: bool,
    _reserved2: u48,

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

    pub fn executeDisableEnabled(self: Self, execute_disable_supported: bool) Error!bool {
        if (self.execute_disable_enable and !execute_disable_supported) {
            return error.UnsupportedExecuteDisable;
        }
        return self.execute_disable_enable;
    }

    comptime {
        std.debug.assert(@bitSizeOf(Self) == 64);
        std.debug.assert(@sizeOf(Self) == 8);
    }
};

/// Privilege: CPL 0.
pub fn read() EFER {
    return EFER.fromInt(MSR.efer.read());
}

/// Privilege: CPL 0.
/// Clobbers: `memory`.
pub fn write(value: EFER) void {
    MSR.efer.write(value.raw());
}
