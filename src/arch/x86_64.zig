//! x86_64 architecture primitives. See docs/specs/arch/x86_64/base.md,
//! docs/specs/arch/x86_64/extensions.md, docs/specs/arch/x86_64/cpuid.md.

const std = @import("std");
const builtin = @import("builtin");

const debug = @import("../core/debug.zig");

/// True if the build target is x86_64. The module is `@import`-able on any
/// target; bodies that emit inline assembly gate on `if (!supported)
/// @compileError(wrong_target);` so non-x86_64 builds see compile errors only
/// at use sites, never at import.
pub const supported: bool = builtin.cpu.arch == .x86_64;

const wrong_target = "stdx.arch.x86_64: this operation requires an x86_64 target";

/// Strong port-number value type covering the entire x86 16-bit I/O space.
pub const Port = enum(u16) {
    _,

    /// Wrap a raw `u16` port number as a strong `Port` value. Compiles on any
    /// target.
    pub fn fromInt(value: u16) Port {
        return @enumFromInt(value);
    }

    /// Return the underlying `u16` port number. Compiles on any target.
    pub fn raw(self: Port) u16 {
        return @intFromEnum(self);
    }

    /// Execute `inb dx, al` and return the byte. Privileged per IOPL/TSS I/O
    /// permission bitmap; raises `#GP` when access is denied. `memory` clobber.
    pub fn in8(self: Port) u8 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("inb %[port], %[ret]"
            : [ret] "={al}" (-> u8),
            : [port] "{dx}" (@intFromEnum(self)),
            : .{ .memory = true });
    }

    /// Execute `inw dx, ax` and return the word. Privileged per IOPL/TSS; raises
    /// `#GP` on denied access. `memory` clobber.
    pub fn in16(self: Port) u16 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("inw %[port], %[ret]"
            : [ret] "={ax}" (-> u16),
            : [port] "{dx}" (@intFromEnum(self)),
            : .{ .memory = true });
    }

    /// Execute `inl dx, eax` and return the dword. Privileged per IOPL/TSS;
    /// raises `#GP` on denied access. `memory` clobber.
    pub fn in32(self: Port) u32 {
        if (!supported) @compileError(wrong_target);
        return asm volatile ("inl %[port], %[ret]"
            : [ret] "={eax}" (-> u32),
            : [port] "{dx}" (@intFromEnum(self)),
            : .{ .memory = true });
    }

    /// Execute `outb al, dx` writing `value`. Privileged per IOPL/TSS; raises
    /// `#GP` on denied access. `memory` clobber.
    pub fn out8(self: Port, value: u8) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("outb %[value], %[port]"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [value] "{al}" (value),
            : .{ .memory = true });
    }

    /// Execute `outw ax, dx` writing `value`. Privileged per IOPL/TSS; raises
    /// `#GP` on denied access. `memory` clobber.
    pub fn out16(self: Port, value: u16) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("outw %[value], %[port]"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [value] "{ax}" (value),
            : .{ .memory = true });
    }

    /// Execute `outl eax, dx` writing `value`. Privileged per IOPL/TSS; raises
    /// `#GP` on denied access. `memory` clobber.
    pub fn out32(self: Port, value: u32) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("outl %[value], %[port]"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [value] "{eax}" (value),
            : .{ .memory = true });
    }

    /// Execute `rep insb` reading `dst.len` bytes from the port into `dst`.
    /// Requires `DF` clear and slice alignment. Clobbers `rcx`, `rdi`, `memory`.
    pub fn inSlice8(self: Port, dst: []u8) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("rep insb"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [dst] "{rdi}" (dst.ptr),
              [count] "{rcx}" (dst.len),
            : .{ .rcx = true, .rdi = true, .memory = true });
    }

    /// Execute `rep insw` reading `dst.len` 16-bit words into `dst`. Requires
    /// `DF` clear and slice alignment. Clobbers `rcx`, `rdi`, `memory`.
    pub fn inSlice16(self: Port, dst: []u16) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("rep insw"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [dst] "{rdi}" (dst.ptr),
              [count] "{rcx}" (dst.len),
            : .{ .rcx = true, .rdi = true, .memory = true });
    }

    /// Execute `rep insd` reading `dst.len` 32-bit dwords into `dst`. Requires
    /// `DF` clear and slice alignment. Clobbers `rcx`, `rdi`, `memory`.
    pub fn inSlice32(self: Port, dst: []u32) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("rep insl"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [dst] "{rdi}" (dst.ptr),
              [count] "{rcx}" (dst.len),
            : .{ .rcx = true, .rdi = true, .memory = true });
    }

    /// Execute `rep outsb` writing `src.len` bytes to the port. Requires `DF`
    /// clear and slice alignment. Clobbers `rcx`, `rsi`, `memory`.
    pub fn outSlice8(self: Port, src: []const u8) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("rep outsb"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [src] "{rsi}" (src.ptr),
              [count] "{rcx}" (src.len),
            : .{ .rcx = true, .rsi = true, .memory = true });
    }

    /// Execute `rep outsw` writing `src.len` 16-bit words. Requires `DF` clear
    /// and slice alignment. Clobbers `rcx`, `rsi`, `memory`.
    pub fn outSlice16(self: Port, src: []const u16) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("rep outsw"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [src] "{rsi}" (src.ptr),
              [count] "{rcx}" (src.len),
            : .{ .rcx = true, .rsi = true, .memory = true });
    }

    /// Execute `rep outsd` writing `src.len` 32-bit dwords. Requires `DF` clear
    /// and slice alignment. Clobbers `rcx`, `rsi`, `memory`.
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

/// Raw `cpuid` access by leaf and subleaf. Unprivileged at any CPL.
pub const Cpuid = struct {
    /// Snapshot of the four CPUID output registers from a single `cpuid` call.
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

    /// Execute `cpuid` with `ecx = 0` against `which` and return the four
    /// output registers. Unprivileged.
    pub fn leaf(which: Leaf) Result {
        if (!supported) @compileError(wrong_target);
        return subleaf(which, 0);
    }

    /// Execute `cpuid` with `eax = which` and `ecx = sub`, returning the four
    /// output registers. Unprivileged.
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

    /// Return `leaf(.max_basic).eax`, the highest basic CPUID leaf supported by
    /// the running CPU. Unprivileged.
    pub fn maxBasicLeaf() u32 {
        if (!supported) @compileError(wrong_target);
        return leaf(.max_basic).eax;
    }

    /// Return `leaf(.max_extended).eax`, the highest extended CPUID leaf
    /// supported by the running CPU. Unprivileged.
    pub fn maxExtendedLeaf() u32 {
        if (!supported) @compileError(wrong_target);
        return leaf(.max_extended).eax;
    }

    /// CPU vendor decoded from CPUID leaf 0 `EBX:EDX:ECX`. Unrecognized
    /// vendor strings map to `.unknown`.
    pub const Vendor = enum {
        intel,
        amd,
        via,
        cyrix,
        transmeta,
        centaur,
        unknown,
    };

    /// Displayed family/model/stepping decoded from CPUID leaf 1 EAX. `eax`
    /// preserves the raw register for callers who need the type bits
    /// (`EAX[13:12]`) or full processor-signature reconstruction.
    pub const Version = struct {
        family: u12,
        model: u8,
        stepping: u4,
        eax: u32,
    };

    /// Comptime helper: return `true` when any field prefixed `_reserved_`
    /// on the packed-struct value is non-zero. Shared by every mask's
    /// `hasReserved`.
    fn maskHasReserved(comptime T: type, self: T) bool {
        inline for (@typeInfo(T).@"struct".fields) |f| {
            if (comptime std.mem.startsWith(u8, f.name, "_reserved_")) {
                if (@field(self, f.name) != 0) return true;
            }
        }
        return false;
    }

    /// CPUID leaf 1 EDX feature mask. Named bits follow Intel SDM Vol.2
    /// Chapter 3. Reserved bit positions are `_reserved_N: u1 = 0` so
    /// `@bitCast(u32, mask)` round-trips.
    pub const BasicFeatureEdx = packed struct(u32) {
        fpu: bool,
        vme: bool,
        de: bool,
        pse: bool,
        tsc: bool,
        msr: bool,
        pae: bool,
        mce: bool,
        cx8: bool,
        apic: bool,
        _reserved_10: u1 = 0,
        sep: bool,
        mtrr: bool,
        pge: bool,
        mca: bool,
        cmov: bool,
        pat: bool,
        pse36: bool,
        psn: bool,
        clflush: bool,
        _reserved_20: u1 = 0,
        ds: bool,
        acpi: bool,
        mmx: bool,
        fxsr: bool,
        sse: bool,
        sse2: bool,
        ss: bool,
        htt: bool,
        tm: bool,
        _reserved_30: u1 = 0,
        pbe: bool,

        comptime {
            std.debug.assert(@bitSizeOf(@This()) == 32);
        }

        pub fn hasReserved(self: BasicFeatureEdx) bool {
            return maskHasReserved(BasicFeatureEdx, self);
        }
    };

    /// CPUID leaf 1 ECX feature mask.
    pub const BasicFeatureEcx = packed struct(u32) {
        sse3: bool,
        pclmulqdq: bool,
        dtes64: bool,
        monitor: bool,
        ds_cpl: bool,
        vmx: bool,
        smx: bool,
        eist: bool,
        tm2: bool,
        ssse3: bool,
        cnxt_id: bool,
        sdbg: bool,
        fma: bool,
        cmpxchg16b: bool,
        xtpr: bool,
        pdcm: bool,
        _reserved_16: u1 = 0,
        pcid: bool,
        dca: bool,
        sse4_1: bool,
        sse4_2: bool,
        x2apic: bool,
        movbe: bool,
        popcnt: bool,
        tsc_deadline: bool,
        aesni: bool,
        xsave: bool,
        osxsave: bool,
        avx: bool,
        f16c: bool,
        rdrand: bool,
        hypervisor: bool,

        comptime {
            std.debug.assert(@bitSizeOf(@This()) == 32);
        }

        pub fn hasReserved(self: BasicFeatureEcx) bool {
            return maskHasReserved(BasicFeatureEcx, self);
        }
    };

    /// CPUID leaf 7 subleaf 0 EBX feature mask.
    pub const StructuredEbx = packed struct(u32) {
        fsgsbase: bool,
        tsc_adjust: bool,
        sgx: bool,
        bmi1: bool,
        hle: bool,
        avx2: bool,
        fdp_excptn_only: bool,
        smep: bool,
        bmi2: bool,
        erms: bool,
        invpcid: bool,
        rtm: bool,
        rdt_m: bool,
        fpu_cs_ds_deprecated: bool,
        mpx: bool,
        rdt_a: bool,
        avx512f: bool,
        avx512dq: bool,
        rdseed: bool,
        adx: bool,
        smap: bool,
        avx512_ifma: bool,
        _reserved_22: u1 = 0,
        clflushopt: bool,
        clwb: bool,
        intel_pt: bool,
        avx512pf: bool,
        avx512er: bool,
        avx512cd: bool,
        sha: bool,
        avx512bw: bool,
        avx512vl: bool,

        comptime {
            std.debug.assert(@bitSizeOf(@This()) == 32);
        }

        pub fn hasReserved(self: StructuredEbx) bool {
            return maskHasReserved(StructuredEbx, self);
        }
    };

    /// CPUID leaf 7 subleaf 0 ECX feature mask.
    pub const StructuredEcx = packed struct(u32) {
        prefetchwt1: bool,
        avx512_vbmi: bool,
        umip: bool,
        pku: bool,
        ospke: bool,
        waitpkg: bool,
        avx512_vbmi2: bool,
        cet_ss: bool,
        gfni: bool,
        vaes: bool,
        vpclmulqdq: bool,
        avx512_vnni: bool,
        avx512_bitalg: bool,
        tme_en: bool,
        avx512_vpopcntdq: bool,
        _reserved_15: u1 = 0,
        la57: bool,
        mawau: u5,
        rdpid: bool,
        kl: bool,
        bus_lock_detect: bool,
        cldemote: bool,
        _reserved_26: u1 = 0,
        movdiri: bool,
        movdir64b: bool,
        enqcmd: bool,
        sgx_lc: bool,
        pks: bool,

        comptime {
            std.debug.assert(@bitSizeOf(@This()) == 32);
        }

        pub fn hasReserved(self: StructuredEcx) bool {
            return maskHasReserved(StructuredEcx, self);
        }
    };

    /// CPUID leaf 7 subleaf 0 EDX feature mask.
    pub const StructuredEdx = packed struct(u32) {
        _reserved_0: u2 = 0,
        avx512_4vnniw: bool,
        avx512_4fmaps: bool,
        fast_short_rep_mov: bool,
        uintr: bool,
        _reserved_6: u2 = 0,
        avx512_vp2intersect: bool,
        srbds_ctrl: bool,
        md_clear: bool,
        rtm_always_abort: bool,
        _reserved_12: u1 = 0,
        rtm_force_abort: bool,
        serialize: bool,
        hybrid: bool,
        tsxldtrk: bool,
        _reserved_17: u1 = 0,
        pconfig: bool,
        architectural_lbrs: bool,
        cet_ibt: bool,
        _reserved_21: u1 = 0,
        amx_bf16: bool,
        avx512_fp16: bool,
        amx_tile: bool,
        amx_int8: bool,
        ibrs_ibpb: bool,
        stibp: bool,
        l1d_flush: bool,
        ia32_arch_capabilities: bool,
        ia32_core_capabilities: bool,
        ssbd: bool,

        comptime {
            std.debug.assert(@bitSizeOf(@This()) == 32);
        }

        pub fn hasReserved(self: StructuredEdx) bool {
            return maskHasReserved(StructuredEdx, self);
        }
    };

    /// CPUID leaf `0x80000001` EDX feature mask.
    pub const ExtendedFeatureEdx = packed struct(u32) {
        _reserved_0: u11 = 0,
        syscall: bool,
        _reserved_12: u8 = 0,
        nx: bool,
        _reserved_21: u5 = 0,
        pdpe1gb: bool,
        rdtscp: bool,
        _reserved_28: u1 = 0,
        lm: bool,
        _reserved_30: u2 = 0,

        comptime {
            std.debug.assert(@bitSizeOf(@This()) == 32);
        }

        pub fn hasReserved(self: ExtendedFeatureEdx) bool {
            return maskHasReserved(ExtendedFeatureEdx, self);
        }
    };

    /// CPUID leaf `0x80000001` ECX feature mask.
    pub const ExtendedFeatureEcx = packed struct(u32) {
        lahf_lm: bool,
        cmp_legacy: bool,
        svm: bool,
        extapic: bool,
        cr8_legacy: bool,
        abm: bool,
        sse4a: bool,
        misalignsse: bool,
        three_dnow_prefetch: bool,
        osvw: bool,
        ibs: bool,
        xop: bool,
        skinit: bool,
        wdt: bool,
        _reserved_14: u1 = 0,
        lwp: bool,
        fma4: bool,
        tce: bool,
        _reserved_18: u4 = 0,
        topoext: bool,
        perfctr_core: bool,
        perfctr_nb: bool,
        _reserved_25: u7 = 0,

        comptime {
            std.debug.assert(@bitSizeOf(@This()) == 32);
        }

        pub fn hasReserved(self: ExtendedFeatureEcx) bool {
            return maskHasReserved(ExtendedFeatureEcx, self);
        }
    };

    /// CPUID leaf 1 feature-mask bundle.
    pub const BasicFeatures = struct {
        edx: BasicFeatureEdx,
        ecx: BasicFeatureEcx,
    };

    /// CPUID leaf 7 subleaf 0 feature-mask bundle.
    pub const StructuredFeatures = struct {
        ebx: StructuredEbx,
        ecx: StructuredEcx,
        edx: StructuredEdx,
    };

    /// CPUID leaf `0x80000001` feature-mask bundle.
    pub const ExtendedFeatures = struct {
        edx: ExtendedFeatureEdx,
        ecx: ExtendedFeatureEcx,
    };

    /// One-shot combined feature-mask bundle covering every mask this spec
    /// decodes.
    pub const Features = struct {
        basic: BasicFeatures,
        structured: StructuredFeatures,
        extended: ExtendedFeatures,
    };

    /// Cache-topology decoder for CPUID leaf 4 deterministic-cache subleaves.
    pub const Cache = struct {
        /// Cache-type field decoded from `EAX[4:0]`. Open enum: values 4..31
        /// (Intel-reserved at spec time) round-trip via the `_` sentinel.
        pub const Kind = enum(u5) {
            null = 0,
            data = 1,
            instruction = 2,
            unified = 3,
            _,
        };

        /// One leaf-4 cache descriptor. `eax`..`edx` retain the raw register
        /// values for callers who need bits beyond the decoded fields.
        pub const Descriptor = struct {
            level: u3,
            kind: Kind,
            line_size: u32,
            partitions: u32,
            ways: u32,
            sets: u32,
            fully_associative: bool,
            self_initializing: bool,
            eax: u32,
            ebx: u32,
            ecx: u32,
            edx: u32,
        };

        /// Iterator over successive leaf-4 subleaves. `next()` returns `null`
        /// when the cache-type field is `0`, signalling the end of the walk.
        pub const Iterator = struct {
            index: u32,

            pub fn next(self: *Iterator) ?Cpuid.Cache.Descriptor {
                if (!supported) @compileError(wrong_target);
                if (maxBasicLeaf() < 4) return null;
                const r = subleaf(@as(Leaf, @enumFromInt(4)), self.index);
                const raw_kind: u5 = @truncate(r.eax);
                if (raw_kind == 0) return null;
                self.index += 1;
                return .{
                    .level = @truncate(r.eax >> 5),
                    .kind = @as(Cpuid.Cache.Kind, @enumFromInt(raw_kind)),
                    .line_size = (r.ebx & 0xFFF) + 1,
                    .partitions = ((r.ebx >> 12) & 0x3FF) + 1,
                    .ways = ((r.ebx >> 22) & 0x3FF) + 1,
                    .sets = r.ecx + 1,
                    .fully_associative = ((r.eax >> 9) & 1) != 0,
                    .self_initializing = ((r.eax >> 8) & 1) != 0,
                    .eax = r.eax,
                    .ebx = r.ebx,
                    .ecx = r.ecx,
                    .edx = r.edx,
                };
            }
        };
    };

    /// Physical/linear/guest-physical address widths from leaf `0x80000008`.
    pub const AddressSizes = struct {
        physical_bits: u8,
        linear_bits: u8,
        guest_physical_bits: u8,
    };

    /// Return the CPU vendor decoded from CPUID leaf 0.
    pub fn vendor() Vendor {
        if (!supported) @compileError(wrong_target);
        const s = vendorString();
        if (std.mem.eql(u8, &s, "GenuineIntel")) return .intel;
        if (std.mem.eql(u8, &s, "AuthenticAMD")) return .amd;
        if (std.mem.eql(u8, &s, "VIA VIA VIA ")) return .via;
        if (std.mem.eql(u8, &s, "CentaurHauls")) return .centaur;
        if (std.mem.eql(u8, &s, "CyrixInstead")) return .cyrix;
        if (std.mem.eql(u8, &s, "GenuineTMx86")) return .transmeta;
        if (std.mem.eql(u8, &s, "TransmetaCPU")) return .transmeta;
        return .unknown;
    }

    /// Raw 12-byte vendor string. Bytes 0..3 = EBX, 4..7 = EDX, 8..11 = ECX
    /// per Intel SDM Vol.2 Appendix A.
    pub fn vendorString() [12]u8 {
        if (!supported) @compileError(wrong_target);
        const r = leaf(.max_basic);
        var out: [12]u8 = @splat(0);
        std.mem.writeInt(u32, out[0..4], r.ebx, .little);
        std.mem.writeInt(u32, out[4..8], r.edx, .little);
        std.mem.writeInt(u32, out[8..12], r.ecx, .little);
        return out;
    }

    /// Decode displayed family/model/stepping from CPUID leaf 1 EAX per
    /// Intel SDM Vol.2 Chapter 3 / AMD APM Vol.3 §CPUID Fn0000_0001_EAX.
    pub fn version() Version {
        if (!supported) @compileError(wrong_target);
        const eax = leaf(.feature_info).eax;
        const base_family: u4 = @truncate(eax >> 8);
        const base_model: u4 = @truncate(eax >> 4);
        const stepping: u4 = @truncate(eax);
        const ext_family: u8 = @truncate(eax >> 20);
        const ext_model: u4 = @truncate(eax >> 16);

        var family: u12 = base_family;
        if (base_family == 0xF) family = @as(u12, base_family) + ext_family;

        var model: u8 = base_model;
        if (base_family == 0x6 or base_family == 0xF) {
            model = (@as(u8, ext_model) << 4) | base_model;
        }

        return .{ .family = family, .model = model, .stepping = stepping, .eax = eax };
    }

    /// Concatenated brand string from leaves `0x80000002..0x80000004`.
    /// Returns `null` when the leaves are unavailable.
    pub fn brandString() ?[48]u8 {
        if (!supported) @compileError(wrong_target);
        if (maxExtendedLeaf() < 0x8000_0004) return null;
        var out: [48]u8 = @splat(0);
        inline for (0..3) |i| {
            const l = @as(Leaf, @enumFromInt(@as(u32, 0x8000_0002) + @as(u32, i)));
            const r = leaf(l);
            std.mem.writeInt(u32, out[i * 16 + 0 ..][0..4], r.eax, .little);
            std.mem.writeInt(u32, out[i * 16 + 4 ..][0..4], r.ebx, .little);
            std.mem.writeInt(u32, out[i * 16 + 8 ..][0..4], r.ecx, .little);
            std.mem.writeInt(u32, out[i * 16 + 12 ..][0..4], r.edx, .little);
        }
        return out;
    }

    /// Fetch CPUID leaf 1 EDX/ECX as typed feature masks.
    pub fn basicFeatures() BasicFeatures {
        if (!supported) @compileError(wrong_target);
        const r = leaf(.feature_info);
        return .{
            .edx = @bitCast(r.edx),
            .ecx = @bitCast(r.ecx),
        };
    }

    /// Fetch CPUID leaf 7 subleaf 0 EBX/ECX/EDX as typed feature masks.
    /// Returns an all-zero bundle when `maxBasicLeaf() < 7`.
    pub fn structuredFeatures() StructuredFeatures {
        if (!supported) @compileError(wrong_target);
        if (maxBasicLeaf() < 7) {
            return .{
                .ebx = @bitCast(@as(u32, 0)),
                .ecx = @bitCast(@as(u32, 0)),
                .edx = @bitCast(@as(u32, 0)),
            };
        }
        const r = subleaf(.structured_extended_features, 0);
        return .{
            .ebx = @bitCast(r.ebx),
            .ecx = @bitCast(r.ecx),
            .edx = @bitCast(r.edx),
        };
    }

    /// Fetch CPUID leaf `0x80000001` EDX/ECX as typed feature masks.
    /// Returns an all-zero bundle when `maxExtendedLeaf() < 0x80000001`.
    pub fn extendedFeatures() ExtendedFeatures {
        if (!supported) @compileError(wrong_target);
        if (maxExtendedLeaf() < 0x8000_0001) {
            return .{
                .edx = @bitCast(@as(u32, 0)),
                .ecx = @bitCast(@as(u32, 0)),
            };
        }
        const r = leaf(.extended_feature_bits);
        return .{
            .edx = @bitCast(r.edx),
            .ecx = @bitCast(r.ecx),
        };
    }

    /// One-shot fetch of every feature-mask bundle owned by this spec.
    pub fn features() Features {
        if (!supported) @compileError(wrong_target);
        return .{
            .basic = basicFeatures(),
            .structured = structuredFeatures(),
            .extended = extendedFeatures(),
        };
    }

    /// Return a fresh iterator over leaf-4 cache descriptors.
    pub fn caches() Cpuid.Cache.Iterator {
        if (!supported) @compileError(wrong_target);
        return .{ .index = 0 };
    }

    /// Decode leaf `0x80000008` address widths. Returns the documented
    /// 32-bit fallback when the leaf is unavailable.
    pub fn addressSizes() AddressSizes {
        if (!supported) @compileError(wrong_target);
        if (maxExtendedLeaf() < 0x8000_0008) {
            return .{ .physical_bits = 32, .linear_bits = 32, .guest_physical_bits = 0 };
        }
        const r = leaf(@as(Leaf, @enumFromInt(0x8000_0008)));
        return .{
            .physical_bits = @truncate(r.eax),
            .linear_bits = @truncate(r.eax >> 8),
            .guest_physical_bits = @truncate(r.eax >> 16),
        };
    }
};

/// Strong MSR-address value type. `read`/`write` execute `rdmsr`/`wrmsr`, both
/// privileged (CPL 0); accessing an unimplemented address raises `#GP`.
pub const Msr = enum(u32) {
    _,

    /// Wrap a raw `u32` MSR address as a strong `Msr` value. Compiles on any
    /// target.
    pub fn fromInt(value: u32) Msr {
        return @enumFromInt(value);
    }

    /// Return the underlying `u32` MSR address. Compiles on any target.
    pub fn raw(self: Msr) u32 {
        return @intFromEnum(self);
    }

    /// Execute `rdmsr` against `self` and return the combined `edx:eax` as
    /// `u64`. Privileged (CPL 0); raises `#GP` on unimplemented MSRs. `memory`
    /// clobber.
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
    /// Privileged (CPL 0); raises `#GP` on unimplemented MSRs or reserved-bit
    /// violations. `memory` clobber.
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

const IA32_FS_BASE: u32 = 0xC000_0100;
const IA32_GS_BASE: u32 = 0xC000_0101;

/// Control-register and extended control-register access. All operations are
/// privileged (CPL 0); calls from CPL > 0 raise `#GP`.
pub const ControlRegister = struct {
    /// `CR0` access (`mov cr0, rNN` / `mov rNN, cr0`). Privileged (CPL 0).
    pub const Cr0 = struct {
        /// Execute `mov %cr0, rNN` and return the value. Privileged (CPL 0).
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%cr0, %[ret]"
                : [ret] "=r" (-> u64),
            );
        }
        /// Execute `mov rNN, %cr0` writing `value`. Privileged (CPL 0).
        /// `memory` clobber.
        pub fn write(value: u64) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%cr0"
                :
                : [v] "r" (value),
                : .{ .memory = true });
        }
    };

    /// `CR2` read-only access. Writes occur only during exception handling and
    /// are out of scope.
    pub const Cr2 = struct {
        /// Execute `mov %cr2, rNN` and return the page-fault linear address.
        /// Privileged (CPL 0).
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%cr2, %[ret]"
                : [ret] "=r" (-> u64),
            );
        }
    };

    /// `CR3` access (paging root). Privileged (CPL 0); `write` may invalidate
    /// TLB entries per architectural rules.
    pub const Cr3 = struct {
        /// Execute `mov %cr3, rNN` and return the value. Privileged (CPL 0).
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%cr3, %[ret]"
                : [ret] "=r" (-> u64),
            );
        }
        /// Execute `mov rNN, %cr3` writing `value`. Privileged (CPL 0); may
        /// invalidate TLB entries per architectural rules. `memory` clobber.
        pub fn write(value: u64) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%cr3"
                :
                : [v] "r" (value),
                : .{ .memory = true });
        }
    };

    /// `CR4` access (architectural feature enables). Privileged (CPL 0).
    pub const Cr4 = struct {
        /// Execute `mov %cr4, rNN` and return the value. Privileged (CPL 0).
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%cr4, %[ret]"
                : [ret] "=r" (-> u64),
            );
        }
        /// Execute `mov rNN, %cr4` writing `value`. Privileged (CPL 0); raises
        /// `#GP` on reserved-bit violations. `memory` clobber.
        pub fn write(value: u64) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%cr4"
                :
                : [v] "r" (value),
                : .{ .memory = true });
        }
    };

    /// `CR8` access (task priority register). Privileged (CPL 0).
    pub const Cr8 = struct {
        /// Execute `mov %cr8, rNN` and return the value. Privileged (CPL 0).
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%cr8, %[ret]"
                : [ret] "=r" (-> u64),
            );
        }
        /// Execute `mov rNN, %cr8` writing `value`. Privileged (CPL 0).
        /// `memory` clobber.
        pub fn write(value: u64) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%cr8"
                :
                : [v] "r" (value),
                : .{ .memory = true });
        }
    };

    /// Extended control register 0 access via `xgetbv`/`xsetbv` with `ecx = 0`.
    /// Requires `Cr4.OSXSAVE`. Privileged (CPL 0).
    pub const Xcr0 = struct {
        /// Execute `xgetbv` with `ecx = 0` and return the combined `edx:eax` as
        /// `u64`. Requires `Cr4.OSXSAVE`.
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
        /// Privileged (CPL 0); requires `Cr4.OSXSAVE`; raises `#GP` when bits
        /// violate CPU support. `memory` clobber.
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

/// Comptime helper: build a `DebugRegister.DrN` sub-type that emits
/// `mov %drN, %rax` / `mov %rax, %drN`. Bodies are target-gated and share
/// the register-only read / memory-clobber write contract from the spec's
/// ordering table.
fn DebugRegSlot(comptime name: []const u8) type {
    return struct {
        /// Execute `mov %drN, %rax` and return the raw `u64`. Privileged
        /// (CPL 0); `#GP` at CPL > 0. Register clobber only.
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%" ++ name ++ ", %[ret]"
                : [ret] "=r" (-> u64),
            );
        }

        /// Execute `mov %rax, %drN` writing `value`. Privileged (CPL 0);
        /// `#GP` at CPL > 0. `memory` clobber.
        pub fn write(value: u64) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%" ++ name
                :
                : [v] "r" (value),
                : .{ .memory = true });
        }
    };
}

/// Raw debug-register access (`Dr0..Dr7`). All operations privileged
/// (CPL 0); Dr4/Dr5 alias Dr6/Dr7 when `CR4.DE = 0` and raise `#UD` when
/// `CR4.DE = 1`. Dr6 status bits are architecturally sticky — callers
/// clear them explicitly. This spec exposes raw access only; Dr7 bit
/// semantics and CR4.DE policy are caller-owned per
/// `docs/specs/arch/x86_64/extensions.md` §DebugRegister.
pub const DebugRegister = struct {
    pub const Dr0 = DebugRegSlot("dr0");
    pub const Dr1 = DebugRegSlot("dr1");
    pub const Dr2 = DebugRegSlot("dr2");
    pub const Dr3 = DebugRegSlot("dr3");
    pub const Dr4 = DebugRegSlot("dr4");
    pub const Dr5 = DebugRegSlot("dr5");
    pub const Dr6 = DebugRegSlot("dr6");
    pub const Dr7 = DebugRegSlot("dr7");
};

/// `RFLAGS` access via `pushfq`/`popfq`. Unprivileged; flag writes affecting
/// privileged state are masked per architectural rules at the current CPL.
pub const Rflags = struct {
    /// Execute `pushfq; pop rNN` and return the value as `u64`. Unprivileged.
    pub fn read() u64 {
        if (!supported) @compileError(wrong_target);
        return asm volatile (
            \\pushfq
            \\popq %[ret]
            : [ret] "=r" (-> u64),
        );
    }

    /// Push `value` and execute `popfq`. Unprivileged; bits the caller cannot
    /// modify at the current CPL are silently ignored. Clobbers `memory` and
    /// `cc`.
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

/// Interrupt-flag control on the issuing logical CPU.
pub const Interrupts = struct {
    /// Execute `sti`. Privileged (CPL 0); raises `#GP` when called below CPL 0.
    /// `memory` clobber.
    pub fn enable() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("sti" ::: .{ .memory = true });
    }

    /// Execute `cli`. Privileged (CPL 0); raises `#GP` when called below CPL 0.
    /// `memory` clobber.
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

/// CPU one-shot instructions: `hlt`, `pause`, `int3`.
pub const Cpu = struct {
    /// Execute `hlt`. Privileged (CPL 0). The CPU halts until the next
    /// interrupt. `memory` clobber.
    pub fn halt() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("hlt" ::: .{ .memory = true });
    }

    /// Execute `pause`. Unprivileged. No `memory` clobber; pair with explicit
    /// fences when ordering against memory access is required.
    pub fn pause() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("pause");
    }

    /// Execute `int3`. Unprivileged. Raises `#BP` by design; behavior depends
    /// on the installed exception handler. `memory` clobber.
    pub fn breakpoint() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("int3" ::: .{ .memory = true });
    }

    /// TSC (time-stamp counter) access via `rdtsc` / `rdtscp`. See also
    /// `docs/specs/arch/x86_64/extensions.md`.
    pub const Tsc = struct {
        /// Combined 64-bit TSC value paired with the `IA32_TSC_AUX` low
        /// 32 bits that `rdtscp` returns in one instruction.
        pub const Reading = struct {
            tsc: u64,
            aux: u32,
        };

        /// Execute `rdtsc` and return the combined `edx:eax` as `u64`.
        /// Unprivileged unless `Cr4.TSD` is set (then `#GP` at CPL > 0).
        /// Register clobber only; not serializing.
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

        /// Execute `rdtscp` and return `Reading{ tsc, aux }`. Partially
        /// serializing on prior instructions per architectural rules.
        /// `#UD` when `RDTSCP` is unsupported; `#GP` at CPL > 0 when
        /// `Cr4.TSD` is set. Register clobbers on `eax`/`ecx`/`edx` only.
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
    pub const Tlb = struct {
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

        /// Execute `invlpg [addr]`. Privileged (CPL 0); `#GP` at CPL > 0.
        /// `memory` clobber to prevent reordering across the invalidation.
        pub fn invalidatePage(addr: usize) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("invlpg (%[addr])"
                :
                : [addr] "r" (addr),
                : .{ .memory = true });
        }

        /// Execute `invpcid (%rdx), %rax` with `rax = @intFromEnum(kind)`
        /// and `rdx = descriptor`. Privileged (CPL 0); `#GP` at CPL > 0;
        /// `#UD` when `INVPCID` is unsupported. `memory` clobber.
        pub fn invalidatePcid(kind: InvpcidKind, descriptor: *const InvpcidDescriptor) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("invpcid (%%rdx), %%rax"
                :
                : [kind] "{rax}" (@as(u64, @intFromEnum(kind))),
                  [desc] "{rdx}" (descriptor),
                : .{ .memory = true });
        }
    };
};

/// Load and store helpers for the GDT, IDT, and task register.
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

    /// GDT load (`lgdt`, privileged) and store (`sgdt`, CPU/OS-policy
    /// dependent at CPL > 0).
    pub const Gdt = struct {
        /// Execute `lgdt [ptr]`. Privileged (CPL 0); raises `#GP` when called
        /// below CPL 0. `memory` clobber.
        pub fn load(ptr: *const Pointer) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("lgdt %[ptr]"
                :
                : [ptr] "*m" (ptr),
                : .{ .memory = true });
        }

        /// Execute `sgdt` into a stack temporary and return it. Accessibility
        /// at CPL > 0 is a CPU/OS policy decision. `memory` clobber.
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

    /// IDT load (`lidt`, privileged) and store (`sidt`, CPU/OS-policy
    /// dependent at CPL > 0).
    pub const Idt = struct {
        /// Execute `lidt [ptr]`. Privileged (CPL 0); raises `#GP` when called
        /// below CPL 0. `memory` clobber.
        pub fn load(ptr: *const Pointer) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("lidt %[ptr]"
                :
                : [ptr] "*m" (ptr),
                : .{ .memory = true });
        }

        /// Execute `sidt` into a stack temporary and return it. Accessibility
        /// at CPL > 0 is a CPU/OS policy decision. `memory` clobber.
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

    /// Task register load (`ltr`, privileged) and store (`str`).
    pub const TaskRegister = struct {
        /// Execute `ltr selector`. Privileged (CPL 0); raises `#GP` when called
        /// below CPL 0 or when the selector violates architectural rules.
        /// `memory` clobber.
        pub fn load(selector: u16) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("ltr %[sel]"
                :
                : [sel] "r" (selector),
                : .{ .memory = true });
        }

        /// Execute `str` and return the current task-register selector.
        /// Accessibility at CPL > 0 is a CPU/OS policy decision.
        pub fn store() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("str %[ret]"
                : [ret] "=r" (-> u16),
            );
        }
    };

    /// LDT-selector load (`lldt`, privileged) and store (`sldt`). See also
    /// `docs/specs/arch/x86_64/extensions.md`.
    pub const Ldtr = struct {
        /// Execute `lldt selector`. Privileged (CPL 0); `#GP` at CPL > 0
        /// or when the selector is invalid, points to a non-LDT descriptor,
        /// or the descriptor is not present. `memory` clobber.
        pub fn load(selector: u16) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("lldt %[sel]"
                :
                : [sel] "r" (selector),
                : .{ .memory = true });
        }

        /// Execute `sldt` and return the current LDT selector.
        /// Accessibility at CPL > 0 is a CPU/OS policy decision.
        /// Register clobber only.
        pub fn store() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("sldt %[ret]"
                : [ret] "=r" (-> u16),
            );
        }
    };
};

/// Segment-register and segment-base access.
pub const Segment = struct {
    /// Code-segment selector access. `read` is unprivileged; loading `cs`
    /// requires a far return.
    pub const Cs = struct {
        /// Execute `mov %cs, rNN` and return the current selector.
        /// Unprivileged.
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

    /// `DS` selector access. `write` is privileged (CPL 0).
    pub const Ds = struct {
        /// Execute `mov %ds, rNN` and return the current selector.
        /// Unprivileged.
        pub fn read() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%ds, %[ret]"
                : [ret] "=r" (-> u16),
            );
        }
        /// Execute `mov rNN, %ds` loading `selector`. Privileged (CPL 0);
        /// raises `#GP` when called below CPL 0 or on architectural violations.
        /// `memory` clobber.
        pub fn write(selector: u16) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%ds"
                :
                : [v] "r" (selector),
                : .{ .memory = true });
        }
    };

    /// `ES` selector access. `write` is privileged (CPL 0).
    pub const Es = struct {
        /// Execute `mov %es, rNN` and return the current selector.
        /// Unprivileged.
        pub fn read() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%es, %[ret]"
                : [ret] "=r" (-> u16),
            );
        }
        /// Execute `mov rNN, %es` loading `selector`. Privileged (CPL 0);
        /// raises `#GP` when called below CPL 0 or on architectural violations.
        /// `memory` clobber.
        pub fn write(selector: u16) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%es"
                :
                : [v] "r" (selector),
                : .{ .memory = true });
        }
    };

    /// `FS` selector access. `write` is privileged (CPL 0).
    pub const Fs = struct {
        /// Execute `mov %fs, rNN` and return the current selector.
        /// Unprivileged.
        pub fn read() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%fs, %[ret]"
                : [ret] "=r" (-> u16),
            );
        }
        /// Execute `mov rNN, %fs` loading `selector`. Privileged (CPL 0);
        /// raises `#GP` when called below CPL 0 or on architectural violations.
        /// `memory` clobber.
        pub fn write(selector: u16) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%fs"
                :
                : [v] "r" (selector),
                : .{ .memory = true });
        }
    };

    /// `GS` selector access. `write` is privileged (CPL 0).
    pub const Gs = struct {
        /// Execute `mov %gs, rNN` and return the current selector.
        /// Unprivileged.
        pub fn read() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%gs, %[ret]"
                : [ret] "=r" (-> u16),
            );
        }
        /// Execute `mov rNN, %gs` loading `selector`. Privileged (CPL 0);
        /// raises `#GP` when called below CPL 0 or on architectural violations.
        /// `memory` clobber.
        pub fn write(selector: u16) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%gs"
                :
                : [v] "r" (selector),
                : .{ .memory = true });
        }
    };

    /// `SS` selector access. `write` is privileged (CPL 0).
    pub const Ss = struct {
        /// Execute `mov %ss, rNN` and return the current selector.
        /// Unprivileged.
        pub fn read() u16 {
            if (!supported) @compileError(wrong_target);
            return asm volatile ("mov %%ss, %[ret]"
                : [ret] "=r" (-> u16),
            );
        }
        /// Execute `mov rNN, %ss` loading `selector`. Privileged (CPL 0);
        /// raises `#GP` when called below CPL 0 or on architectural violations.
        /// `memory` clobber.
        pub fn write(selector: u16) void {
            if (!supported) @compileError(wrong_target);
            asm volatile ("mov %[v], %%ss"
                :
                : [v] "r" (selector),
                : .{ .memory = true });
        }
    };

    /// FS-base access. Uses `rdfsbase`/`wrfsbase` when FSGSBASE is advertised
    /// and `Cr4.FSGSBASE` is set; otherwise falls back to `IA32_FS_BASE` MSR.
    /// MSR fallback is privileged (CPL 0).
    pub const FsBase = struct {
        /// Read the current FS base. Uses `rdfsbase` when CPUID advertises
        /// FSGSBASE and `Cr4.FSGSBASE` is set; otherwise falls back to `rdmsr`
        /// against `IA32_FS_BASE`. MSR fallback is privileged (CPL 0).
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            if (fsgsbaseSupported()) {
                return asm volatile ("rdfsbase %[ret]"
                    : [ret] "=r" (-> u64),
                );
            }
            return Msr.fromInt(IA32_FS_BASE).read();
        }
        /// Write the FS base. Uses `wrfsbase` when CPUID advertises FSGSBASE
        /// and `Cr4.FSGSBASE` is set; otherwise falls back to `wrmsr` against
        /// `IA32_FS_BASE`. MSR fallback is privileged (CPL 0). `memory` clobber.
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

    /// GS-base access. Uses `rdgsbase`/`wrgsbase` when FSGSBASE is advertised
    /// and `Cr4.FSGSBASE` is set; otherwise falls back to `IA32_GS_BASE` MSR.
    /// MSR fallback is privileged (CPL 0).
    pub const GsBase = struct {
        /// Read the current GS base. Uses `rdgsbase` when CPUID advertises
        /// FSGSBASE and `Cr4.FSGSBASE` is set; otherwise falls back to `rdmsr`
        /// against `IA32_GS_BASE`. MSR fallback is privileged (CPL 0).
        pub fn read() u64 {
            if (!supported) @compileError(wrong_target);
            if (fsgsbaseSupported()) {
                return asm volatile ("rdgsbase %[ret]"
                    : [ret] "=r" (-> u64),
                );
            }
            return Msr.fromInt(IA32_GS_BASE).read();
        }
        /// Write the GS base. Uses `wrgsbase` when CPUID advertises FSGSBASE
        /// and `Cr4.FSGSBASE` is set; otherwise falls back to `wrmsr` against
        /// `IA32_GS_BASE`. MSR fallback is privileged (CPL 0). `memory` clobber.
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

    /// Execute `swapgs`. Privileged (CPL 0); exchanges `GS.base` with
    /// `IA32_KERNEL_GS_BASE`. `memory` clobber.
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

/// Raw x86 fence instructions. All unprivileged.
pub const Fence = struct {
    /// Execute `lfence`. Unprivileged. Architectural load fence; `memory`
    /// clobber.
    pub fn lfence() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("lfence" ::: .{ .memory = true });
    }

    /// Execute `sfence`. Unprivileged. Architectural store fence; `memory`
    /// clobber.
    pub fn sfence() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("sfence" ::: .{ .memory = true });
    }

    /// Execute `mfence`. Unprivileged. Architectural full memory fence;
    /// `memory` clobber.
    pub fn mfence() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("mfence" ::: .{ .memory = true });
    }
};

/// Cache-line maintenance and full-cache control instructions.
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

    /// Execute `clflush [addr]`. Unprivileged. `memory` clobber.
    pub fn flush(addr: usize) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("clflush (%[addr])"
            :
            : [addr] "r" (addr),
            : .{ .memory = true });
    }

    /// Execute `clflushopt [addr]`. Unprivileged; may compile down to `clflush`
    /// when `clflushopt` is unavailable. `memory` clobber.
    pub fn flushOptimized(addr: usize) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("clflushopt (%[addr])"
            :
            : [addr] "r" (addr),
            : .{ .memory = true });
    }

    /// Execute `clwb [addr]`. Unprivileged; may compile down to `clflushopt`
    /// or `clflush` when `clwb` is unavailable. `memory` clobber.
    pub fn writeBack(addr: usize) void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("clwb (%[addr])"
            :
            : [addr] "r" (addr),
            : .{ .memory = true });
    }

    /// Walk `[ptr, ptr + len)` in `lineSize()` steps, calling `flush` per line.
    /// Unprivileged.
    pub fn flushRange(ptr: [*]const u8, len: usize) void {
        if (!supported) @compileError(wrong_target);
        rangeWalk(ptr, len, flush);
    }

    /// Walk `[ptr, ptr + len)` in `lineSize()` steps, calling `writeBack` per
    /// line. Unprivileged.
    pub fn writeBackRange(ptr: [*]const u8, len: usize) void {
        if (!supported) @compileError(wrong_target);
        rangeWalk(ptr, len, writeBack);
    }

    /// Execute `wbinvd`. Privileged (CPL 0); raises `#GP` when called below
    /// CPL 0. `memory` clobber.
    pub fn writeBackInvalidate() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("wbinvd" ::: .{ .memory = true });
    }

    /// Execute `invd`. Privileged (CPL 0); raises `#GP` when called below
    /// CPL 0. Loses dirty cache state when no prior write-back was issued.
    /// `memory` clobber.
    pub fn invalidate() void {
        if (!supported) @compileError(wrong_target);
        asm volatile ("invd" ::: .{ .memory = true });
    }
};

/// Walk `[ptr, ptr + len)` in `Cache.lineSize()` steps, invoking `op` on the
/// line-aligned address of every covered line.
fn rangeWalk(ptr: [*]const u8, len: usize, comptime op: fn (usize) void) void {
    if (!supported) @compileError(wrong_target);

    const line = Cache.lineSize();

    std.debug.assert(line > 0);
    std.debug.assert(std.math.isPowerOfTwo(line));

    const start = @intFromPtr(ptr);
    if (debug.checksEnabled(.build_mode)) {
        std.debug.assert(len <= std.math.maxInt(usize) - start);
    }
    const end = std.math.add(usize, start, len) catch return;
    if (len == 0) return;

    var cursor = start & ~(line - 1);
    while (cursor < end) : (cursor += line) {
        op(cursor);
    }
}

/// Current-privilege-level probe.
pub const Privilege = struct {
    /// Bits 0-1 of the `cs` segment selector hold the architectural RPL/CPL,
    /// so truncating `cs` to `u2` extracts the current privilege level.
    /// Unprivileged.
    pub fn currentLevel() u2 {
        if (!supported) @compileError(wrong_target);
        return @truncate(Segment.Cs.read());
    }
};
