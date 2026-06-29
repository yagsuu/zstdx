//! Public facade export contract tests. Spec: docs/specs/root-exports.md.

const std = @import("std");

const zstdx = @import("zstdx");

const testing = std.testing;

test "contract: first-slice public exports are exact" {
    _ = zstdx.core.SafetyMode;
    _ = zstdx.core.Range;
    _ = zstdx.core.debug.checksEnabled;
    _ = zstdx.core.Order;
    _ = zstdx.core.Compare;
    _ = zstdx.core.LessThan;
    _ = zstdx.core.Eql;
    _ = zstdx.core.Hash;
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
    _ = zstdx.addr.Page;
    _ = zstdx.addr.pages._4kib;
    _ = zstdx.ranges.RangeSet;
    _ = zstdx.ranges.RangeMap;
    _ = zstdx.bytes.loadUnaligned;
    _ = zstdx.bytes.storeUnaligned;
    _ = zstdx.bytes.load;
    _ = zstdx.bytes.store;
    _ = zstdx.bytes.loadSlice;
    _ = zstdx.bytes.storeSlice;
    _ = zstdx.bytes.loadTail;
    _ = zstdx.layout.EndianInt;
    _ = zstdx.layout.Le;
    _ = zstdx.layout.Be;
    _ = zstdx.bytes.Cursor;
    _ = zstdx.List.Static;
    _ = zstdx.List.Bounded;
    _ = zstdx.Ring.Static;
    _ = zstdx.Ring.Bounded;
    _ = zstdx.intrusive.List;
    _ = zstdx.intrusive.Queue;
    _ = zstdx.intrusive.Stack;

    try testing.expect(!@hasDecl(zstdx.bits, "BitFlags"));
    try testing.expect(!@hasDecl(zstdx.mem, "BumpAllocator"));
    try testing.expect(!@hasDecl(zstdx.core, "traits"));
    try testing.expect(!@hasDecl(zstdx, "Page"));
    try testing.expect(!@hasDecl(zstdx, "RangeSet"));
    try testing.expect(!@hasDecl(zstdx, "RangeMap"));
    try testing.expect(!@hasDecl(zstdx, "Queue"));
    try testing.expect(!@hasDecl(zstdx, "Stack"));
    try testing.expect(!@hasDecl(zstdx, "SinglyLinkedList"));
    try testing.expect(!@hasDecl(zstdx, "DoublyLinkedList"));
    try testing.expect(!@hasDecl(zstdx, "io"));
}
