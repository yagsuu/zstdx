//! x86_64 CPUID decoders. See `docs/specs/arch/x86_64/cpuid.md`.

const std = @import("std");

const target = @import("target.zig");

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

/// Executes `cpuid` with `ecx = 0` against `which` and returns the four
/// output registers.
/// Privilege: unprivileged.
pub fn leaf(which: Leaf) Result {
    target.ensureSupported();
    return subleaf(which, 0);
}

/// Executes `cpuid` with `eax = which` and `ecx = sub`, returning the four
/// output registers.
/// Privilege: unprivileged.
pub fn subleaf(which: Leaf, sub: u32) Result {
    target.ensureSupported();

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

/// Returns the highest basic CPUID leaf supported by the running CPU.
/// Privilege: unprivileged.
pub fn maxBasicLeaf() u32 {
    target.ensureSupported();
    return leaf(.max_basic).eax;
}

/// Returns the highest extended CPUID leaf supported by the running CPU.
/// Privilege: unprivileged.
pub fn maxExtendedLeaf() u32 {
    target.ensureSupported();
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

/// Returns true when any `_reserved_` field in a packed mask is non-zero.
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
pub const cache = struct {
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

        pub fn next(self: *Iterator) ?cache.Descriptor {
            target.ensureSupported();
            if (maxBasicLeaf() < 4) return null;
            const r = subleaf(@as(Leaf, @enumFromInt(4)), self.index);
            const raw_kind: u5 = @truncate(r.eax);
            if (raw_kind == 0) return null;
            self.index += 1;
            return .{
                .level = @truncate(r.eax >> 5),
                .kind = @as(cache.Kind, @enumFromInt(raw_kind)),
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

/// Returns the CPU vendor decoded from CPUID leaf 0.
pub fn vendor() Vendor {
    target.ensureSupported();

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
    target.ensureSupported();

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
    target.ensureSupported();
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
    target.ensureSupported();
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

/// Fetches CPUID leaf 1 EDX/ECX as typed feature masks.
pub fn basicFeatures() BasicFeatures {
    target.ensureSupported();

    const r = leaf(.feature_info);
    return .{
        .edx = @bitCast(r.edx),
        .ecx = @bitCast(r.ecx),
    };
}

/// Fetches CPUID leaf 7 subleaf 0 EBX/ECX/EDX as typed feature masks.
/// Returns an all-zero bundle when `maxBasicLeaf() < 7`.
pub fn structuredFeatures() StructuredFeatures {
    target.ensureSupported();
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

/// Fetches CPUID leaf `0x80000001` EDX/ECX as typed feature masks.
/// Returns an all-zero bundle when `maxExtendedLeaf() < 0x80000001`.
pub fn extendedFeatures() ExtendedFeatures {
    target.ensureSupported();

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
    target.ensureSupported();
    return .{
        .basic = basicFeatures(),
        .structured = structuredFeatures(),
        .extended = extendedFeatures(),
    };
}

/// Returns a fresh iterator over leaf-4 cache descriptors.
pub fn caches() cache.Iterator {
    target.ensureSupported();
    return .{ .index = 0 };
}

/// Decode leaf `0x80000008` address widths. Returns the documented
/// 32-bit fallback when the leaf is unavailable.
pub fn addressSizes() AddressSizes {
    target.ensureSupported();

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
