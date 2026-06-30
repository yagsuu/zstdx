//! x86_64 architecture primitives. Spec: docs/specs/arch/x86_64.md.
//!
//! Thin, inline-asm-only wrappers for x86_64 instruction primitives. The
//! module is `@import`-able on any target; bodies that emit inline assembly
//! are gated with `if (!supported) @compileError(...);` so non-x86_64 builds
//! see compile errors only at use sites, never at import.

const std = @import("std");
const builtin = @import("builtin");

/// True iff the build target is x86_64.
pub const supported: bool = builtin.cpu.arch == .x86_64;

const wrong_target = "stdx.arch.x86_64: this operation requires an x86_64 target";

/// Strong port-number value type covering the entire x86 16-bit I/O space.
pub const Port = enum(u16) {
    _,

    pub fn fromInt(value: u16) Port {
        return @enumFromInt(value);
    }

    pub fn raw(self: Port) u16 {
        return @intFromEnum(self);
    }

    pub fn in8(self: Port) u8 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("inb %[port], %[ret]"
            : [ret] "={al}" (-> u8),
            : [port] "{dx}" (@intFromEnum(self)),
            : .{ .memory = true });
    }

    pub fn in16(self: Port) u16 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("inw %[port], %[ret]"
            : [ret] "={ax}" (-> u16),
            : [port] "{dx}" (@intFromEnum(self)),
            : .{ .memory = true });
    }

    pub fn in32(self: Port) u32 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("inl %[port], %[ret]"
            : [ret] "={eax}" (-> u32),
            : [port] "{dx}" (@intFromEnum(self)),
            : .{ .memory = true });
    }

    pub fn out8(self: Port, value: u8) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("outb %[value], %[port]"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [value] "{al}" (value),
            : .{ .memory = true });
    }

    pub fn out16(self: Port, value: u16) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("outw %[value], %[port]"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [value] "{ax}" (value),
            : .{ .memory = true });
    }

    pub fn out32(self: Port, value: u32) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("outl %[value], %[port]"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [value] "{eax}" (value),
            : .{ .memory = true });
    }

    pub fn inSlice8(self: Port, dst: []u8) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("rep insb"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [dst] "{rdi}" (dst.ptr),
              [count] "{rcx}" (dst.len),
            : .{ .rcx = true, .rdi = true, .memory = true });
    }

    pub fn inSlice16(self: Port, dst: []u16) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("rep insw"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [dst] "{rdi}" (dst.ptr),
              [count] "{rcx}" (dst.len),
            : .{ .rcx = true, .rdi = true, .memory = true });
    }

    pub fn inSlice32(self: Port, dst: []u32) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("rep insl"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [dst] "{rdi}" (dst.ptr),
              [count] "{rcx}" (dst.len),
            : .{ .rcx = true, .rdi = true, .memory = true });
    }

    pub fn outSlice8(self: Port, src: []const u8) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("rep outsb"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [src] "{rsi}" (src.ptr),
              [count] "{rcx}" (src.len),
            : .{ .rcx = true, .rsi = true, .memory = true });
    }

    pub fn outSlice16(self: Port, src: []const u16) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("rep outsw"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [src] "{rsi}" (src.ptr),
              [count] "{rcx}" (src.len),
            : .{ .rcx = true, .rsi = true, .memory = true });
    }

    pub fn outSlice32(self: Port, src: []const u32) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("rep outsl"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [src] "{rsi}" (src.ptr),
              [count] "{rcx}" (src.len),
            : .{ .rcx = true, .rsi = true, .memory = true });
    }
};

/// Classic legacy short-delay: `out 0x80, al` with `al = 0`.
pub fn ioWait() void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("outb %[v], $0x80"
        :
        : [v] "{al}" (@as(u8, 0)),
        : .{ .memory = true });
}

pub const Cpuid = struct {
    pub const Result = struct {
        eax: u32,
        ebx: u32,
        ecx: u32,
        edx: u32,
    };

    /// Named CPUID leaves used inside zstdx. Callers needing a vendor- or
    /// model-specific leaf pass `@enumFromInt(value)`; the tag is open.
    pub const Leaf = enum(u32) {
        max_basic = 0x0,
        feature_info = 0x1,
        structured_extended_features = 0x7,
        max_extended = 0x8000_0000,
        extended_feature_bits = 0x8000_0001,
        _,
    };

    pub fn leaf(which: Leaf) Result {
        if (!supported) @compileError(wrong_target);
        return subleaf(which, 0);
    }

    pub fn subleaf(which: Leaf, sub: u32) Result {
        if (!supported) @compileError(wrong_target);
        var a: u32 = undefined;
        var b: u32 = undefined;
        var c: u32 = undefined;
        var d: u32 = undefined;
        asm volatile ("cpuid"
            : [a] "={eax}" (a),
              [b] "={ebx}" (b),
              [c] "={ecx}" (c),
              [d] "={edx}" (d),
            : [a_in] "{eax}" (@intFromEnum(which)),
              [c_in] "{ecx}" (sub),
        );
        return .{ .eax = a, .ebx = b, .ecx = c, .edx = d };
    }

    pub fn maxBasicLeaf() u32 {
        if (!supported) @compileError(wrong_target);
        return leaf(.max_basic).eax;
    }

    pub fn maxExtendedLeaf() u32 {
        if (!supported) @compileError(wrong_target);
        return leaf(.max_extended).eax;
    }
};

pub const Msr = enum(u32) {
    _,

    pub fn fromInt(value: u32) Msr {
        return @enumFromInt(value);
    }

    pub fn raw(self: Msr) u32 {
        return @intFromEnum(self);
    }

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

// IA32 MSR addresses used by the FsBase/GsBase MSR fallback.
const IA32_FS_BASE: u32 = 0xC000_0100;
const IA32_GS_BASE: u32 = 0xC000_0101;

pub const ControlRegister = struct {
    pub const Cr0 = struct {
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%cr0, %[ret]"
                : [ret] "=r" (-> u64),
            );
        }
        pub fn write(value: u64) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%cr0"
                :
                : [v] "r" (value),
                : .{ .memory = true });
        }
    };

    pub const Cr2 = struct {
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%cr2, %[ret]"
                : [ret] "=r" (-> u64),
            );
        }
    };

    pub const Cr3 = struct {
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%cr3, %[ret]"
                : [ret] "=r" (-> u64),
            );
        }
        pub fn write(value: u64) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%cr3"
                :
                : [v] "r" (value),
                : .{ .memory = true });
        }
    };

    pub const Cr4 = struct {
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%cr4, %[ret]"
                : [ret] "=r" (-> u64),
            );
        }
        pub fn write(value: u64) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%cr4"
                :
                : [v] "r" (value),
                : .{ .memory = true });
        }
    };

    pub const Cr8 = struct {
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%cr8, %[ret]"
                : [ret] "=r" (-> u64),
            );
        }
        pub fn write(value: u64) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%cr8"
                :
                : [v] "r" (value),
                : .{ .memory = true });
        }
    };

    pub const Xcr0 = struct {
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
};

pub const Rflags = struct {
    pub fn read() u64 {
        if (!supported) @compileError(wrong_target);
        return asm volatile (
            \\pushfq
            \\popq %[ret]
            : [ret] "=r" (-> u64),
        );
    }

    pub fn write(value: u64) void {
        if (!supported) @compileError(wrong_target);
        asm volatile (
            \\pushq %[v]
            \\popfq
            :
            : [v] "r" (value),
            : .{ .memory = true, .cc = true });
    }
};

pub const Interrupts = struct {
    pub fn enable() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("sti" ::: .{ .memory = true });
    }

    pub fn disable() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("cli" ::: .{ .memory = true });
    }

    /// Whether the `IF` bit in `RFLAGS` is set. Unprivileged.
    pub fn enabled() bool {
        if (!supported) @compileError(wrong_target);
        return (Rflags.read() & (1 << 9)) != 0;
    }
};

pub const Cpu = struct {
    pub fn halt() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("hlt" ::: .{ .memory = true });
    }

    pub fn pause() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("pause");
    }

    pub fn breakpoint() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("int3" ::: .{ .memory = true });
    }
};

pub const Descriptor = struct {
    /// Architectural pseudo-descriptor used by lgdt/sgdt/lidt/sidt: 16-bit
    /// limit followed by a 64-bit base, packed with no padding.
    ///
    /// The spec mandates exactly 10 bytes and no inter-field padding; that
    /// requires `extern struct` with the base field marked `align(2)` so the
    /// host alignment of `u64` does not insert 6 bytes of padding.
    pub const Pointer = extern struct {
        limit: u16,
        base: u64 align(2),

        comptime {
            std.debug.assert(@sizeOf(Pointer) == 10);
            std.debug.assert(@offsetOf(Pointer, "limit") == 0);
            std.debug.assert(@offsetOf(Pointer, "base") == 2);
        }
    };

    pub const Gdt = struct {
        pub fn load(ptr: *const Pointer) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("lgdt %[ptr]"
                :
                : [ptr] "*m" (ptr),
                : .{ .memory = true });
        }

        pub fn store() Pointer {
            if (!supported) @compileError(wrong_target);
            var p: Pointer = undefined;
            asm volatile ("sgdt %[ptr]"
                : [ptr] "=m" (p),
                :
                : .{ .memory = true });
            return p;
        }
    };

    pub const Idt = struct {
        pub fn load(ptr: *const Pointer) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("lidt %[ptr]"
                :
                : [ptr] "*m" (ptr),
                : .{ .memory = true });
        }

        pub fn store() Pointer {
            if (!supported) @compileError(wrong_target);
            var p: Pointer = undefined;
            asm volatile ("sidt %[ptr]"
                : [ptr] "=m" (p),
                :
                : .{ .memory = true });
            return p;
        }
    };

    pub const TaskRegister = struct {
        pub fn load(selector: u16) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("ltr %[sel]"
                :
                : [sel] "r" (selector),
                : .{ .memory = true });
        }

        pub fn store() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("str %[ret]"
                : [ret] "=r" (-> u16),
            );
        }
    };
};

pub const Segment = struct {
    pub const Cs = struct {
        pub fn read() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%cs, %[ret]"
                : [ret] "=r" (-> u16),
            );
        }

        /// Far-return trampoline to load `cs`: pushes selector and the
        /// next-instruction RIP, then `lretq` consumes them.
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

    pub const Ds = struct {
        pub fn read() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%ds, %[ret]"
                : [ret] "=r" (-> u16),
            );
        }
        pub fn write(selector: u16) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%ds"
                :
                : [v] "r" (selector),
                : .{ .memory = true });
        }
    };

    pub const Es = struct {
        pub fn read() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%es, %[ret]"
                : [ret] "=r" (-> u16),
            );
        }
        pub fn write(selector: u16) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%es"
                :
                : [v] "r" (selector),
                : .{ .memory = true });
        }
    };

    pub const Fs = struct {
        pub fn read() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%fs, %[ret]"
                : [ret] "=r" (-> u16),
            );
        }
        pub fn write(selector: u16) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%fs"
                :
                : [v] "r" (selector),
                : .{ .memory = true });
        }
    };

    pub const Gs = struct {
        pub fn read() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%gs, %[ret]"
                : [ret] "=r" (-> u16),
            );
        }
        pub fn write(selector: u16) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%gs"
                :
                : [v] "r" (selector),
                : .{ .memory = true });
        }
    };

    pub const Ss = struct {
        pub fn read() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%ss, %[ret]"
                : [ret] "=r" (-> u16),
            );
        }
        pub fn write(selector: u16) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%ss"
                :
                : [v] "r" (selector),
                : .{ .memory = true });
        }
    };

    pub const FsBase = struct {
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            if (fsgsbaseSupported()) {
                return asm volatile ("rdfsbase %[ret]"
                    : [ret] "=r" (-> u64),
                );
            }
            return Msr.fromInt(IA32_FS_BASE).read();
        }
        pub fn write(value: u64) void {
            if (!supported) @compileError(wrong_target);
            if (fsgsbaseSupported()) {
                asm volatile ("wrfsbase %[v]"
                    :
                    : [v] "r" (value),
                    : .{ .memory = true });
                return;
            }
            Msr.fromInt(IA32_FS_BASE).write(value);
        }
    };

    pub const GsBase = struct {
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            if (fsgsbaseSupported()) {
                return asm volatile ("rdgsbase %[ret]"
                    : [ret] "=r" (-> u64),
                );
            }
            return Msr.fromInt(IA32_GS_BASE).read();
        }
        pub fn write(value: u64) void {
            if (!supported) @compileError(wrong_target);
            if (fsgsbaseSupported()) {
                asm volatile ("wrgsbase %[v]"
                    :
                    : [v] "r" (value),
                    : .{ .memory = true });
                return;
            }
            Msr.fromInt(IA32_GS_BASE).write(value);
        }
    };

    pub fn swapGs() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("swapgs" ::: .{ .memory = true });
    }
};

/// Process-lifetime probe cache for `CPUID.(EAX=7,ECX=0):EBX[bit 0]`
/// (`FSGSBASE`). Values: `0` = unprobed, `1` = false, `2` = true.
/// Loads and stores use `.monotonic` ordering; the publish race is benign
/// because every probing thread computes the same answer from CPUID.
var fsgsbase_cache = std.atomic.Value(u8).init(0);

fn fsgsbaseSupported() bool {
    if (!supported) @compileError(wrong_target);

    const cached = fsgsbase_cache.load(.monotonic);
    if (cached != 0) return cached == 2;

    const max_basic = Cpuid.maxBasicLeaf();
    const supports = max_basic >= 7 and (Cpuid.subleaf(.structured_extended_features, 0).ebx & 1) != 0;
    fsgsbase_cache.store(if (supports) 2 else 1, .monotonic);
    return supports;
}

pub const Fence = struct {
    pub fn lfence() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("lfence" ::: .{ .memory = true });
    }

    pub fn sfence() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("sfence" ::: .{ .memory = true });
    }

    pub fn mfence() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mfence" ::: .{ .memory = true });
    }
};

pub const Cache = struct {
    /// L1 cache-line size in bytes, derived from `CPUID.1:EBX[15:8] * 8`.
    /// Falls back to 64 when CPUID does not advertise a size.
    pub fn lineSize() usize {
        if (!supported) @compileError(wrong_target);
        const ebx = Cpuid.leaf(.feature_info).ebx;
        const clflush_qwords: u32 = (ebx >> 8) & 0xff;
        if (clflush_qwords == 0) return 64;
        return @as(usize, clflush_qwords) * 8;
    }

    pub fn flush(addr: usize) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("clflush (%[addr])"
            :
            : [addr] "r" (addr),
            : .{ .memory = true });
    }

    pub fn flushOptimized(addr: usize) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("clflushopt (%[addr])"
            :
            : [addr] "r" (addr),
            : .{ .memory = true });
    }

    pub fn writeBack(addr: usize) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("clwb (%[addr])"
            :
            : [addr] "r" (addr),
            : .{ .memory = true });
    }

    pub fn flushRange(ptr: [*]const u8, len: usize) void {
        if (!supported) @compileError(wrong_target);
        rangeWalk(ptr, len, flush);
    }

    pub fn writeBackRange(ptr: [*]const u8, len: usize) void {
        if (!supported) @compileError(wrong_target);
        rangeWalk(ptr, len, writeBack);
    }

    pub fn writeBackInvalidate() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("wbinvd" ::: .{ .memory = true });
    }

    pub fn invalidate() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("invd" ::: .{ .memory = true });
    }
};

/// Walk `[ptr, ptr + len)` in `Cache.lineSize()` steps, invoking `op` on the
/// line-aligned address of every covered line.
fn rangeWalk(ptr: [*]const u8, len: usize, comptime op: fn (usize) void) void {
    if (len == 0) return;
    const line = Cache.lineSize();
    const start = @intFromPtr(ptr);
    const end = start + len;
    var cursor = start & ~(line - 1);
    while (cursor < end) : (cursor += line) {
        op(cursor);
    }
}

pub const Privilege = struct {
    /// Bits 0-1 of the `cs` segment selector hold the architectural RPL/CPL,
    /// so truncating `cs` to `u2` extracts the current privilege level.
    /// Unprivileged.
    pub fn currentLevel() u2 {
        if (!supported) @compileError(wrong_target);
        return @truncate(Segment.Cs.read());
    }
};
