//! x86_64 CPUID decoder contract tests.
//! Spec: docs/specs/arch/x86_64/cpuid.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const x86 = stdx.arch.x86_64;
const Cpuid = x86.Cpuid;

const testing = std.testing;

// Compile-only structural tests asserting every layout invariant the spec's
// "Required tests" section pins. These execute at comptime; on non-x86_64
// targets they still fire because the mask/bundle types have no asm gate.

comptime {
    // Every feature mask is a packed-struct-of-u32 with @sizeOf == 4.
    // Spec §Feature masks.
    const masks = .{
        Cpuid.BasicFeatureEdx,
        Cpuid.BasicFeatureEcx,
        Cpuid.StructuredEbx,
        Cpuid.StructuredEcx,
        Cpuid.StructuredEdx,
        Cpuid.ExtendedFeatureEdx,
        Cpuid.ExtendedFeatureEcx,
    };
    for (masks) |M| {
        std.debug.assert(@bitSizeOf(M) == 32);
        std.debug.assert(@sizeOf(M) == 4);
        std.debug.assert(@typeInfo(M).@"struct".layout == .@"packed");
        std.debug.assert(@typeInfo(M).@"struct".backing_integer == u32);
    }

    // `@bitCast(u32, BasicFeatureEdx{}) == 0`; the default-initialized mask
    // has every named bit `false` and every reserved slot 0.
    std.debug.assert(@as(u32, @bitCast(Cpuid.BasicFeatureEdx{
        .fpu = false,
        .vme = false,
        .de = false,
        .pse = false,
        .tsc = false,
        .msr = false,
        .pae = false,
        .mce = false,
        .cx8 = false,
        .apic = false,
        .sep = false,
        .mtrr = false,
        .pge = false,
        .mca = false,
        .cmov = false,
        .pat = false,
        .pse36 = false,
        .psn = false,
        .clflush = false,
        .ds = false,
        .acpi = false,
        .mmx = false,
        .fxsr = false,
        .sse = false,
        .sse2 = false,
        .ss = false,
        .htt = false,
        .tm = false,
        .pbe = false,
    })) == 0);

    // `@bitCast(BasicFeatureEdx, @as(u32, 0))` reconstructs an all-false
    // mask; check one representative field.
    const zero_mask: Cpuid.BasicFeatureEdx = @bitCast(@as(u32, 0));
    std.debug.assert(zero_mask.fpu == false);
    std.debug.assert(zero_mask.tsc == false);

    // Bundle sizes. Spec §Feature bundles.
    std.debug.assert(@sizeOf(Cpuid.BasicFeatures) == 8);
    std.debug.assert(@sizeOf(Cpuid.StructuredFeatures) == 12);
    std.debug.assert(@sizeOf(Cpuid.ExtendedFeatures) == 8);
    std.debug.assert(@sizeOf(Cpuid.Features) == 28);

    // `hasReserved` exists on every mask type with signature
    // `fn (mask) bool`.
    std.debug.assert(@TypeOf(Cpuid.BasicFeatureEdx.hasReserved) == fn (Cpuid.BasicFeatureEdx) bool);
    std.debug.assert(@TypeOf(Cpuid.BasicFeatureEcx.hasReserved) == fn (Cpuid.BasicFeatureEcx) bool);
    std.debug.assert(@TypeOf(Cpuid.StructuredEbx.hasReserved) == fn (Cpuid.StructuredEbx) bool);
    std.debug.assert(@TypeOf(Cpuid.StructuredEcx.hasReserved) == fn (Cpuid.StructuredEcx) bool);
    std.debug.assert(@TypeOf(Cpuid.StructuredEdx.hasReserved) == fn (Cpuid.StructuredEdx) bool);
    std.debug.assert(@TypeOf(Cpuid.ExtendedFeatureEdx.hasReserved) == fn (Cpuid.ExtendedFeatureEdx) bool);
    std.debug.assert(@TypeOf(Cpuid.ExtendedFeatureEcx.hasReserved) == fn (Cpuid.ExtendedFeatureEcx) bool);

    // Vendor enum: exactly seven tags in the documented order. Spec
    // §Vendor and version.
    const vendor_info = @typeInfo(Cpuid.Vendor).@"enum";
    std.debug.assert(vendor_info.fields.len == 7);
    std.debug.assert(std.mem.eql(u8, vendor_info.fields[0].name, "intel"));
    std.debug.assert(std.mem.eql(u8, vendor_info.fields[1].name, "amd"));
    std.debug.assert(std.mem.eql(u8, vendor_info.fields[6].name, "unknown"));

    // Cache.Kind: `enum(u5)` with `_` sentinel (i.e., non-exhaustive).
    // Spec §Cache topology.
    const kind_info = @typeInfo(Cpuid.Cache.Kind).@"enum";
    std.debug.assert(kind_info.tag_type == u5);
    std.debug.assert(!kind_info.is_exhaustive);
    std.debug.assert(@intFromEnum(Cpuid.Cache.Kind.null) == 0);
    std.debug.assert(@intFromEnum(Cpuid.Cache.Kind.data) == 1);
    std.debug.assert(@intFromEnum(Cpuid.Cache.Kind.instruction) == 2);
    std.debug.assert(@intFromEnum(Cpuid.Cache.Kind.unified) == 3);

    // Version field types match the spec's Approved API block.
    std.debug.assert(@FieldType(Cpuid.Version, "family") == u12);
    std.debug.assert(@FieldType(Cpuid.Version, "model") == u8);
    std.debug.assert(@FieldType(Cpuid.Version, "stepping") == u4);
    std.debug.assert(@FieldType(Cpuid.Version, "eax") == u32);

    // AddressSizes field types.
    std.debug.assert(@FieldType(Cpuid.AddressSizes, "physical_bits") == u8);
    std.debug.assert(@FieldType(Cpuid.AddressSizes, "linear_bits") == u8);
    std.debug.assert(@FieldType(Cpuid.AddressSizes, "guest_physical_bits") == u8);
}

// Compile-only accessor signatures: every asm-emitting accessor exists on
// x86_64 with the exact spec signature. On non-x86 builds the module still
// imports; only asm-emitting bodies would trigger `@compileError`, and none
// is referenced as a value here (function-type queries are comptime).

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "contract: Cpuid vendor/version/brand accessors instantiate" {
    if (!x86.supported) return;
    expectFn(fn () Cpuid.Vendor, Cpuid.vendor);
    expectFn(fn () [12]u8, Cpuid.vendorString);
    expectFn(fn () Cpuid.Version, Cpuid.version);
    expectFn(fn () ?[48]u8, Cpuid.brandString);
}

test "contract: Cpuid feature accessors instantiate" {
    if (!x86.supported) return;
    expectFn(fn () Cpuid.BasicFeatures, Cpuid.basicFeatures);
    expectFn(fn () Cpuid.StructuredFeatures, Cpuid.structuredFeatures);
    expectFn(fn () Cpuid.ExtendedFeatures, Cpuid.extendedFeatures);
    expectFn(fn () Cpuid.Features, Cpuid.features);
}

test "contract: Cpuid caches/addressSizes instantiate" {
    if (!x86.supported) return;
    expectFn(fn () Cpuid.Cache.Iterator, Cpuid.caches);
    expectFn(fn () Cpuid.AddressSizes, Cpuid.addressSizes);
    expectFn(fn (*Cpuid.Cache.Iterator) ?Cpuid.Cache.Descriptor, Cpuid.Cache.Iterator.next);
}

// Value-only model assertions that do not depend on the running CPU.

test "model: hasReserved returns true when a reserved bit is set" {
    // BasicFeatureEdx reserved bits are at positions 10, 20, 30. Set bit 10.
    const raw: u32 = 1 << 10;
    const mask: Cpuid.BasicFeatureEdx = @bitCast(raw);
    try testing.expect(mask.hasReserved());
    // Confirm round-trip preserves the bit.
    try testing.expectEqual(raw, @as(u32, @bitCast(mask)));
}

test "model: hasReserved is false on a zeroed mask" {
    const mask: Cpuid.BasicFeatureEdx = @bitCast(@as(u32, 0));
    try testing.expect(!mask.hasReserved());
}

test "model: BasicFeatureEcx round-trips a reserved bit at position 16" {
    // Ecx reserved bit is at 16.
    const raw: u32 = 1 << 16;
    const mask: Cpuid.BasicFeatureEcx = @bitCast(raw);
    try testing.expect(mask.hasReserved());
    try testing.expectEqual(raw, @as(u32, @bitCast(mask)));
}

test "model: ExtendedFeatureEdx wide reserved run sets hasReserved" {
    // ExtendedFeatureEdx bits 0..10 are all reserved. Set bit 0.
    const raw: u32 = 1 << 0;
    const mask: Cpuid.ExtendedFeatureEdx = @bitCast(raw);
    try testing.expect(mask.hasReserved());
}

// Host-safe runtime tests: non-x86 hosts early-return so the module still
// compiles.

test "unit: vendor returns intel, amd, or unknown" {
    if (builtin.cpu.arch != .x86_64) return;
    const v = Cpuid.vendor();
    try testing.expect(v == .intel or v == .amd or v == .unknown);
}

test "unit: vendorString matches vendor enum prefix" {
    if (builtin.cpu.arch != .x86_64) return;
    const s = Cpuid.vendorString();
    switch (Cpuid.vendor()) {
        .intel => try testing.expectEqualSlices(u8, "Genu", s[0..4]),
        .amd => try testing.expectEqualSlices(u8, "Auth", s[0..4]),
        else => {},
    }
}

test "unit: version.family is at least 6 on modern CPUs" {
    if (builtin.cpu.arch != .x86_64) return;
    const v = Cpuid.version();
    try testing.expect(v.family >= 6);
}

test "unit: basicFeatures FPU and TSC are true; reserved is clean" {
    if (builtin.cpu.arch != .x86_64) return;
    const bf = Cpuid.basicFeatures();
    try testing.expect(bf.edx.fpu);
    try testing.expect(bf.edx.tsc);
    try testing.expect(!bf.edx.hasReserved());
}

test "unit: features() bundle matches individual accessors" {
    if (builtin.cpu.arch != .x86_64) return;
    const bundle = Cpuid.features();
    const basic = Cpuid.basicFeatures();
    const structured = Cpuid.structuredFeatures();
    const extended = Cpuid.extendedFeatures();

    try testing.expectEqual(@as(u32, @bitCast(basic.edx)), @as(u32, @bitCast(bundle.basic.edx)));
    try testing.expectEqual(@as(u32, @bitCast(basic.ecx)), @as(u32, @bitCast(bundle.basic.ecx)));
    try testing.expectEqual(@as(u32, @bitCast(structured.ebx)), @as(u32, @bitCast(bundle.structured.ebx)));
    try testing.expectEqual(@as(u32, @bitCast(structured.ecx)), @as(u32, @bitCast(bundle.structured.ecx)));
    try testing.expectEqual(@as(u32, @bitCast(structured.edx)), @as(u32, @bitCast(bundle.structured.edx)));
    try testing.expectEqual(@as(u32, @bitCast(extended.edx)), @as(u32, @bitCast(bundle.extended.edx)));
    try testing.expectEqual(@as(u32, @bitCast(extended.ecx)), @as(u32, @bitCast(bundle.extended.ecx)));
}

test "unit: caches iterator produces well-formed L1 descriptor when populated" {
    if (builtin.cpu.arch != .x86_64) return;
    // Leaf 4 is Intel-defined; modern AMD implements it partially per
    // spec §Cache topology. On AMD hosts where leaf 4 is empty (Ryzen
    // returns all zeros, deferring topology to leaf 0x8000001D), the
    // iterator correctly returns null on the first call; skip the L1
    // shape assertion in that case per the spec's "when leaf 4 is
    // populated" wording.
    if (Cpuid.maxBasicLeaf() < 4) return;

    var it = Cpuid.caches();
    var seen_l1_64 = false;
    var count: u32 = 0;
    while (it.next()) |desc| : (count += 1) {
        try testing.expect(count < 32);
        try testing.expect(desc.level >= 1 and desc.level <= 4);
        try testing.expect(desc.line_size > 0);
        try testing.expect(desc.ways > 0);
        try testing.expect(desc.sets > 0);
        if (desc.level == 1 and desc.line_size == 64) seen_l1_64 = true;
    }
    // Spec required-test bullet: on hosts where leaf 4 is populated, at
    // least one descriptor is L1 with a 64-byte line. Hosts where leaf 4
    // returns 0 (Ryzen defers to leaf 0x8000001D) skip this bullet.
    if (count == 0) return;
    try testing.expect(seen_l1_64);
}

test "unit: brandString returns non-null printable ASCII on modern CPUs" {
    if (builtin.cpu.arch != .x86_64) return;
    const brand = Cpuid.brandString() orelse return error.TestSkipped;
    const trimmed = std.mem.sliceTo(&brand, 0);
    try testing.expect(trimmed.len > 0);
    for (trimmed) |c| {
        // Printable ASCII plus space per Intel SDM leaf 0x80000002..4.
        try testing.expect(c >= 0x20 and c <= 0x7E);
    }
}

test "unit: addressSizes physical_bits is between 32 and 57" {
    if (builtin.cpu.arch != .x86_64) return;
    const s = Cpuid.addressSizes();
    try testing.expect(s.physical_bits >= 32 and s.physical_bits <= 57);
}
