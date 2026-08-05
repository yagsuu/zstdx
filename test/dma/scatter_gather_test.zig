//! DMA scatter-gather contract tests.
//! See `docs/specs/dma/scatter_gather.md`.

const std = @import("std");

const stdx = @import("stdx");

const DMAAddr = stdx.addr.DMAAddr;
const Buffer = stdx.dma.Buffer;
const Sg = stdx.dma.ScatterGather;

const testing = std.testing;

fn seg(base: u64, len_bytes: DMAAddr.Raw) Sg.Segment {
    return .{ .addr = DMAAddr.fromInt(base), .len_bytes = len_bytes };
}

test "unit: Segment.init succeeds for a zero-length segment" {
    const s = try Sg.Segment.init(DMAAddr.fromInt(0xDEAD), 0);
    try testing.expect(s.isEmpty());
    try testing.expectEqual(@as(u64, 0), s.byteLen());
}

test "unit: Segment.init succeeds for a non-empty segment" {
    const s = try Sg.Segment.init(DMAAddr.fromInt(0x1000), 128);
    try testing.expectEqual(@as(u64, 128), s.byteLen());
    try testing.expect(!s.isEmpty());
}

test "unit: Segment.init returns Overflow when addr + len_bytes exceeds Address.Raw" {
    const near_max = DMAAddr.fromInt(std.math.maxInt(u64) - 10);
    try testing.expectError(error.Overflow, Sg.Segment.init(near_max, 20));
}

test "unit: Segment.fromBuffer matches buffer.dmaAddr and buffer.byteLen" {
    var backing: [4]u32 = undefined;
    const buf = try Buffer(u32).init(&backing, DMAAddr.fromInt(0x1000));
    const s = Sg.Segment.fromBuffer(u32, buf);
    try testing.expectEqual(buf.dmaAddr().raw(), s.addr.raw());
    try testing.expectEqual(buf.byteLen(), s.byteLen());
}

test "unit: Segment.endAddr returns addr + len_bytes for valid segments" {
    const s = try Sg.Segment.init(DMAAddr.fromInt(0x1000), 0x100);
    try testing.expectEqual(@as(u64, 0x1100), (try s.endAddr()).raw());
}

test "unit: Segment.endAddr returns Overflow for hand-constructed overflow" {
    const bad = seg(std.math.maxInt(u64) - 1, 10);
    try testing.expectError(error.Overflow, bad.endAddr());
}

test "unit: Segment.isAligned(1) accepts every segment" {
    try testing.expect(seg(0, 0).isAligned(1));
    try testing.expect(seg(1, 3).isAligned(1));
    try testing.expect(seg(0xABCDEF, 0xFEDCBA).isAligned(1));
}

test "unit: Segment.isAligned rejects invalid alignment values" {
    try testing.expect(!seg(0, 0).isAligned(0));
    try testing.expect(!seg(0x1000, 4096).isAligned(0));
    try testing.expect(!seg(0x1000, 4096).isAligned(3));
}

test "unit: Segment.isAligned checks both addr and byte length against alignment" {
    try testing.expect(seg(0x1000, 4096).isAligned(4096));
    try testing.expect(!seg(0x1001, 4096).isAligned(4096));
    try testing.expect(!seg(0x1000, 4097).isAligned(4096));
    try testing.expect(seg(0x1000, 512).isAligned(512));
}

test "unit: Segment.byteLen and isEmpty reflect len_bytes" {
    try testing.expect(seg(0x1000, 0).isEmpty());
    try testing.expect(!seg(0x1000, 1).isEmpty());
    try testing.expectEqual(@as(u64, 42), seg(0, 42).byteLen());
}

fn exerciseList(comptime L: type, list_ptr: *L) !void {
    try testing.expect(list_ptr.isEmpty());
    try testing.expectEqual(@as(usize, 3), list_ptr.capacity());

    try list_ptr.append(seg(0x1000, 64));
    try list_ptr.append(seg(0x2000, 128));
    try list_ptr.append(seg(0x3000, 32));
    try testing.expect(list_ptr.isFull());
    try testing.expectEqual(@as(usize, 3), list_ptr.len());

    try testing.expectError(error.Full, list_ptr.append(seg(0x4000, 8)));
    try testing.expectEqual(@as(usize, 3), list_ptr.len());

    try testing.expectEqual(@as(u64, 0x2000), (try list_ptr.at(1)).addr.raw());
    try testing.expectEqual(@as(u64, 0x3000), (try list_ptr.constAt(2)).addr.raw());
    try testing.expectError(error.OutOfBounds, list_ptr.at(3));

    try testing.expectEqual(@as(u64, 64 + 128 + 32), try list_ptr.totalByteLen());

    list_ptr.clearRetainingCapacity();
    try testing.expect(list_ptr.isEmpty());
    try testing.expectEqual(@as(usize, 3), list_ptr.capacity());
}

test "unit: List.Static exercises append/at/totalByteLen/clear" {
    var list = Sg.List.Static(3).init();
    try exerciseList(@TypeOf(list), &list);
}

test "unit: List.Bounded exercises the same sequence over borrowed storage" {
    var storage: [3]Sg.Segment = undefined;
    var list = Sg.List.Bounded.wrap(&storage);
    try exerciseList(@TypeOf(list), &list);
}

test "unit: List.Bounded with a zero-length backing slice is empty and full" {
    var storage: [0]Sg.Segment = .{};
    var list = Sg.List.Bounded.wrap(&storage);
    try testing.expect(list.isEmpty());
    try testing.expect(list.isFull());
    try testing.expectError(error.Full, list.append(seg(0, 0)));
}

test "unit: List.Static.appendAssumeCapacity mutates without checking" {
    var list = Sg.List.Static(2).init();
    list.appendAssumeCapacity(seg(0x1000, 16));
    try testing.expectEqual(@as(usize, 1), list.len());
}

test "unit: List.Static.appendBuffer combines fromBuffer and append" {
    var backing: [4]u32 = undefined;
    const buf = try Buffer(u32).init(&backing, DMAAddr.fromInt(0x1000));
    var list = Sg.List.Static(2).init();
    try list.appendBuffer(u32, buf);
    try testing.expectEqual(@as(usize, 1), list.len());
    try testing.expectEqual(@as(u64, 16), (try list.constAt(0)).byteLen());
    try testing.expectEqual(@as(u64, 0x1000), (try list.constAt(0)).addr.raw());
}

test "unit: List.totalByteLen returns Overflow on sum wraparound" {
    var storage: [2]Sg.Segment = undefined;
    var list = Sg.List.Bounded.wrap(&storage);
    try list.append(seg(0, std.math.maxInt(u64) - 3));
    try list.append(seg(0x1000, 8));
    try testing.expectError(error.Overflow, list.totalByteLen());
}

test "unit: Builder.Static(alignment=1) accepts every segment" {
    var b = Sg.Builder.Static(4, 1).init();
    try b.append(seg(0x1001, 3));
    try b.append(seg(0xABCDEF, 7));
    try testing.expectEqual(@as(usize, 2), b.len());
}

test "unit: Builder.Static(alignment=512) accepts aligned segments" {
    var b = Sg.Builder.Static(4, 512).init();
    try b.append(seg(0x1000, 512));
    try b.append(seg(0x1200, 1024));
    try testing.expectEqual(@as(usize, 2), b.len());
}

test "unit: Builder.Static returns Misaligned before Full" {
    var b = Sg.Builder.Static(1, 4096).init();
    try b.append(seg(0x1000, 4096));
    try testing.expect(b.isFull());
    try testing.expectError(error.Misaligned, b.append(seg(0x1001, 4096)));
    try testing.expectError(error.Full, b.append(seg(0x2000, 4096)));
    try testing.expectEqual(@as(usize, 1), b.len());
}

test "unit: Builder.Static.append leaves the list unchanged on Misaligned" {
    var b = Sg.Builder.Static(4, 4096).init();
    try b.append(seg(0x1000, 4096));
    try testing.expectError(error.Misaligned, b.append(seg(0x1001, 4096)));
    try testing.expectError(error.Misaligned, b.append(seg(0x2000, 4097)));
    try testing.expectEqual(@as(usize, 1), b.len());
}

test "unit: Builder.Static.appendBuffer inherits Misaligned and Full" {
    var page_backing: [4096]u8 align(4096) = undefined;
    const buf = try Buffer(u8).initAligned(&page_backing, DMAAddr.fromInt(0x1000), 4096);
    var b = Sg.Builder.Static(1, 4096).init();
    try b.appendBuffer(u8, buf);
    try testing.expectError(error.Full, b.appendBuffer(u8, buf));

    var small_backing: [8]u8 = undefined;
    const small = try Buffer(u8).init(&small_backing, DMAAddr.fromInt(0x2000));
    var b2 = Sg.Builder.Static(1, 4096).init();
    try testing.expectError(error.Misaligned, b2.appendBuffer(u8, small));
}

test "unit: Builder.Static.finish exposes the wrapped list contents" {
    var b = Sg.Builder.Static(4, 512).init();
    try b.append(seg(0x1000, 512));
    try b.append(seg(0x1800, 512));
    const list = b.finish();
    try testing.expectEqual(@as(usize, 2), list.len());
    try testing.expectEqual(@as(u64, 0x1800), (try list.constAt(1)).addr.raw());
}

test "unit: Builder.Bounded shares the same behavior over borrowed storage" {
    var storage: [4]Sg.Segment = undefined;
    var b = Sg.Builder.Bounded(4096).wrap(&storage);
    try b.append(seg(0x1000, 4096));
    try testing.expectError(error.Misaligned, b.append(seg(0x1001, 4096)));
    try b.append(seg(0x2000, 8192));
    try testing.expectEqual(@as(usize, 2), b.len());

    const list = b.finish();
    try testing.expectEqual(@as(u64, 0x2000), (try list.constAt(1)).addr.raw());
}

test "unit: Builder.clearRetainingCapacity delegates to the underlying list" {
    var b = Sg.Builder.Static(4, 512).init();
    try b.append(seg(0x1000, 512));
    try testing.expectEqual(@as(usize, 1), b.len());
    b.clearRetainingCapacity();
    try testing.expect(b.isEmpty());
    try testing.expectEqual(@as(usize, 4), b.capacity());
}

test "unit: Builder.assertValid accepts a well-formed builder" {
    var b = Sg.Builder.Static(4, 4096).init();
    try b.append(seg(0x1000, 4096));
    b.assertValid();
}
