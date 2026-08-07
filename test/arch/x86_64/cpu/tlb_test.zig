const std = @import("std");
const x86 = @import("stdx").arch.x86_64;
const tlb = x86.cpu.tlb;

const testing = std.testing;

comptime {
    std.debug.assert(@sizeOf(tlb.INVPCIDDescriptor) == 16);
    std.debug.assert(@alignOf(tlb.INVPCIDDescriptor) == 16);
    std.debug.assert(@offsetOf(tlb.INVPCIDDescriptor, "pcid") == 0);
    std.debug.assert(@offsetOf(tlb.INVPCIDDescriptor, "linear_address") == 8);
    std.debug.assert(tlb.INVPCIDDescriptor.alignment == 16);

    const kind_info = @typeInfo(tlb.INVPCIDKind).@"enum";
    std.debug.assert(kind_info.fields.len == 4);
    std.debug.assert(kind_info.tag_type == u2);
    std.debug.assert(@intFromEnum(tlb.INVPCIDKind.individual_address) == 0);
    std.debug.assert(@intFromEnum(tlb.INVPCIDKind.single_context) == 1);
    std.debug.assert(@intFromEnum(tlb.INVPCIDKind.all_including_globals) == 2);
    std.debug.assert(@intFromEnum(tlb.INVPCIDKind.all_excluding_globals) == 3);
}

test "contract: TLB invalidation wrappers instantiate" {
    if (!x86.supported) return;
    comptime {
        testing.expectEqual(fn (usize) void, @TypeOf(tlb.invalidatePage)) catch unreachable;
        testing.expectEqual(fn (tlb.INVPCIDKind, *const tlb.INVPCIDDescriptor) void, @TypeOf(tlb.invalidatePCID)) catch unreachable;
    }
}
