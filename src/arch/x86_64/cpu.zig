const std = @import("std");
const addr = @import("addr");

const target = @import("target.zig");

pub const Tsc = struct {
    pub const Reading = struct {
        count: u64,
        aux: u32,
    };

    /// requires RDTSC support; CR4.TSD can restrict access to CPL 0.
    /// does not serialize instructions or memory accesses.
    pub fn read() u64 {
        comptime target.require();

        var lo: u32 = undefined;
        var hi: u32 = undefined;
        asm volatile ("rdtsc"
            : [lo] "={eax}" (lo),
              [hi] "={edx}" (hi),
        );

        return (@as(u64, hi) << 32) | @as(u64, lo);
    }

    /// requires RDTSCP support; CR4.TSD can restrict access to CPL 0.
    /// waits for prior instructions and loads, but not for prior stores to become globally visible.
    /// later instructions can execute before the read completes.
    /// adds no fences or compiler memory barrier.
    pub fn readAux() Reading {
        comptime target.require();

        var lo: u32 = undefined;
        var hi: u32 = undefined;
        var aux: u32 = undefined;
        asm volatile ("rdtscp"
            : [lo] "={eax}" (lo),
              [hi] "={edx}" (hi),
              [aux] "={ecx}" (aux),
        );

        return .{ .count = (@as(u64, hi) << 32) | @as(u64, lo), .aux = aux };
    }
};

pub const Tlb = struct {
    /// address/context exclude global translations; the processor may invalidate more broadly.
    pub const Scope = enum(u2) {
        address = 0,
        context = 1,
        all = 2,
        all_non_global = 3,
    };

    pub const Context = packed struct(u64) {
        pcid: u12 = 0,
        _reserved_12: u52 = 0,
    };

    pub const Descriptor = extern struct {
        context: Context = .{},
        address: addr.VirtAddr,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 16);
            std.debug.assert(@alignOf(@This()) == 8);
            std.debug.assert(@offsetOf(@This(), "context") == 0);
            std.debug.assert(@offsetOf(@This(), "address") == 8);
        }
    };

    /// requires CPL 0.
    pub fn invalidatePage(address: addr.VirtAddr) void {
        comptime target.require();
        asm volatile ("invlpg (%[address])"
            :
            : [address] "r" (address.raw()),
            : .{ .memory = true });
    }

    /// requires CPL 0 and INVPCID support.
    /// descriptor reserved bits must be zero.
    /// address/context require PCID zero when CR4.PCIDE is clear.
    /// address requires a canonical linear address.
    pub fn invalidate(scope: Scope, descriptor: *const Descriptor) void {
        comptime target.require();
        asm volatile ("invpcid (%%rdx), %%rax"
            :
            : [scope] "{rax}" (@as(u64, @intFromEnum(scope))),
              [descriptor] "{rdx}" (descriptor),
            : .{ .memory = true });
    }
};

/// requires CPL 0; execution resumes on a wake event.
pub fn halt() void {
    comptime target.require();
    asm volatile ("hlt" ::: .{ .memory = true });
}

pub fn pause() void {
    comptime target.require();
    asm volatile ("pause" ::: .{ .memory = true });
}

/// raises #BP.
pub fn breakpoint() void {
    comptime target.require();
    asm volatile ("int3" ::: .{ .memory = true });
}
