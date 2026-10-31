const std = @import("std");

const msr = @import("../msr.zig");

pub const EFER = packed struct(u64) {
    syscall_enable: bool,
    _reserved_1: u7,
    long_mode_enable: bool,
    _reserved_9: bool,
    long_mode_active: bool,
    execute_disable_enable: bool,
    secure_virtual_machine_enable: bool,
    long_mode_segment_limit_enable: bool,
    fast_fxsave_fxrstor: bool,
    translation_cache_extension: bool,
    _reserved_16: bool,
    _unknown_17: u2,
    _reserved_19: bool,
    _unknown_20: u2,
    _reserved_22: u42,

    const Self = @This();

    pub const Error = error{UnsupportedExecuteDisable};

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
        return Self.from(msr.read(.IA32_EFER));
    }

    /// requires cpl 0; clobbers memory.
    pub fn write(self: Self) void {
        msr.write(.IA32_EFER, self.raw());
    }

    pub fn executeDisableEnabled(self: Self, supported: bool) Error!bool {
        if (self.execute_disable_enable and !supported) {
            return error.UnsupportedExecuteDisable;
        }
        return self.execute_disable_enable;
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "execute-disable capability validation preserves raw bits" {
        const value = EFER.from(0xa5f3_5ca9_3d7e_1c42 | (1 << 11));
        const disabled = EFER.init();

        try testing.expectEqual(@as(u64, 0xa5f3_5ca9_3d7e_1c42 | (1 << 11)), value.raw());
        try testing.expect(try value.executeDisableEnabled(true));
        try testing.expectError(error.UnsupportedExecuteDisable, value.executeDisableEnabled(false));
        try testing.expect(!try disabled.executeDisableEnabled(false));
    }
};
