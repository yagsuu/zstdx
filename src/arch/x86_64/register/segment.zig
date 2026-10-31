//! x86_64 segment-register access. See `docs/specs/arch/x86_64/registers.md`.

const std = @import("std");
const target = @import("../target.zig");

const Table = enum(u1) {
    gdt,
    ldt,

    pub fn init() Table {
        return .gdt;
    }
};

const SelectorKind = enum {
    cs,
    ds,
    es,
    fs,
    gs,
    ss,
    tr,
    ldtr,
};

fn Selector(comptime kind: SelectorKind) type {
    return packed struct(u16) {
        rpl: u2,
        table: Table,
        index: u13,

        const Self = @This();

        pub fn init() Self {
            return fromInt(0);
        }

        pub fn fromInt(value: u16) Self {
            return @bitCast(value);
        }

        pub fn raw(self: Self) u16 {
            return @bitCast(self);
        }

        comptime {
            _ = kind;
            std.debug.assert(@bitSizeOf(Self) == 16);
            std.debug.assert(@sizeOf(Self) == 2);
        }
    };
}

pub const cs = struct {
    pub const CS = Selector(.cs);

    /// Privilege: unprivileged.
    pub fn read() CS {
        comptime target.require();
        return CS.fromInt(asm volatile ("mov %%cs, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Far-return trampoline to load `cs`.
    /// Effects: pushes selector and next-instruction RIP; `lretq` consumes both.
    /// Clobbers: `memory`.
    pub fn writeFarReturn(value: CS) void {
        comptime target.require();
        _ = asm volatile (
            \\pushq %[sel]
            \\leaq 1f(%%rip), %[tmp]
            \\pushq %[tmp]
            \\lretq
            \\1:
            : [tmp] "=&r" (-> u64),
            : [sel] "r" (@as(u64, value.raw())),
            : .{ .memory = true });
    }
};

pub const ds = struct {
    pub const DS = Selector(.ds);

    /// Privilege: unprivileged.
    pub fn read() DS {
        comptime target.require();
        return DS.fromInt(asm volatile ("mov %%ds, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: DS) void {
        comptime target.require();
        asm volatile ("mov %[v], %%ds"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

pub const es = struct {
    pub const ES = Selector(.es);

    /// Privilege: unprivileged.
    pub fn read() ES {
        comptime target.require();
        return ES.fromInt(asm volatile ("mov %%es, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: ES) void {
        comptime target.require();
        asm volatile ("mov %[v], %%es"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

pub const fs = struct {
    pub const FS = Selector(.fs);

    /// Privilege: unprivileged.
    pub fn read() FS {
        comptime target.require();
        return FS.fromInt(asm volatile ("mov %%fs, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: FS) void {
        comptime target.require();
        asm volatile ("mov %[v], %%fs"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

pub const gs = struct {
    pub const GS = Selector(.gs);

    /// Privilege: unprivileged.
    pub fn read() GS {
        comptime target.require();
        return GS.fromInt(asm volatile ("mov %%gs, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: GS) void {
        comptime target.require();
        asm volatile ("mov %[v], %%gs"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

pub const ss = struct {
    pub const SS = Selector(.ss);

    /// Privilege: unprivileged.
    pub fn read() SS {
        comptime target.require();
        return SS.fromInt(asm volatile ("mov %%ss, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: SS) void {
        comptime target.require();
        asm volatile ("mov %[v], %%ss"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

/// FS-base access through `rdfsbase` / `wrfsbase`.
/// Requirements: FSGSBASE support and `CR4.fsgsbase_enable`.
/// Faults: `#UD` when unsupported.
pub const fs_base = struct {
    pub const FSBase = packed struct(u64) {
        base: u64,

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
    /// Reads the current FS base with `rdfsbase`.
    pub fn read() FSBase {
        comptime target.require();
        return FSBase.fromInt(asm volatile ("rdfsbase %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// Clobbers: `memory`.
    pub fn write(value: FSBase) void {
        comptime target.require();
        asm volatile ("wrfsbase %[v]"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

/// GS-base access through `rdgsbase` / `wrgsbase`.
/// Requirements: FSGSBASE support and `CR4.fsgsbase_enable`.
/// Faults: `#UD` when unsupported.
pub const gs_base = struct {
    pub const GSBase = packed struct(u64) {
        base: u64,

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
    /// Reads the current GS base with `rdgsbase`.
    pub fn read() GSBase {
        comptime target.require();
        return GSBase.fromInt(asm volatile ("rdgsbase %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// Clobbers: `memory`.
    pub fn write(value: GSBase) void {
        comptime target.require();
        asm volatile ("wrgsbase %[v]"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }

    /// Privilege: CPL 0.
    /// Effects: exchanges `GS.base` with `IA32_KERNEL_GS_BASE`.
    /// Clobbers: `memory`.
    pub fn swap() void {
        comptime target.require();
        asm volatile ("swapgs" ::: .{ .memory = true });
    }
};
