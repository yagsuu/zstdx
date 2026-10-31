//! host-safe CPUID query integration.

const std = @import("std");
const stdx = @import("stdx");

const x86 = stdx.arch.x86_64;
const cpuid = x86.cpuid;
const testing = std.testing;

test "vendor bytes follow architectural register order" {
    if (!x86.supported) {
        return;
    }

    const identity = cpuid.query(.max_basic, 0);
    const vendor = cpuid.vendorString();

    try testing.expectEqual(identity.ebx, std.mem.readInt(u32, vendor[0..4], .little));
    try testing.expectEqual(identity.edx, std.mem.readInt(u32, vendor[4..8], .little));
    try testing.expectEqual(identity.ecx, std.mem.readInt(u32, vendor[8..12], .little));
}

test "brand and address widths match available extended leaves" {
    if (!x86.supported) {
        return;
    }

    const maximum = cpuid.maxExtendedLeaf();
    const brand = cpuid.brandString();
    const widths = cpuid.addressSizes();

    if (maximum >= cpuid.Leaf.brand_3.raw()) {
        const bytes = brand.?;
        inline for (.{ cpuid.Leaf.brand_1, cpuid.Leaf.brand_2, cpuid.Leaf.brand_3 }, 0..) |which, index| {
            const raw = cpuid.query(which, 0);
            const block = bytes[index * 16 ..][0..16];

            try testing.expectEqual(raw.eax, std.mem.readInt(u32, block[0..4], .little));
            try testing.expectEqual(raw.ebx, std.mem.readInt(u32, block[4..8], .little));
            try testing.expectEqual(raw.ecx, std.mem.readInt(u32, block[8..12], .little));
            try testing.expectEqual(raw.edx, std.mem.readInt(u32, block[12..16], .little));
        }
    } else {
        try testing.expectEqual(@as(?[48]u8, null), brand);
    }

    if (maximum >= cpuid.Leaf.address_sizes.raw()) {
        const raw = cpuid.query(.address_sizes, 0);

        try testing.expectEqual(raw.eax & 0xFF, @as(u32, widths.physical_bits));
        try testing.expectEqual((raw.eax >> 8) & 0xFF, @as(u32, widths.linear_bits));
        try testing.expectEqual((raw.eax >> 16) & 0xFF, @as(u32, widths.guest_physical_bits));
    } else {
        try testing.expectEqual(cpuid.AddressSizes{
            .physical_bits = 32,
            .linear_bits = 32,
            .guest_physical_bits = 0,
        }, widths);
    }
}

test "leaf four iteration follows raw subleaves through the terminator" {
    if (!x86.supported) {
        return;
    }

    var iterator = cpuid.caches();
    if (cpuid.maxBasicLeaf() < cpuid.Leaf.cache_parameters.raw()) {
        const descriptor = iterator.next();

        try testing.expectEqual(@as(?cpuid.Cache.Descriptor, null), descriptor);
        return;
    }

    var index: u32 = 0;
    while (iterator.next()) |descriptor| : (index += 1) {
        const raw = cpuid.query(.cache_parameters, index);

        try testing.expectEqual(raw, cpuid.Result{
            .eax = descriptor.eax,
            .ebx = descriptor.ebx,
            .ecx = descriptor.ecx,
            .edx = descriptor.edx,
        });
        try testing.expect(raw.eax & 31 != 0);
    }

    const terminator = cpuid.query(.cache_parameters, index);
    const exhausted = iterator.next();

    try testing.expectEqual(@as(u32, 0), terminator.eax & 31);
    try testing.expectEqual(index, iterator.subleaf);
    try testing.expectEqual(@as(?cpuid.Cache.Descriptor, null), exhausted);
}
