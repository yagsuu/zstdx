//! Public facade export contract tests. Spec: docs/specs/root-exports.md.

const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;

test "contract: first-slice public exports are exact" {
    _ = stdx.core.SafetyMode;
    _ = stdx.core.Range;
    _ = stdx.core.debug.checksEnabled;
    _ = stdx.core.Order;
    _ = stdx.core.Compare;
    _ = stdx.core.LessThan;
    _ = stdx.core.Eql;
    _ = stdx.core.Hash;
    _ = stdx.bits.isPowerOfTwo;
    _ = stdx.bits.nextPowerOfTwo;
    _ = stdx.bits.BitSet.Static;
    _ = stdx.mem.alignUp;
    _ = stdx.mem.alignDown;
    _ = stdx.mem.isAligned;
    _ = stdx.mem.Arena;
    _ = stdx.mem.Arena.Bounded;
    _ = stdx.mem.Arena.Static;
    _ = stdx.mem.Pool;
    _ = stdx.mem.Pool.Static;
    _ = stdx.mem.Pool.Bounded;
    _ = stdx.addr.Address;
    _ = stdx.addr.PhysAddr;
    _ = stdx.addr.VirtAddr;
    _ = stdx.addr.Page;
    _ = stdx.addr.pages._4kib;
    _ = stdx.ranges.RangeSet;
    _ = stdx.ranges.RangeMap;
    _ = stdx.bytes.loadUnaligned;
    _ = stdx.bytes.storeUnaligned;
    _ = stdx.bytes.load;
    _ = stdx.bytes.store;
    _ = stdx.bytes.loadSlice;
    _ = stdx.bytes.storeSlice;
    _ = stdx.bytes.loadTail;
    _ = stdx.layout.EndianInt;
    _ = stdx.layout.Le;
    _ = stdx.layout.Be;
    _ = stdx.bytes.Cursor;
    _ = stdx.List.Static;
    _ = stdx.List.Bounded;
    _ = stdx.Ring.Static;
    _ = stdx.Ring.Bounded;
    _ = stdx.intrusive.List;
    _ = stdx.intrusive.Queue;
    _ = stdx.intrusive.Stack;

    try testing.expect(!@hasDecl(stdx.bits, "BitFlags"));
    try testing.expect(!@hasDecl(stdx.mem, "BumpAllocator"));
    try testing.expect(!@hasDecl(stdx.core, "traits"));
    try testing.expect(!@hasDecl(stdx, "Page"));
    try testing.expect(!@hasDecl(stdx, "RangeSet"));
    try testing.expect(!@hasDecl(stdx, "RangeMap"));
    try testing.expect(!@hasDecl(stdx, "Queue"));
    try testing.expect(!@hasDecl(stdx, "Stack"));
    try testing.expect(!@hasDecl(stdx, "SinglyLinkedList"));
    try testing.expect(!@hasDecl(stdx, "DoublyLinkedList"));
    try testing.expect(!@hasDecl(stdx, "io"));
    try testing.expect(!@hasDecl(stdx, "Pool"));
}
