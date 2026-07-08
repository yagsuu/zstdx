//! x86_64 descriptor-register access. Spec: docs/specs/arch/x86_64/register.md.

const std = @import("std");

const target = @import("../target.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

pub const Pointer = extern struct {
    limit: u16,
    base: u64 align(2),

    pub const alignment: usize = 2;

    comptime {
        std.debug.assert(@sizeOf(Pointer) == 10);
        std.debug.assert(@offsetOf(Pointer, "limit") == 0);
        std.debug.assert(@offsetOf(Pointer, "base") == 2);
    }
};

pub const gdtr = struct {
    /// Execute `lgdt [ptr]`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0.
    /// Clobbers: `memory`.
    pub fn load(ptr: *const Pointer) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("lgdt %[ptr]"
            :
            : [ptr] "*m" (ptr),
            : .{ .memory = true });
    }

    /// Execute `sgdt` into `ptr`.
    /// Privilege: CPU/OS policy at CPL > 0.
    /// Clobbers: `memory`.
    pub fn store(ptr: *Pointer) void {
        if (!supported) @compileError(wrong_target);
        var p: Pointer = undefined;
        asm volatile ("sgdt %[ptr]"
            : [ptr] "=m" (p),
            :
            : .{ .memory = true });
        ptr.* = p;
    }
};

pub const idtr = struct {
    /// Execute `lidt [ptr]`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0.
    /// Clobbers: `memory`.
    pub fn load(ptr: *const Pointer) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("lidt %[ptr]"
            :
            : [ptr] "*m" (ptr),
            : .{ .memory = true });
    }

    /// Execute `sidt` into `ptr`.
    /// Privilege: CPU/OS policy at CPL > 0.
    /// Clobbers: `memory`.
    pub fn store(ptr: *Pointer) void {
        if (!supported) @compileError(wrong_target);
        var p: Pointer = undefined;
        asm volatile ("sidt %[ptr]"
            : [ptr] "=m" (p),
            :
            : .{ .memory = true });
        ptr.* = p;
    }
};

pub const tr = struct {
    /// Execute `ltr selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or invalid selector state.
    /// Clobbers: `memory`.
    pub fn load(selector: u16) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("ltr %[sel]"
            :
            : [sel] "r" (selector),
            : .{ .memory = true });
    }

    /// Execute `str` and return the current task-register selector.
    /// Privilege: CPU/OS policy at CPL > 0.
    pub fn store() u16 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("str %[ret]"
            : [ret] "=r" (-> u16),
        );
    }
};

pub const ldtr = struct {
    /// Execute `lldt selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or invalid/non-present LDT descriptor.
    /// Clobbers: `memory`.
    pub fn load(selector: u16) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("lldt %[sel]"
            :
            : [sel] "r" (selector),
            : .{ .memory = true });
    }

    /// Execute `sldt` and return the current LDT selector.
    /// Privilege: CPU/OS policy at CPL > 0.
    /// Clobbers: registers only.
    pub fn store() u16 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("sldt %[ret]"
            : [ret] "=r" (-> u16),
        );
    }
};
