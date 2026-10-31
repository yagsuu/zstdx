//! unprivileged x86_64 CPUID queries and decoders.

const std = @import("std");

const target = @import("target.zig");

pub const Leaf = enum(u32) {
    max_basic = 0x0000_0000,
    basic_features = 0x0000_0001,
    cache_parameters = 0x0000_0004,
    structured_features = 0x0000_0007,
    max_extended = 0x8000_0000,
    extended_features = 0x8000_0001,
    brand_1 = 0x8000_0002,
    brand_2 = 0x8000_0003,
    brand_3 = 0x8000_0004,
    address_sizes = 0x8000_0008,
    _,

    const Self = @This();

    pub fn from(value: u32) Self {
        return @enumFromInt(value);
    }

    pub fn raw(self: Self) u32 {
        return @intFromEnum(self);
    }
};

pub const Result = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

pub const Vendor = enum {
    intel,
    amd,
    via,
    cyrix,
    transmeta,
    centaur,
    unknown,

    pub fn decode(bytes: [12]u8) Vendor {
        const suffix = bytes[1..];
        switch (bytes[0]) {
            'A' => {
                if (std.mem.eql(u8, suffix, "uthenticAMD")) {
                    return .amd;
                }
            },
            'C' => {
                if (std.mem.eql(u8, suffix, "entaurHauls")) {
                    return .centaur;
                }
                if (std.mem.eql(u8, suffix, "yrixInstead")) {
                    return .cyrix;
                }
            },
            'G' => {
                if (std.mem.eql(u8, suffix, "enuineIntel")) {
                    return .intel;
                }
                if (std.mem.eql(u8, suffix, "enuineTMx86")) {
                    return .transmeta;
                }
            },
            'T' => {
                if (std.mem.eql(u8, suffix, "ransmetaCPU")) {
                    return .transmeta;
                }
            },
            'V' => {
                if (std.mem.eql(u8, suffix, "IA VIA VIA ")) {
                    return .via;
                }
            },
            else => {},
        }

        return .unknown;
    }
};

/// family and model include signature extensions where applicable.
pub const Version = struct {
    family: u12,
    model: u8,
    stepping: u4,
    eax: u32,

    pub fn decode(signature: Signature) Version {
        var family: u12 = signature.family;
        if (signature.family == 0xF) {
            family += signature.extended_family;
        }

        var model: u8 = signature.model;
        if (signature.family == 0x6 or signature.family == 0xF) {
            model |= @as(u8, signature.extended_model) << 4;
        }

        return .{
            .family = family,
            .model = model,
            .stepping = signature.stepping,
            .eax = @bitCast(signature),
        };
    }
};

pub const Signature = packed struct(u32) {
    stepping: u4,
    model: u4,
    family: u4,
    processor_type: u2,
    _reserved_14: u2 = 0,
    extended_model: u4,
    extended_family: u8,
    _reserved_28: u4 = 0,
};

pub const Features = struct {
    basic: Basic,
    structured: Structured,
    extended: Extended,
};

/// leaf 1.
pub const Basic = struct {
    eax: Signature,
    ebx: BasicEbx,
    ecx: BasicEcx,
    edx: BasicEdx,

    pub fn from(result: Result) Basic {
        return .{
            .eax = @bitCast(result.eax),
            .ebx = @bitCast(result.ebx),
            .ecx = @bitCast(result.ecx),
            .edx = @bitCast(result.edx),
        };
    }
};

pub const BasicEbx = packed struct(u32) {
    brand_index: u8,
    clflush_units: u8,
    logical_processors: u8,
    initial_apic_id: u8,
};

pub const BasicEcx = packed struct(u32) {
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
    _unknown_16: u1,
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

    pub const unknown_mask: u32 = mask: {
        var value = std.mem.zeroes(BasicEcx);
        value._unknown_16 = ~value._unknown_16;
        break :mask @bitCast(value);
    };

    pub fn unknownBits(self: BasicEcx) u32 {
        return @as(u32, @bitCast(self)) & unknown_mask;
    }
};

pub const BasicEdx = packed struct(u32) {
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
    _unknown_10: u1,
    sep: bool,
    mtrr: bool,
    pge: bool,
    mca: bool,
    cmov: bool,
    pat: bool,
    pse36: bool,
    psn: bool,
    clflush: bool,
    _unknown_20: u1,
    ds: bool,
    acpi: bool,
    mmx: bool,
    fxsr: bool,
    sse: bool,
    sse2: bool,
    ss: bool,
    htt: bool,
    tm: bool,
    _unknown_30: u1,
    pbe: bool,

    pub const unknown_mask: u32 = mask: {
        var value = std.mem.zeroes(BasicEdx);
        value._unknown_10 = ~value._unknown_10;
        value._unknown_20 = ~value._unknown_20;
        value._unknown_30 = ~value._unknown_30;
        break :mask @bitCast(value);
    };

    pub fn unknownBits(self: BasicEdx) u32 {
        return @as(u32, @bitCast(self)) & unknown_mask;
    }
};

/// leaf 7, subleaf 0.
pub const Structured = struct {
    eax: u32,
    ebx: StructuredEbx,
    ecx: StructuredEcx,
    edx: StructuredEdx,

    pub fn from(result: Result) Structured {
        return .{
            .eax = result.eax,
            .ebx = @bitCast(result.ebx),
            .ecx = @bitCast(result.ecx),
            .edx = @bitCast(result.edx),
        };
    }
};

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
    _unknown_22: u1,
    clflushopt: bool,
    clwb: bool,
    intel_pt: bool,
    avx512pf: bool,
    avx512er: bool,
    avx512cd: bool,
    sha: bool,
    avx512bw: bool,
    avx512vl: bool,

    pub const unknown_mask: u32 = mask: {
        var value = std.mem.zeroes(StructuredEbx);
        value._unknown_22 = ~value._unknown_22;
        break :mask @bitCast(value);
    };

    pub fn unknownBits(self: StructuredEbx) u32 {
        return @as(u32, @bitCast(self)) & unknown_mask;
    }
};

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
    _unknown_15: u1,
    la57: bool,
    mawau: u5,
    rdpid: bool,
    kl: bool,
    bus_lock_detect: bool,
    cldemote: bool,
    _unknown_26: u1,
    movdiri: bool,
    movdir64b: bool,
    enqcmd: bool,
    sgx_lc: bool,
    pks: bool,

    pub const unknown_mask: u32 = mask: {
        var value = std.mem.zeroes(StructuredEcx);
        value._unknown_15 = ~value._unknown_15;
        value._unknown_26 = ~value._unknown_26;
        break :mask @bitCast(value);
    };

    pub fn unknownBits(self: StructuredEcx) u32 {
        return @as(u32, @bitCast(self)) & unknown_mask;
    }
};

pub const StructuredEdx = packed struct(u32) {
    _unknown_0: u2,
    avx512_4vnniw: bool,
    avx512_4fmaps: bool,
    fast_short_rep_mov: bool,
    uintr: bool,
    _unknown_6: u2,
    avx512_vp2intersect: bool,
    srbds_ctrl: bool,
    md_clear: bool,
    rtm_always_abort: bool,
    _unknown_12: u1,
    rtm_force_abort: bool,
    serialize: bool,
    hybrid: bool,
    tsxldtrk: bool,
    _unknown_17: u1,
    pconfig: bool,
    architectural_lbrs: bool,
    cet_ibt: bool,
    _unknown_21: u1,
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

    pub const unknown_mask: u32 = mask: {
        var value = std.mem.zeroes(StructuredEdx);
        value._unknown_0 = ~value._unknown_0;
        value._unknown_6 = ~value._unknown_6;
        value._unknown_12 = ~value._unknown_12;
        value._unknown_17 = ~value._unknown_17;
        value._unknown_21 = ~value._unknown_21;
        break :mask @bitCast(value);
    };

    pub fn unknownBits(self: StructuredEdx) u32 {
        return @as(u32, @bitCast(self)) & unknown_mask;
    }
};

/// leaf `0x80000001`.
pub const Extended = struct {
    eax: u32,
    ebx: u32,
    ecx: ExtendedEcx,
    edx: ExtendedEdx,

    pub fn from(result: Result) Extended {
        return .{
            .eax = result.eax,
            .ebx = result.ebx,
            .ecx = @bitCast(result.ecx),
            .edx = @bitCast(result.edx),
        };
    }
};

pub const ExtendedEcx = packed struct(u32) {
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
    _unknown_14: u1,
    lwp: bool,
    fma4: bool,
    tce: bool,
    _unknown_18: u4,
    topoext: bool,
    perfctr_core: bool,
    perfctr_nb: bool,
    _unknown_25: u7,

    pub const unknown_mask: u32 = mask: {
        var value = std.mem.zeroes(ExtendedEcx);
        value._unknown_14 = ~value._unknown_14;
        value._unknown_18 = ~value._unknown_18;
        value._unknown_25 = ~value._unknown_25;
        break :mask @bitCast(value);
    };

    pub fn unknownBits(self: ExtendedEcx) u32 {
        return @as(u32, @bitCast(self)) & unknown_mask;
    }
};

pub const ExtendedEdx = packed struct(u32) {
    _unknown_0: u11,
    syscall: bool,
    _unknown_12: u8,
    nx: bool,
    _unknown_21: u5,
    pdpe1gb: bool,
    rdtscp: bool,
    _unknown_28: u1,
    lm: bool,
    _unknown_30: u2,

    pub const unknown_mask: u32 = mask: {
        var value = std.mem.zeroes(ExtendedEdx);
        value._unknown_0 = ~value._unknown_0;
        value._unknown_12 = ~value._unknown_12;
        value._unknown_21 = ~value._unknown_21;
        value._unknown_28 = ~value._unknown_28;
        value._unknown_30 = ~value._unknown_30;
        break :mask @bitCast(value);
    };

    pub fn unknownBits(self: ExtendedEdx) u32 {
        return @as(u32, @bitCast(self)) & unknown_mask;
    }
};

pub const Cache = struct {
    pub const Kind = enum(u5) {
        null = 0,
        data = 1,
        instruction = 2,
        unified = 3,
        _,
    };

    pub const Descriptor = struct {
        level: u3,
        kind: Kind,
        line_size: u32,
        partitions: u32,
        ways: u32,
        sets: u64,
        fully_associative: bool,
        self_initializing: bool,
        eax: u32,
        ebx: u32,
        ecx: u32,
        edx: u32,

        pub fn decode(raw: Result) ?Descriptor {
            const eax: Eax = @bitCast(raw.eax);
            const ebx: Ebx = @bitCast(raw.ebx);
            if (eax.kind == .null) {
                return null;
            }

            return .{
                .level = eax.level,
                .kind = eax.kind,
                .line_size = @as(u32, ebx.line_size) + 1,
                .partitions = @as(u32, ebx.partitions) + 1,
                .ways = @as(u32, ebx.ways) + 1,
                .sets = @as(u64, raw.ecx) + 1,
                .fully_associative = eax.fully_associative,
                .self_initializing = eax.self_initializing,
                .eax = raw.eax,
                .ebx = raw.ebx,
                .ecx = raw.ecx,
                .edx = raw.edx,
            };
        }
    };

    pub const Iterator = struct {
        subleaf: u32,
        done: bool,

        pub fn next(self: *Iterator) ?Descriptor {
            comptime target.require();

            if (self.done) {
                return null;
            }

            const raw = query(.cache_parameters, self.subleaf);
            const descriptor = Descriptor.decode(raw) orelse {
                self.done = true;
                return null;
            };

            self.subleaf += 1;
            return descriptor;
        }
    };

    const Eax = packed struct(u32) {
        kind: Kind,
        level: u3,
        self_initializing: bool,
        fully_associative: bool,
        _reserved_10: u4 = 0,
        _unknown_14: u18,
    };

    const Ebx = packed struct(u32) {
        line_size: u12,
        partitions: u10,
        ways: u10,
    };
};

pub const AddressSizes = struct {
    physical_bits: u8,
    linear_bits: u8,
    guest_physical_bits: u8,

    const Eax = packed struct(u32) {
        physical_bits: u8,
        linear_bits: u8,
        guest_physical_bits: u8,
        _reserved_24: u8 = 0,
    };
};

/// unavailable leaves and subleaves retain the CPU's raw query behavior.
pub fn query(leaf: Leaf, subleaf: u32) Result {
    comptime target.require();

    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [eax_in] "{eax}" (leaf.raw()),
          [ecx_in] "{ecx}" (subleaf),
    );

    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

/// the caller selects a decoder matching the requested leaf and subleaf.
pub fn queryAs(comptime T: type, leaf: Leaf, subleaf: u32) T {
    return T.from(query(leaf, subleaf));
}

pub fn maxBasicLeaf() u32 {
    return query(.max_basic, 0).eax;
}

pub fn maxExtendedLeaf() u32 {
    return query(.max_extended, 0).eax;
}

pub fn vendor() Vendor {
    return Vendor.decode(vendorString());
}

pub fn vendorString() [12]u8 {
    const result = query(.max_basic, 0);
    var bytes: [12]u8 = undefined;

    std.mem.writeInt(u32, bytes[0..4], result.ebx, .little);
    std.mem.writeInt(u32, bytes[4..8], result.edx, .little);
    std.mem.writeInt(u32, bytes[8..12], result.ecx, .little);

    return bytes;
}

/// returns `null` when leaves `0x80000002..0x80000004` are unavailable.
pub fn brandString() ?[48]u8 {
    if (maxExtendedLeaf() < Leaf.brand_3.raw()) {
        return null;
    }

    var bytes: [48]u8 = undefined;
    inline for (.{ Leaf.brand_1, Leaf.brand_2, Leaf.brand_3 }, 0..) |which, index| {
        const result = query(which, 0);
        std.mem.writeInt(u32, bytes[index * 16 ..][0..4], result.eax, .little);
        std.mem.writeInt(u32, bytes[index * 16 + 4 ..][0..4], result.ebx, .little);
        std.mem.writeInt(u32, bytes[index * 16 + 8 ..][0..4], result.ecx, .little);
        std.mem.writeInt(u32, bytes[index * 16 + 12 ..][0..4], result.edx, .little);
    }

    return bytes;
}

pub fn version() Version {
    return Version.decode(basicFeatures().eax);
}

pub fn features() Features {
    return .{
        .basic = basicFeatures(),
        .structured = structuredFeatures(),
        .extended = extendedFeatures(),
    };
}

/// leaf 1 is required on x86_64.
pub fn basicFeatures() Basic {
    return queryAs(Basic, .basic_features, 0);
}

/// returns an all-zero bundle when leaf 7 is unavailable.
pub fn structuredFeatures() Structured {
    if (maxBasicLeaf() < Leaf.structured_features.raw()) {
        return std.mem.zeroes(Structured);
    }

    return queryAs(Structured, .structured_features, 0);
}

/// returns an all-zero bundle when leaf `0x80000001` is unavailable.
pub fn extendedFeatures() Extended {
    if (maxExtendedLeaf() < Leaf.extended_features.raw()) {
        return std.mem.zeroes(Extended);
    }

    return queryAs(Extended, .extended_features, 0);
}

pub fn caches() Cache.Iterator {
    return .{ .subleaf = 0, .done = maxBasicLeaf() < Leaf.cache_parameters.raw() };
}

/// unavailable leaf `0x80000008` returns 32 physical bits, 32 linear bits, and zero guest physical bits.
pub fn addressSizes() AddressSizes {
    if (maxExtendedLeaf() < Leaf.address_sizes.raw()) {
        return .{ .physical_bits = 32, .linear_bits = 32, .guest_physical_bits = 0 };
    }

    const result = query(.address_sizes, 0);
    const eax: AddressSizes.Eax = @bitCast(result.eax);

    return .{
        .physical_bits = eax.physical_bits,
        .linear_bits = eax.linear_bits,
        .guest_physical_bits = eax.guest_physical_bits,
    };
}

pub const unit = struct {
    const testing = std.testing;

    test "signature extensions apply only to their base families" {
        const cases = [_]struct { eax: u32, family: u12, model: u8 }{
            .{ .eax = 0x0FF9_05A3, .family = 5, .model = 0xA },
            .{ .eax = 0x0FF9_06A3, .family = 6, .model = 0x9A },
            .{ .eax = 0x0FF9_0EA3, .family = 14, .model = 0xA },
            .{ .eax = 0x0FF9_0FA3, .family = 270, .model = 0x9A },
        };
        for (cases) |case| {
            const decoded = Version.decode(@bitCast(case.eax));

            try testing.expectEqual(case.family, decoded.family);
            try testing.expectEqual(case.model, decoded.model);
            try testing.expectEqual(@as(u4, 3), decoded.stepping);
            try testing.expectEqual(case.eax, decoded.eax);
        }
    }

    test "vendor matching uses all twelve bytes and accepts both Transmeta strings" {
        try testing.expectEqual(Vendor.intel, Vendor.decode("GenuineIntel".*));
        try testing.expectEqual(Vendor.amd, Vendor.decode("AuthenticAMD".*));
        try testing.expectEqual(Vendor.via, Vendor.decode("VIA VIA VIA ".*));
        try testing.expectEqual(Vendor.centaur, Vendor.decode("CentaurHauls".*));
        try testing.expectEqual(Vendor.cyrix, Vendor.decode("CyrixInstead".*));
        try testing.expectEqual(Vendor.transmeta, Vendor.decode("GenuineTMx86".*));
        try testing.expectEqual(Vendor.transmeta, Vendor.decode("TransmetaCPU".*));

        for ([_][12]u8{
            "AuthenticAM?".*,
            "CyrixInstea?".*,
            "GenuineTMx8?".*,
            "TransmetaCP?".*,
            "VIA VIA VIA?".*,
            "XuthenticAMD".*,
        }) |bytes| {
            try testing.expectEqual(Vendor.unknown, Vendor.decode(bytes));
        }

        try testing.expectEqual(Vendor.unknown, Vendor.decode("GenuineInte?".*));
        try testing.expectEqual(Vendor.unknown, Vendor.decode(@splat(0)));
    }

    test "cache decoding preserves unknown kinds and the full set count" {
        const raw: Result = .{
            .eax = 0xA000_0367,
            .ebx = (7 << 22) | (1 << 12) | 63,
            .ecx = 511,
            .edx = 0x8000_0007,
        };
        const decoded = Cache.Descriptor.decode(raw).?;
        const maximum = Cache.Descriptor.decode(.{
            .eax = 1,
            .ebx = 0xFFFF_FFFF,
            .ecx = 0xFFFF_FFFF,
            .edx = 0,
        }).?;
        const terminator = Cache.Descriptor.decode(.{
            .eax = 0xFFFF_FFE0,
            .ebx = 0xFFFF_FFFF,
            .ecx = 0xFFFF_FFFF,
            .edx = 0xFFFF_FFFF,
        });

        try testing.expectEqual(@as(u5, 7), @intFromEnum(decoded.kind));
        try testing.expectEqual(@as(u3, 3), decoded.level);
        try testing.expectEqual(@as(u32, 64), decoded.line_size);
        try testing.expectEqual(@as(u32, 2), decoded.partitions);
        try testing.expectEqual(@as(u32, 8), decoded.ways);
        try testing.expectEqual(@as(u64, 512), decoded.sets);
        try testing.expect(decoded.fully_associative);
        try testing.expect(decoded.self_initializing);
        try testing.expectEqual(raw, Result{
            .eax = decoded.eax,
            .ebx = decoded.ebx,
            .ecx = decoded.ecx,
            .edx = decoded.edx,
        });
        try testing.expectEqual(@as(u32, 4096), maximum.line_size);
        try testing.expectEqual(@as(u32, 1024), maximum.partitions);
        try testing.expectEqual(@as(u32, 1024), maximum.ways);
        try testing.expectEqual(@as(u64, 1) << 32, maximum.sets);
        try testing.expectEqual(@as(?Cache.Descriptor, null), terminator);
    }

    test "unmodeled positions are extracted without changing feature bits" {
        const basic: BasicEdx = @bitCast(@as(u32, (1 << 10) | (1 << 25)));
        const clean: BasicEdx = @bitCast(@as(u32, 1 << 25));
        const extended: ExtendedEdx = @bitCast(@as(u32, (1 << 0) | (1 << 29)));
        const structured: StructuredEcx = @bitCast(@as(u32, (1 << 15) | (17 << 17)));

        try testing.expectEqual(@as(u32, 1 << 10), basic.unknownBits());
        try testing.expect(basic.sse);
        try testing.expectEqual(@as(u32, (1 << 10) | (1 << 25)), @as(u32, @bitCast(basic)));
        try testing.expectEqual(@as(u32, 0), clean.unknownBits());
        try testing.expectEqual(@as(u32, 1), extended.unknownBits());
        try testing.expect(extended.lm);
        try testing.expectEqual(@as(u32, (1 << 0) | (1 << 29)), @as(u32, @bitCast(extended)));
        try testing.expectEqual(@as(u32, 1 << 15), structured.unknownBits());
        try testing.expectEqual(@as(u5, 17), structured.mawau);
        try testing.expectEqual(@as(u32, (1 << 15) | (17 << 17)), @as(u32, @bitCast(structured)));
    }
};
