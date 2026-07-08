//! x86_64 segment-register access. Spec: docs/specs/arch/x86_64/register.md.

const target = @import("../target.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

/// Code-segment selector access.
/// Privilege: `read` is unprivileged; loading `cs` requires a far return.
pub const cs = struct {
    /// Execute `mov rNN, cs` and return the current selector.
    /// Privilege: unprivileged.
    pub fn read() u16 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("mov %%cs, %[ret]"
            : [ret] "=r" (-> u16),
        );
    }

    /// Far-return trampoline to load `cs`.
    /// Effects: pushes selector and next-instruction RIP; `lretq` consumes both.
    /// Clobbers: `memory`.
    pub fn writeFarReturn(selector: u16) void {
        if (!supported) @compileError(wrong_target);
        _ = asm volatile (
            \\pushq %[sel]
            \\leaq 1f(%%rip), %[tmp]
            \\pushq %[tmp]
            \\lretq
            \\1:
            : [tmp] "=&r" (-> u64),
            : [sel] "r" (@as(u64, selector)),
            : .{ .memory = true });
    }
};

/// `DS` selector access.
pub const ds = struct {
    /// Execute `mov rNN, ds` and return the current selector.
    /// Privilege: unprivileged.
    pub fn read() u16 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("mov %%ds, %[ret]"
            : [ret] "=r" (-> u16),
        );
    }
    /// Execute `mov ds, rNN` loading `selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(selector: u16) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%ds"
            :
            : [v] "r" (selector),
            : .{ .memory = true });
    }
};

/// `ES` selector access.
pub const es = struct {
    /// Execute `mov rNN, es` and return the current selector.
    /// Privilege: unprivileged.
    pub fn read() u16 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("mov %%es, %[ret]"
            : [ret] "=r" (-> u16),
        );
    }
    /// Execute `mov es, rNN` loading `selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(selector: u16) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%es"
            :
            : [v] "r" (selector),
            : .{ .memory = true });
    }
};

/// `FS` selector access.
pub const fs = struct {
    /// Execute `mov rNN, fs` and return the current selector.
    /// Privilege: unprivileged.
    pub fn read() u16 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("mov %%fs, %[ret]"
            : [ret] "=r" (-> u16),
        );
    }
    /// Execute `mov fs, rNN` loading `selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(selector: u16) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%fs"
            :
            : [v] "r" (selector),
            : .{ .memory = true });
    }
};

/// `GS` selector access.
pub const gs = struct {
    /// Execute `mov rNN, gs` and return the current selector.
    /// Privilege: unprivileged.
    pub fn read() u16 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("mov %%gs, %[ret]"
            : [ret] "=r" (-> u16),
        );
    }
    /// Execute `mov gs, rNN` loading `selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(selector: u16) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%gs"
            :
            : [v] "r" (selector),
            : .{ .memory = true });
    }
};

/// `SS` selector access.
pub const ss = struct {
    /// Execute `mov rNN, ss` and return the current selector.
    /// Privilege: unprivileged.
    pub fn read() u16 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("mov %%ss, %[ret]"
            : [ret] "=r" (-> u16),
        );
    }
    /// Execute `mov ss, rNN` loading `selector`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0 or architectural selector violations.
    /// Clobbers: `memory`.
    pub fn write(selector: u16) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%ss"
            :
            : [v] "r" (selector),
            : .{ .memory = true });
    }
};

/// FS-base access through `rdfsbase` / `wrfsbase`.
/// Requirements: FSGSBASE support and `Cr4.FSGSBASE`.
/// Faults: `#UD` when unsupported.
pub const fs_base = struct {
    /// Read the current FS base with `rdfsbase`.
    pub fn read() u64 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("rdfsbase %[ret]"
            : [ret] "=r" (-> u64),
        );
    }
    /// Write the FS base with `wrfsbase`.
    /// Clobbers: `memory`.
    pub fn write(value: u64) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("wrfsbase %[v]"
            :
            : [v] "r" (value),
            : .{ .memory = true });
    }
};

/// GS-base access through `rdgsbase` / `wrgsbase`.
/// Requirements: FSGSBASE support and `Cr4.FSGSBASE`.
/// Faults: `#UD` when unsupported.
pub const gs_base = struct {
    /// Read the current GS base with `rdgsbase`.
    pub fn read() u64 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("rdgsbase %[ret]"
            : [ret] "=r" (-> u64),
        );
    }
    /// Write the GS base with `wrgsbase`.
    /// Clobbers: `memory`.
    pub fn write(value: u64) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("wrgsbase %[v]"
            :
            : [v] "r" (value),
            : .{ .memory = true });
    }
};

/// Execute `swapgs`.
/// Privilege: CPL 0.
/// Effects: exchanges `GS.base` with `IA32_KERNEL_GS_BASE`.
/// Clobbers: `memory`.
pub fn swapGs() void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("swapgs" ::: .{ .memory = true });
}
