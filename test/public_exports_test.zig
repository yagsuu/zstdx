//! Public facade export contract tests. Spec: docs/specs/root-exports.md.

const std = @import("std");

const zstdx = @import("zstdx");

const testing = std.testing;

test "contract: first-slice public exports are exact" {
    _ = zstdx.core.SafetyMode;
    _ = zstdx.core.Range;
    _ = zstdx.core.debug.checksEnabled;
    _ = zstdx.bits.isPowerOfTwo;
    _ = zstdx.bits.nextPowerOfTwo;
    _ = zstdx.bits.BitSet.Static;
    _ = zstdx.mem.alignUp;
    _ = zstdx.mem.alignDown;
    _ = zstdx.mem.isAligned;
    _ = zstdx.mem.FixedBufferArena;
    _ = zstdx.addr.Address;
    _ = zstdx.addr.PhysAddr;
    _ = zstdx.addr.VirtAddr;
    _ = zstdx.layout.unalignedLoad;
    _ = zstdx.layout.unalignedStore;
    _ = zstdx.layout.EndianInt;
    _ = zstdx.layout.Le;
    _ = zstdx.layout.Be;
    _ = zstdx.bytes.Cursor;
    _ = zstdx.List.Static;
    _ = zstdx.List.Bounded;
    _ = zstdx.Ring.Static;

    try testing.expect(!@hasDecl(zstdx.bits, "BitFlags"));
    try testing.expect(!@hasDecl(zstdx.mem, "BumpAllocator"));
    try testing.expect(!@hasDecl(zstdx.core, "traits"));
    try testing.expect(!@hasDecl(zstdx, "intrusive"));
    try testing.expect(!@hasDecl(zstdx.Ring, "Bounded"));
}
