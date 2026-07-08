//! x86_64 MSR primitive. Spec: docs/specs/arch/x86_64/base.md.

const target = @import("target.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

pub const Msr = enum(u32) {
    _,

    pub fn fromInt(value: u32) Msr {
        return @enumFromInt(value);
    }

    pub fn raw(self: Msr) u32 {
        return @intFromEnum(self);
    }

    /// Execute `rdmsr` against `self` and return the combined `edx:eax` as `u64`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` on unimplemented MSRs.
    /// Clobbers: `memory`.
    pub fn read(self: Msr) u64 {
        if (!supported) @compileError(wrong_target);
        var lo: u32 = undefined;
        var hi: u32 = undefined;
        asm volatile ("rdmsr"
            : [lo] "={eax}" (lo),
              [hi] "={edx}" (hi),
            : [idx] "{ecx}" (@intFromEnum(self)),
            : .{ .memory = true });
        return (@as(u64, hi) << 32) | @as(u64, lo);
    }

    /// Execute `wrmsr` against `self` with `edx:eax` split from `value`.
    /// Privilege: CPL 0.
    /// Faults: `#GP` on unimplemented MSRs or reserved-bit violations.
    /// Clobbers: `memory`.
    pub fn write(self: Msr, value: u64) void {
        if (!supported) @compileError(wrong_target);
        const lo: u32 = @truncate(value);
        const hi: u32 = @truncate(value >> 32);
        asm volatile ("wrmsr"
            :
            : [idx] "{ecx}" (@intFromEnum(self)),
              [lo] "{eax}" (lo),
              [hi] "{edx}" (hi),
            : .{ .memory = true });
    }
};
