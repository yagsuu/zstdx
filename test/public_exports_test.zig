//! Public facade export contract tests. Spec: docs/specs/root-exports.md.

const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;

test "contract: first-slice public exports are exact" {
    // Root domain namespaces.
    _ = stdx.core;
    _ = stdx.bits;
    _ = stdx.addr;
    _ = stdx.layout;
    _ = stdx.bytes;
    _ = stdx.mem;
    _ = stdx.collections;
    _ = stdx.intrusive;
    _ = stdx.ranges;

    // Root-promoted flagship families.
    _ = stdx.List;
    _ = stdx.List.Static;
    _ = stdx.List.Bounded;
    _ = stdx.Ring;
    _ = stdx.Ring.Static;
    _ = stdx.Ring.Bounded;

    // core
    _ = stdx.core.SafetyMode;
    _ = stdx.core.Range;
    _ = stdx.core.debug;
    _ = stdx.core.debug.checksEnabled;
    _ = stdx.core.Order;
    _ = stdx.core.Compare;
    _ = stdx.core.LessThan;
    _ = stdx.core.Eql;
    _ = stdx.core.Hash;

    // bits
    _ = stdx.bits.power_of_two;
    _ = stdx.bits.isPowerOfTwo;
    _ = stdx.bits.nextPowerOfTwo;
    _ = stdx.bits.BitSet;
    _ = stdx.bits.BitSet.Static;

    // mem
    _ = stdx.mem.alignment;
    _ = stdx.mem.alignUp;
    _ = stdx.mem.alignDown;
    _ = stdx.mem.isAligned;
    _ = stdx.mem.alignUpDelta;
    _ = stdx.mem.alignDownDelta;
    _ = stdx.mem.arena;
    _ = stdx.mem.Arena;
    _ = stdx.mem.Arena.Bounded;
    _ = stdx.mem.Arena.Static;
    _ = stdx.mem.pool;
    _ = stdx.mem.Pool;
    _ = stdx.mem.Pool.Static;
    _ = stdx.mem.Pool.Bounded;

    // addr
    _ = stdx.addr.address;
    _ = stdx.addr.Address;
    _ = stdx.addr.PhysAddr;
    _ = stdx.addr.VirtAddr;
    _ = stdx.addr.pages;
    _ = stdx.addr.Page;
    _ = stdx.addr.pages._4kib;
    _ = stdx.addr.pages._16kib;
    _ = stdx.addr.pages._64kib;
    _ = stdx.addr.pages._2mib;
    _ = stdx.addr.pages._1gib;

    // layout
    _ = stdx.layout.endian;
    _ = stdx.layout.EndianInt;
    _ = stdx.layout.Le;
    _ = stdx.layout.Be;

    // bytes
    _ = stdx.bytes.unaligned;
    _ = stdx.bytes.loadUnaligned;
    _ = stdx.bytes.storeUnaligned;
    _ = stdx.bytes.access;
    _ = stdx.bytes.load;
    _ = stdx.bytes.store;
    _ = stdx.bytes.loadSlice;
    _ = stdx.bytes.storeSlice;
    _ = stdx.bytes.loadTail;
    _ = stdx.bytes.cursor;
    _ = stdx.bytes.Cursor;

    // ranges
    _ = stdx.ranges.set;
    _ = stdx.ranges.map;
    _ = stdx.ranges.RangeSet;
    _ = stdx.ranges.RangeMap;

    // collections
    _ = stdx.collections.list;
    _ = stdx.collections.ring;
    _ = stdx.collections.List;
    _ = stdx.collections.Ring;

    // intrusive
    _ = stdx.intrusive.list;
    _ = stdx.intrusive.queue;
    _ = stdx.intrusive.stack;
    _ = stdx.intrusive.List;
    _ = stdx.intrusive.Queue;
    _ = stdx.intrusive.Stack;

    // Negative checks: names that specs keep absent from root.
    try testing.expect(!@hasDecl(stdx, "Page"));
    try testing.expect(!@hasDecl(stdx, "PhysAddr"));
    try testing.expect(!@hasDecl(stdx, "VirtAddr"));
    try testing.expect(!@hasDecl(stdx, "Address"));
    try testing.expect(!@hasDecl(stdx, "RangeSet"));
    try testing.expect(!@hasDecl(stdx, "RangeMap"));
    try testing.expect(!@hasDecl(stdx, "Queue"));
    try testing.expect(!@hasDecl(stdx, "Stack"));
    try testing.expect(!@hasDecl(stdx, "SinglyLinkedList"));
    try testing.expect(!@hasDecl(stdx, "DoublyLinkedList"));
    try testing.expect(!@hasDecl(stdx, "Pool"));
    try testing.expect(!@hasDecl(stdx, "Arena"));
    try testing.expect(!@hasDecl(stdx, "BitSet"));
    try testing.expect(!@hasDecl(stdx, "Cursor"));
    try testing.expect(!@hasDecl(stdx, "EndianInt"));
    try testing.expect(!@hasDecl(stdx, "Le"));
    try testing.expect(!@hasDecl(stdx, "Be"));
    try testing.expect(!@hasDecl(stdx, "Range"));
    try testing.expect(!@hasDecl(stdx, "Order"));
    try testing.expect(!@hasDecl(stdx, "Compare"));
    try testing.expect(!@hasDecl(stdx, "LessThan"));
    try testing.expect(!@hasDecl(stdx, "Eql"));
    try testing.expect(!@hasDecl(stdx, "Hash"));
    try testing.expect(!@hasDecl(stdx, "SafetyMode"));
    try testing.expect(!@hasDecl(stdx, "alignUp"));
    try testing.expect(!@hasDecl(stdx, "alignDown"));
    try testing.expect(!@hasDecl(stdx, "isAligned"));
    try testing.expect(!@hasDecl(stdx, "isPowerOfTwo"));
    try testing.expect(!@hasDecl(stdx, "nextPowerOfTwo"));
    try testing.expect(!@hasDecl(stdx, "loadUnaligned"));
    try testing.expect(!@hasDecl(stdx, "storeUnaligned"));
    try testing.expect(!@hasDecl(stdx, "load"));
    try testing.expect(!@hasDecl(stdx, "store"));
    try testing.expect(!@hasDecl(stdx, "loadSlice"));
    try testing.expect(!@hasDecl(stdx, "storeSlice"));
    try testing.expect(!@hasDecl(stdx, "loadTail"));
    try testing.expect(!@hasDecl(stdx, "io"));

    // Namespace-scoped negatives.
    try testing.expect(!@hasDecl(stdx.bits, "BitFlags"));
    try testing.expect(!@hasDecl(stdx.mem, "BumpAllocator"));
    try testing.expect(!@hasDecl(stdx.core, "traits"));
}
