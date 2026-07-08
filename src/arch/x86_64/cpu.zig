//! x86_64 CPU instructions. Spec: docs/specs/arch/x86_64/cpu.md.

const std = @import("std");

const target = @import("target.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

/// Execute `hlt`.
/// Privilege: CPL 0.
/// Effects: halts the CPU until the next interrupt.
/// Clobbers: `memory`.
pub fn halt() void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("hlt" ::: .{ .memory = true });
}

/// Execute `pause`.
/// Privilege: unprivileged.
/// Clobbers: `memory`.
pub fn pause() void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("pause" ::: .{ .memory = true });
}

/// Execute `int3`.
/// Privilege: unprivileged.
/// Faults: raises `#BP`; behavior depends on the installed handler.
/// Clobbers: `memory`.
pub fn breakpoint() void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("int3" ::: .{ .memory = true });
}

/// TSC (time-stamp counter) access via `rdtsc` / `rdtscp`. See also
/// `docs/specs/arch/x86_64/extensions.md`.
pub const tsc = struct {
    /// Combined 64-bit TSC value paired with the `IA32_TSC_AUX` low
    /// 32 bits that `rdtscp` returns in one instruction.
    pub const Reading = struct {
        tsc: u64,
        aux: u32,
    };

    /// Execute `rdtsc` and return the combined `edx:eax` as `u64`.
    /// Privilege: unprivileged unless `Cr4.TSD` blocks userspace.
    /// Faults: `#GP` at CPL > 0 when `Cr4.TSD` is set.
    /// Ordering: not serializing.
    /// Clobbers: registers only.
    pub fn read() u64 {
        if (!supported) @compileError(wrong_target);
        var lo: u32 = undefined;
        var hi: u32 = undefined;
        asm volatile ("rdtsc"
            : [lo] "={eax}" (lo),
              [hi] "={edx}" (hi),
        );
        return (@as(u64, hi) << 32) | @as(u64, lo);
    }

    /// Execute `rdtscp` and return `Reading{ tsc, aux }`.
    /// Privilege: unprivileged unless `Cr4.TSD` blocks userspace.
    /// Requirements: `RDTSCP` support.
    /// Faults: `#UD` when unsupported; `#GP` at CPL > 0 when `Cr4.TSD` is set.
    /// Ordering: partially serializing on prior instructions.
    /// Clobbers: `eax`, `ecx`, `edx`.
    pub fn readSerializing() Reading {
        if (!supported) @compileError(wrong_target);
        var lo: u32 = undefined;
        var hi: u32 = undefined;
        var aux: u32 = undefined;
        asm volatile ("rdtscp"
            : [lo] "={eax}" (lo),
              [hi] "={edx}" (hi),
              [aux] "={ecx}" (aux),
        );
        return .{ .tsc = (@as(u64, hi) << 32) | @as(u64, lo), .aux = aux };
    }
};

/// Per-address and PCID-scoped TLB invalidation. See also
/// `docs/specs/arch/x86_64/extensions.md`.
pub const tlb = struct {
    /// `invpcid` invalidation kind. Backing values match the immediate
    /// value the CPU expects in the type register.
    pub const InvpcidKind = enum(u2) {
        individual_address = 0,
        single_context = 1,
        all_including_globals = 2,
        all_excluding_globals = 3,
    };

    /// 128-bit `invpcid` descriptor. Explicit `align(16)` satisfies the
    /// instruction's operand-alignment requirement; reserved fields
    /// default to zero because Intel documents non-zero reserved bits
    /// as producing `#GP`.
    pub const InvpcidDescriptor = extern struct {
        pcid: u16 align(16),
        _reserved_pcid_high: u16 = 0,
        _reserved: u32 = 0,
        linear_address: u64,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 16);
            std.debug.assert(@alignOf(@This()) == 16);
            std.debug.assert(@offsetOf(@This(), "pcid") == 0);
            std.debug.assert(@offsetOf(@This(), "linear_address") == 8);
        }

        pub const alignment: usize = 16;
    };

    /// Execute `invlpg [addr]`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` at CPL > 0.
    /// Clobbers: `memory`.
    pub fn invalidatePage(addr: usize) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("invlpg (%[addr])"
            :
            : [addr] "r" (addr),
            : .{ .memory = true });
    }

    /// Execute `invpcid rax, [rdx]` with `rax = @intFromEnum(kind)`
    /// and `rdx = descriptor`.
    /// Privilege: CPL 0.
    /// Requirements: `INVPCID` support.
    /// Faults: `#GP` at CPL > 0; `#UD` when unsupported.
    /// Clobbers: `memory`.
    pub fn invalidatePcid(kind: InvpcidKind, descriptor: *const InvpcidDescriptor) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("invpcid (%%rdx), %%rax"
            :
            : [kind] "{rax}" (@as(u64, @intFromEnum(kind))),
              [desc] "{rdx}" (descriptor),
            : .{ .memory = true });
    }
};
