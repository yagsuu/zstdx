//! x86_64 descriptor-register access. Spec: docs/specs/arch/x86_64/register.md.

const std = @import("std");

const Table = enum(u1) { gdt, ldt };
const SelectorKind = enum { tr, ldtr };

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

pub const gdtr = struct {
    pub const GDTR = extern struct {
        limit: u16,
        base: u64 align(2),

        const Self = @This();

        pub fn init() Self {
            return .{ .limit = 0, .base = 0 };
        }

        pub const alignment: usize = 2;

        comptime {
            std.debug.assert(@sizeOf(Self) == 10);
            std.debug.assert(@alignOf(Self) == alignment);
            std.debug.assert(@offsetOf(Self, "limit") == 0);
            std.debug.assert(@offsetOf(Self, "base") == 2);
        }
    };
    /// Execute `lgdt [ptr]`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0.
    /// Clobbers: `memory`.
    pub fn write(value: GDTR) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("lgdt %[ptr]"
            :
            : [ptr] "*m" (&value),
            : .{ .memory = true });
    }

    /// Execute `sgdt` and return the current GDTR.
    /// Privilege: CPU/OS policy at CPL > 0.
    /// Clobbers: `memory`.
    pub fn read() GDTR {
        if (!supported) @compileError(wrong_target);

        var value: GDTR = undefined;
        asm volatile ("sgdt %[ptr]"
            : [ptr] "=m" (value),
            :
            : .{ .memory = true });

        return value;
    }
};

pub const idtr = struct {
    pub const IDTR = extern struct {
        limit: u16,
        base: u64 align(2),

        const Self = @This();

        pub fn init() Self {
            return .{ .limit = 0, .base = 0 };
        }

        pub const alignment: usize = 2;

        comptime {
            std.debug.assert(@sizeOf(Self) == 10);
            std.debug.assert(@alignOf(Self) == alignment);
            std.debug.assert(@offsetOf(Self, "limit") == 0);
            std.debug.assert(@offsetOf(Self, "base") == 2);
        }
    };
    /// Execute `lidt [ptr]`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0.
    /// Clobbers: `memory`.
    pub fn write(value: IDTR) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("lidt %[ptr]"
            :
            : [ptr] "*m" (&value),
            : .{ .memory = true });
    }

    /// Execute `sidt` and return the current IDTR.
    /// Privilege: CPU/OS policy at CPL > 0.
    /// Clobbers: `memory`.
    pub fn read() IDTR {
        if (!supported) @compileError(wrong_target);

        var value: IDTR = undefined;
        asm volatile ("sidt %[ptr]"
            : [ptr] "=m" (value),
            :
            : .{ .memory = true });

        return value;
    }
};

pub const tr = struct {
    pub const TR = selector(.tr);
    /// Execute `ltr selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or invalid selector state.
    /// Clobbers: `memory`.
    pub fn write(value: TR) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("ltr %[sel]"
            :
            : [sel] "r" (value.raw()),
            : .{ .memory = true });
    }

    /// Execute `str` and return the current task-register selector.
    /// Privilege: CPU/OS policy at CPL > 0.
    pub fn read() TR {
        if (!supported) @compileError(wrong_target);
        return TR.fromInt(asm volatile ("str %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }
};

pub const ldtr = struct {
    pub const LDTR = selector(.ldtr);
    /// Execute `lldt selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or invalid/non-present LDT descriptor.
    /// Clobbers: `memory`.
    pub fn write(value: LDTR) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("lldt %[sel]"
            :
            : [sel] "r" (value.raw()),
            : .{ .memory = true });
    }

    /// Execute `sldt` and return the current LDT selector.
    /// Privilege: CPU/OS policy at CPL > 0.
    /// Clobbers: registers only.
    pub fn read() LDTR {
        if (!supported) @compileError(wrong_target);
        return LDTR.fromInt(asm volatile ("sldt %[ret]"
            : [ret] "=r" (-> u16),
        ));
    }
};
