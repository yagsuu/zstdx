//! x86_64 debug-register access. See `docs/specs/arch/x86_64/register.md`.

const std = @import("std");

const target = @import("../target.zig");

const DebugAddress = struct {
    fn forIndex(comptime index: u3) type {
        return packed struct(u64) {
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
                _ = index;
                std.debug.assert(@bitSizeOf(Self) == 64);
                std.debug.assert(@sizeOf(Self) == 8);
            }
        };
    }
};

pub const dr0 = struct {
    pub const DR0 = DebugAddress.forIndex(0);

    pub fn read() DR0 {
        return readDebug(DR0, "dr0");
    }

    pub fn write(value: DR0) void {
        writeDebug(DR0, "dr0", value);
    }
};

pub const dr1 = struct {
    pub const DR1 = DebugAddress.forIndex(1);

    pub fn read() DR1 {
        return readDebug(DR1, "dr1");
    }

    pub fn write(value: DR1) void {
        writeDebug(DR1, "dr1", value);
    }
};

pub const dr2 = struct {
    pub const DR2 = DebugAddress.forIndex(2);

    pub fn read() DR2 {
        return readDebug(DR2, "dr2");
    }

    pub fn write(value: DR2) void {
        writeDebug(DR2, "dr2", value);
    }
};

pub const dr3 = struct {
    pub const DR3 = DebugAddress.forIndex(3);

    pub fn read() DR3 {
        return readDebug(DR3, "dr3");
    }

    pub fn write(value: DR3) void {
        writeDebug(DR3, "dr3", value);
    }
};

pub const dr4 = struct {
    pub const DR4 = DebugAddress.forIndex(4);

    pub fn read() DR4 {
        return readDebug(DR4, "dr4");
    }

    pub fn write(value: DR4) void {
        writeDebug(DR4, "dr4", value);
    }
};

pub const dr5 = struct {
    pub const DR5 = DebugAddress.forIndex(5);

    pub fn read() DR5 {
        return readDebug(DR5, "dr5");
    }

    pub fn write(value: DR5) void {
        writeDebug(DR5, "dr5", value);
    }
};

pub const dr6 = struct {
    pub const DR6 = packed struct(u64) {
        br0: bool,
        br1: bool,
        br2: bool,
        br3: bool,
        _reserved0: u7,
        bus_lock_detect: bool,
        _reserved1: bool,
        debug_register_access: bool,
        single_step: bool,
        task_switch: bool,
        restricted_transactional_memory: bool,
        _reserved2: u47,

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

    pub fn read() DR6 {
        return readDebug(DR6, "dr6");
    }

    pub fn write(value: DR6) void {
        writeDebug(DR6, "dr6", value);
    }
};

pub const dr7 = struct {
    pub const Breakpoint = packed struct(u4) {
        condition: u2,
        length: u2,

        const Self = @This();

        pub fn init() Self {
            return fromInt(0);
        }

        pub fn fromInt(value: u4) Self {
            return @bitCast(value);
        }

        pub fn raw(self: Self) u4 {
            return @bitCast(self);
        }

        comptime {
            std.debug.assert(@bitSizeOf(Self) == 4);
            std.debug.assert(@sizeOf(Self) == 1);
        }
    };

    pub const DR7 = packed struct(u64) {
        local_0: bool,
        global_0: bool,
        local_1: bool,
        global_1: bool,
        local_2: bool,
        global_2: bool,
        local_3: bool,
        global_3: bool,
        local_exact: bool,
        global_exact: bool,
        fixed_one: bool,
        _reserved0: u2,
        general_detect: bool,
        _reserved1: u2,
        br0: Breakpoint,
        br1: Breakpoint,
        br2: Breakpoint,
        br3: Breakpoint,
        _reserved2: u32,

        const Self = @This();

        pub fn init() Self {
            return fromInt(1 << 10);
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

    pub fn read() DR7 {
        return readDebug(DR7, "dr7");
    }

    pub fn write(value: DR7) void {
        writeDebug(DR7, "dr7", value);
    }
};

fn readDebug(comptime T: type, comptime name: []const u8) T {
    target.ensureSupported();
    return T.fromInt(asm volatile ("mov %%" ++ name ++ ", %[ret]"
        : [ret] "=r" (-> u64),
    ));
}

fn writeDebug(comptime T: type, comptime name: []const u8, value: T) void {
    target.ensureSupported();
    asm volatile ("mov %[v], %%" ++ name
        :
        : [v] "r" (value.raw()),
        : .{ .memory = true });
}
