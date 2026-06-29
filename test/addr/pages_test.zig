//! Page primitive contract tests. Spec: docs/specs/addr/pages.md.

const std = @import("std");

const stdx = @import("stdx");
const addr = stdx.addr;

const testing = std.testing;

const Tag64 = opaque {};
const Tag8 = opaque {};
const A64 = addr.Address(Tag64, u64);
const A8 = addr.Address(Tag8, u8);
const Phys4K = addr.Page(addr.PhysAddr, addr.pages._4kib);
const Virt4K = addr.Page(addr.VirtAddr, addr.pages._4kib);
const A64_4K = addr.Page(A64, addr.pages._4kib);
const A8_4 = addr.Page(A8, 4);

test "unit: page constants are exact byte counts" {
    try testing.expectEqual(@as(comptime_int, 4096), addr.pages._4kib);
    try testing.expectEqual(@as(comptime_int, 16 * 1024), addr.pages._16kib);
    try testing.expectEqual(@as(comptime_int, 64 * 1024), addr.pages._64kib);
    try testing.expectEqual(@as(comptime_int, 2 * 1024 * 1024), addr.pages._2mib);
    try testing.expectEqual(@as(comptime_int, 1024 * 1024 * 1024), addr.pages._1gib);
}

test "unit: page size metadata and family identity are stable" {
    try testing.expectEqual(@as(A8.Raw, 4), A8_4.Size.bytes);
    try testing.expectEqual(@as(A8.Raw, 3), A8_4.Size.mask);
    try testing.expectEqual(@as(comptime_int, 2), A8_4.Size.shift);
    try testing.expect(@TypeOf(Phys4K.Frame.fromAddressInt(0) catch unreachable) != @TypeOf(Virt4K.Frame.fromAddressInt(0) catch unreachable));
    const Phys2M = addr.Page(addr.PhysAddr, addr.pages._2mib);
    try testing.expect(Phys4K.Frame != Phys2M.Frame);
    _ = A64_4K;
}

test "unit: Count converts pages and bytes with checked arithmetic" {
    try testing.expectEqual(@as(u8, 0), A8_4.Count.zero().pages());
    try testing.expectEqual(std.math.maxInt(u8), A8_4.Count.max().pages());
    try testing.expectEqual(@as(u8, 3), A8_4.Count.fromPages(3).pages());
    try testing.expectEqual(@as(u8, 0), (try A8_4.Count.fromBytesExact(0)).pages());
    try testing.expectEqual(@as(u8, 2), (try A8_4.Count.fromBytesExact(8)).pages());
    try testing.expectError(error.Misaligned, A8_4.Count.fromBytesExact(5));
    try testing.expectEqual(@as(u8, 0), (try A8_4.Count.fromBytesRoundUp(0)).pages());
    try testing.expectEqual(@as(u8, 1), (try A8_4.Count.fromBytesRoundUp(1)).pages());
    try testing.expectEqual(@as(u8, 1), (try A8_4.Count.fromBytesRoundUp(4)).pages());
    try testing.expectEqual(@as(u8, 2), (try A8_4.Count.fromBytesRoundUp(5)).pages());
    try testing.expectError(error.Overflow, A8_4.Count.fromBytesRoundUp(254));
    try testing.expectEqual(@as(u8, 12), try A8_4.Count.fromPages(3).toBytes());
    try testing.expectError(error.Overflow, A8_4.Count.max().toBytes());
}

test "unit: Frame validates alignment and indexes aligned addresses" {
    const frame = try Phys4K.Frame.fromAddressInt(0x1000);
    try testing.expectEqual(@as(u64, 0x1000), frame.addressInt());
    try testing.expectEqual(@as(u64, 1), frame.index());
    try testing.expectEqual(@as(u64, 0x1000), frame.address().raw());
    try testing.expectError(error.Misaligned, Phys4K.Frame.fromAddressInt(1));
    try testing.expect(Phys4K.Frame.isAlignedAddress(addr.PhysAddr.fromInt(0x2000)));
    try testing.expect(!Phys4K.Frame.isAlignedAddress(addr.PhysAddr.fromInt(0x2001)));
    try testing.expectEqual(@as(u64, 0x2000), (try Phys4K.Frame.containingAddress(addr.PhysAddr.fromInt(0x2fff))).addressInt());
    try testing.expectEqual(@as(u64, 0x3000), (try Phys4K.Frame.nextAlignedAddress(addr.PhysAddr.fromInt(0x2001))).addressInt());
    try testing.expectError(error.Overflow, A8_4.Frame.nextAlignedAddress(A8.fromInt(254)));
    frame.assertValid();
}

test "unit: Frame arithmetic checks overflow and underflow" {
    const frame = try A8_4.Frame.fromAddressInt(8);
    try testing.expectEqual(@as(u8, 16), (try frame.add(A8_4.Count.fromPages(2))).addressInt());
    try testing.expectEqual(@as(u8, 4), (try frame.sub(A8_4.Count.fromPages(1))).addressInt());
    try testing.expectError(error.Overflow, (try A8_4.Frame.fromAddressInt(252)).add(A8_4.Count.fromPages(1)));
    try testing.expectError(error.Overflow, frame.sub(A8_4.Count.fromPages(3)));
}

test "unit: FrameRange constructs from base, bytes, and spans" {
    const base = try A8_4.Frame.fromAddressInt(8);
    const range = try A8_4.FrameRange.fromBaseCount(base, A8_4.Count.fromPages(3));
    try testing.expect(range.isValid());
    try testing.expect(!range.isEmpty());
    try testing.expectEqual(@as(u8, 12), range.byteLen());
    try testing.expectEqual(@as(u8, 20), range.end().addressInt());
    try testing.expectError(error.Overflow, A8_4.FrameRange.fromBaseCount(try A8_4.Frame.fromAddressInt(252), A8_4.Count.fromPages(2)));

    const from_bytes = try A8_4.FrameRange.fromAddressBytes(A8.fromInt(8), 8);
    try testing.expectEqual(@as(u8, 2), from_bytes.count.pages());
    try testing.expectError(error.Misaligned, A8_4.FrameRange.fromAddressBytes(A8.fromInt(9), 4));
    try testing.expectError(error.Misaligned, A8_4.FrameRange.fromAddressBytes(A8.fromInt(8), 5));

    const span = try Phys4K.FrameRange.fromAddressByteSpan(addr.PhysAddr.fromInt(0x1001), 1);
    try testing.expectEqual(@as(u64, 0x1000), span.base.addressInt());
    try testing.expectEqual(@as(u64, 1), span.count.pages());
}

test "unit: FrameRange containment overlap adjacency and intersection are half-open" {
    const frame = A8_4.Frame.fromAddressInt;
    const left = try A8_4.FrameRange.fromBaseCount(try frame(8), A8_4.Count.fromPages(3));
    const right = try A8_4.FrameRange.fromBaseCount(try frame(20), A8_4.Count.fromPages(2));
    const middle = try A8_4.FrameRange.fromBaseCount(try frame(12), A8_4.Count.fromPages(2));
    const empty = A8_4.FrameRange.empty(try frame(20));

    try testing.expect(left.containsFrame(try frame(8)));
    try testing.expect(!left.containsFrame(try frame(20)));
    try testing.expect(left.containsAddress(A8.fromInt(19)));
    try testing.expect(!left.containsAddress(A8.fromInt(20)));
    try testing.expect(left.containsFrameRange(middle));
    try testing.expect(left.containsFrameRange(empty));
    try testing.expect(!left.overlaps(right));
    try testing.expect(left.isAdjacent(right));
    try testing.expect(!left.overlaps(empty));
    try testing.expectEqual(@as(?A8_4.FrameRange, null), left.intersection(right));
    try testing.expectEqual(middle, left.intersection(middle).?);
    try testing.expectEqual(@as(u8, 8), left.span(right).base.addressInt());
    try testing.expectEqual(@as(u8, 5), left.span(right).count.pages());
}

test "unit: FrameRange splitAt accepts boundaries and rejects outside" {
    const base = try A8_4.Frame.fromAddressInt(8);
    const range = try A8_4.FrameRange.fromBaseCount(base, A8_4.Count.fromPages(3));
    const middle = try A8_4.Frame.fromAddressInt(12);
    const split = try range.splitAt(middle);
    try testing.expectEqual(@as(u8, 1), split.left.count.pages());
    try testing.expectEqual(@as(u8, 2), split.right.count.pages());
    try testing.expectEqual(@as(u8, 12), split.right.base.addressInt());
    try testing.expectEqual(@as(u8, 0), (try range.splitAt(base)).left.count.pages());
    try testing.expectEqual(@as(u8, 0), (try range.splitAt(range.end())).right.count.pages());
    try testing.expectError(error.OutOfBounds, range.splitAt(try A8_4.Frame.fromAddressInt(4)));
    try testing.expectError(error.OutOfBounds, range.splitAt(try A8_4.Frame.fromAddressInt(24)));
}

test "unit: Page comptime use works for small address family" {
    comptime {
        const P = addr.Page(A8, 4);
        if (P.Size.bytes != 4) @compileError("unexpected page size");
        if (P.Size.mask != 3) @compileError("unexpected page mask");
        if (P.Size.shift != 2) @compileError("unexpected page shift");
        const frame = P.Frame.fromAddressInt(8) catch unreachable;
        if (frame.index() != 2) @compileError("unexpected frame index");
        const count = P.Count.fromBytesRoundUp(7) catch unreachable;
        if (count.pages() != 2) @compileError("unexpected page count");
    }
}
