//! x86_64 segment-register access. Spec: docs/specs/arch/x86_64/register.md.

const std = @import("std");

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

fn selector(comptime kind: SelectorKind) type {
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

const target = @import("../target.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

pub const cs = struct {
    pub const CS = selector(.cs);
    /// Execute `mov rNN, cs` and return the current selector.
    /// Privilege: unprivileged.
    pub fn read() CS {
        if (!supported) @compileError(wrong_target);
        return CS.fromInt(asm volatile ("mov %%cs, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Far-return trampoline to load `cs`.
    /// Effects: pushes selector and next-instruction RIP; `lretq` consumes both.
    /// Clobbers: `memory`.
    pub fn writeFarReturn(value: CS) void {
        if (!supported) @compileError(wrong_target);
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
    pub const DS = selector(.ds);
    /// Execute `mov rNN, ds` and return the current selector.
    /// Privilege: unprivileged.
    pub fn read() DS {
        if (!supported) @compileError(wrong_target);
        return DS.fromInt(asm volatile ("mov %%ds, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Execute `mov ds, rNN` loading `selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: DS) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%ds"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

pub const es = struct {
    pub const ES = selector(.es);
    /// Execute `mov rNN, es` and return the current selector.
    /// Privilege: unprivileged.
    pub fn read() ES {
        if (!supported) @compileError(wrong_target);
        return ES.fromInt(asm volatile ("mov %%es, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Execute `mov es, rNN` loading `selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: ES) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%es"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

pub const fs = struct {
    pub const FS = selector(.fs);
    /// Execute `mov rNN, fs` and return the current selector.
    /// Privilege: unprivileged.
    pub fn read() FS {
        if (!supported) @compileError(wrong_target);
        return FS.fromInt(asm volatile ("mov %%fs, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Execute `mov fs, rNN` loading `selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: FS) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%fs"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

pub const gs = struct {
    pub const GS = selector(.gs);
    /// Execute `mov rNN, gs` and return the current selector.
    /// Privilege: unprivileged.
    pub fn read() GS {
        if (!supported) @compileError(wrong_target);
        return GS.fromInt(asm volatile ("mov %%gs, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Execute `mov gs, rNN` loading `selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: GS) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%gs"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }
};

pub const ss = struct {
    pub const SS = selector(.ss);
    /// Execute `mov rNN, ss` and return the current selector.
    /// Privilege: unprivileged.
    pub fn read() SS {
        if (!supported) @compileError(wrong_target);
        return SS.fromInt(asm volatile ("mov %%ss, %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }

    /// Execute `mov ss, rNN` loading `selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(value: SS) void {
        if (!supported) @compileError(wrong_target);
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
    /// Read the current FS base with `rdfsbase`.
    pub fn read() FSBase {
        if (!supported) @compileError(wrong_target);
        return FSBase.fromInt(asm volatile ("rdfsbase %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// Write the FS base with `wrfsbase`.
    /// Clobbers: `memory`.
    pub fn write(value: FSBase) void {
        if (!supported) @compileError(wrong_target);
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
    /// Read the current GS base with `rdgsbase`.
    pub fn read() GSBase {
        if (!supported) @compileError(wrong_target);
        return GSBase.fromInt(asm volatile ("rdgsbase %[ret]"
            : [ret] "=r" (-> u64),
        ));
    }

    /// Write the GS base with `wrgsbase`.
    /// Clobbers: `memory`.
    pub fn write(value: GSBase) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("wrgsbase %[v]"
            :
            : [v] "r" (value.raw()),
            : .{ .memory = true });
    }

    /// Execute `swapgs`.
    /// Privilege: CPL 0.
    /// Effects: exchanges `GS.base` with `IA32_KERNEL_GS_BASE`.
    /// Clobbers: `memory`.
    pub fn swap() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("swapgs" ::: .{ .memory = true });
    }
};
