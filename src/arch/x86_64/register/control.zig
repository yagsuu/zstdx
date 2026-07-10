//! x86_64 control-register access. Spec: docs/specs/arch/x86_64/register.md.

const target = @import("../target.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

/// `CR0` access (`mov rNN, cr0` / `mov cr0, rNN`).
/// Privilege: CPL 0.
pub const cr0 = struct {
    /// Execute `mov rNN, cr0` and return the value.
    /// Privilege: CPL 0.
    pub fn read() u64 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("mov %%cr0, %[ret]"
            : [ret] "=r" (-> u64),
        );
    }

    /// Execute `mov cr0, rNN` writing `value`.
    /// Privilege: CPL 0.
    /// Clobbers: `memory`.
    pub fn write(value: u64) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%cr0"
            :
            : [v] "r" (value),
            : .{ .memory = true });
    }
};

/// `CR2` access. Writes are architecturally legal and are used by exception
/// injection or recovery paths; this wrapper exposes raw access only.
pub const cr2 = struct {
    /// Execute `mov rNN, cr2` and return the page-fault linear address.
    /// Privilege: CPL 0.
    pub fn read() u64 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("mov %%cr2, %[ret]"
            : [ret] "=r" (-> u64),
        );
    }

    /// Execute `mov cr2, rNN` writing `value`.
    /// Privilege: CPL 0.
    /// Clobbers: `memory`.
    pub fn write(value: u64) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%cr2"
            :
            : [v] "r" (value),
            : .{ .memory = true });
    }
};

/// `CR3` access (paging root).
/// Privilege: CPL 0.
/// Notes: `write` may invalidate TLB entries per architectural rules.
pub const cr3 = struct {
    /// Execute `mov rNN, cr3` and return the value.
    /// Privilege: CPL 0.
    pub fn read() u64 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("mov %%cr3, %[ret]"
            : [ret] "=r" (-> u64),
        );
    }

    /// Execute `mov cr3, rNN` writing `value`.
    /// Privilege: CPL 0.
    /// Notes: may invalidate TLB entries per architectural rules.
    /// Clobbers: `memory`.
    pub fn write(value: u64) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%cr3"
            :
            : [v] "r" (value),
            : .{ .memory = true });
    }
};

/// `CR4` access (architectural feature enables).
/// Privilege: CPL 0.
pub const cr4 = struct {
    /// Execute `mov rNN, cr4` and return the value.
    /// Privilege: CPL 0.
    pub fn read() u64 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("mov %%cr4, %[ret]"
            : [ret] "=r" (-> u64),
        );
    }

    /// Execute `mov cr4, rNN` writing `value`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` on reserved-bit violations.
    /// Clobbers: `memory`.
    pub fn write(value: u64) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%cr4"
            :
            : [v] "r" (value),
            : .{ .memory = true });
    }
};

/// `CR8` access (task priority register).
/// Privilege: CPL 0.
pub const cr8 = struct {
    /// Execute `mov rNN, cr8` and return the value.
    /// Privilege: CPL 0.
    pub fn read() u64 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("mov %%cr8, %[ret]"
            : [ret] "=r" (-> u64),
        );
    }

    /// Execute `mov cr8, rNN` writing `value`.
    /// Privilege: CPL 0.
    /// Clobbers: `memory`.
    pub fn write(value: u64) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mov %[v], %%cr8"
            :
            : [v] "r" (value),
            : .{ .memory = true });
    }
};

/// Extended control register 0 access via `xgetbv`/`xsetbv` with `ecx = 0`.
/// Privilege: CPL 0.
/// Requirements: `Cr4.OSXSAVE`.
pub const xcr0 = struct {
    /// Execute `xgetbv` with `ecx = 0` and return the combined `edx:eax` as `u64`.
    /// Requirements: `Cr4.OSXSAVE`.
    pub fn read() u64 {
        if (!supported) @compileError(wrong_target);
        var lo: u32 = undefined;
        var hi: u32 = undefined;
        asm volatile ("xgetbv"
            : [lo] "={eax}" (lo),
              [hi] "={edx}" (hi),
            : [c] "{ecx}" (@as(u32, 0)),
        );
        return (@as(u64, hi) << 32) | @as(u64, lo);
    }

    /// Execute `xsetbv` with `ecx = 0` and `edx:eax` split from `value`.
    /// Privilege: CPL 0.
    /// Requirements: `Cr4.OSXSAVE`.
    /// Faults: `#GP` when bits violate CPU support.
    /// Clobbers: `memory`.
    pub fn write(value: u64) void {
        if (!supported) @compileError(wrong_target);
        const lo: u32 = @truncate(value);
        const hi: u32 = @truncate(value >> 32);
        asm volatile ("xsetbv"
            :
            : [c] "{ecx}" (@as(u32, 0)),
              [lo] "{eax}" (lo),
              [hi] "{edx}" (hi),
            : .{ .memory = true });
    }
};
