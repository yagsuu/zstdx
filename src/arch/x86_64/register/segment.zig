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
        target.ensureSupported();
        return CS.fromInt(asm volatile ("mov %%cs, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Far-return trampoline to load `cs`.
    /// Effects: pushes selector and next-instruction RIP; `lretq` consumes both.
    /// Clobbers: `memory`.
    pub fn writeFarReturn(value: CS) void {
        target.ensureSupported();
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
        target.ensureSupported();
        return DS.fromInt(asm volatile ("mov %%ds, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: DS) void {
        target.ensureSupported();
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
        target.ensureSupported();
        return ES.fromInt(asm volatile ("mov %%es, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: ES) void {
        target.ensureSupported();
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
        target.ensureSupported();
        return FS.fromInt(asm volatile ("mov %%fs, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: FS) void {
        target.ensureSupported();
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
        target.ensureSupported();
        return GS.fromInt(asm volatile ("mov %%gs, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: GS) void {
        target.ensureSupported();
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
        target.ensureSupported();
        return SS.fromInt(asm volatile ("mov %%ss, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: SS) void {
        target.ensureSupported();
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
        target.ensureSupported();
        return FSBase.fromInt(asm volatile ("rdfsbase %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// Clobbers: `memory`.
    pub fn write(value: FSBase) void {
        target.ensureSupported();
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
        target.ensureSupported();
        return GSBase.fromInt(asm volatile ("rdgsbase %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// Clobbers: `memory`.
    pub fn write(value: GSBase) void {
        target.ensureSupported();
        asm volatile ("wrgsbase %[v]"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }

    /// Privilege: CPL 0.
    /// Effects: exchanges `GS.base` with `IA32_KERNEL_GS_BASE`.
    /// Clobbers: `memory`.
    pub fn swap() void {
        target.ensureSupported();
        asm volatile ("swapgs" ::: .{ .memory = true });
    }
};
