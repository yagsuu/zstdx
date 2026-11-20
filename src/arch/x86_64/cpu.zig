const addr = @import("addr");
const layout = @import("layout");

const target = @import("target.zig");

pub const Tsc = struct {
    pub const Reading = struct {
        count: u64,
        aux: u32,
    };

    /// Requires: RDTSC.
    /// Privilege: CPL 0 when CR4.TSD = 1.
    /// Ordering: Non-serializing.
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

    /// Requires: RDTSCP.
    /// Privilege: CPL 0 when CR4.TSD = 1.
    /// Ordering:
    /// - Prior instruction completion and prior-load visibility.
    /// - No prior-store visibility guarantee.
    /// - No subsequent-instruction serialization or compiler memory barrier.
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
            layout.assertLayout(@This(), .{
                .size = 16,
                .alignment = 8,
                .offsets = .{ .context = 0, .address = 8 },
            });
        }
    };

    /// Privilege: CPL 0.
    pub fn invalidatePage(address: addr.VirtAddr) void {
        comptime target.require();
        asm volatile ("invlpg (%[address])"
            :
            : [address] "r" (address.raw()),
            : .{ .memory = true });
    }

    /// Requires: INVPCID.
    /// Privilege: CPL 0.
    /// Inputs:
    /// - Descriptor reserved bits = 0.
    /// - PCID = 0 for address/context scopes when CR4.PCIDE = 0.
    /// - Canonical linear address for address scope.
    pub fn invalidate(scope: Scope, descriptor: *const Descriptor) void {
        comptime target.require();
        asm volatile ("invpcid (%%rdx), %%rax"
            :
            : [scope] "{rax}" (@as(u64, @backingInt(scope))),
              [descriptor] "{rdx}" (descriptor),
            : .{ .memory = true });
    }
};

/// Privilege: CPL 0.
pub fn halt() void {
    comptime target.require();
    asm volatile ("hlt" ::: .{ .memory = true });
}

pub fn pause() void {
    comptime target.require();
    asm volatile ("pause" ::: .{ .memory = true });
}

/// Faults: #BP.
pub fn breakpoint() void {
    comptime target.require();
    asm volatile ("int3" ::: .{ .memory = true });
}
