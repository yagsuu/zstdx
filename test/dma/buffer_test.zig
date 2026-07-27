//! DMA buffer contract tests. Spec: docs/specs/dma/buffer.md.

const std = @import("std");

const stdx = @import("stdx");

const DMAAddr = stdx.addr.DMAAddr;
const Buffer = stdx.dma.Buffer;

const testing = std.testing;

const WireEntry = extern struct {
    a: u32,
    b: u32,
};

test "unit: Buffer(u8).init accepts an empty slice at any dma address" {
    var backing: [0]u8 = .{};
    const buf = try Buffer(u8).init(&backing, DMAAddr.fromInt(0xDEAD));
    try testing.expect(buf.isEmpty());
    try testing.expectEqual(@as(usize, 0), buf.len());
    try testing.expectEqual(@as(u64, 0), buf.byteLen());
    try testing.expectEqual(@as(u64, 0xDEAD), buf.dmaAddr().raw());
}

test "unit: Buffer(u8).init pairs slice and dma address" {
    var backing: [8]u8 = undefined;
    const buf = try Buffer(u8).init(&backing, DMAAddr.fromInt(0x1000));
    try testing.expectEqual(@as(usize, 8), buf.len());
    try testing.expectEqual(@as(u64, 8), buf.byteLen());
    try testing.expectEqual(@as(u64, 0x1000), buf.dmaAddr().raw());
}

test "unit: Buffer(u32) enforces @alignOf(T) on the dma address" {
    var backing: [4]u32 = undefined;
    try testing.expectError(error.Misaligned, Buffer(u32).init(&backing, DMAAddr.fromInt(0x1001)));
    try testing.expectError(error.Misaligned, Buffer(u32).init(&backing, DMAAddr.fromInt(0x1002)));
    _ = try Buffer(u32).init(&backing, DMAAddr.fromInt(0x1000));
}

test "unit: Buffer(u32).byteLen scales by @sizeOf(T)" {
    var backing: [4]u32 = undefined;
    const buf = try Buffer(u32).init(&backing, DMAAddr.fromInt(0x1000));
    try testing.expectEqual(@as(usize, 4), buf.len());
    try testing.expectEqual(@as(u64, 16), buf.byteLen());
}

test "unit: Buffer(WireEntry) works over an extern struct" {
    var backing: [2]WireEntry = undefined;
    const buf = try Buffer(WireEntry).init(&backing, DMAAddr.fromInt(0x2000));
    try testing.expectEqual(@as(usize, 2), buf.len());
    try testing.expectEqual(@as(u64, 2 * @sizeOf(WireEntry)), buf.byteLen());
    try testing.expectError(error.Misaligned, Buffer(WireEntry).init(&backing, DMAAddr.fromInt(0x2001)));
}

test "unit: Buffer.init rejects byte-length that overflows Address.Raw at the end" {
    var backing: [4]u8 = undefined;
    const near_max = DMAAddr.fromInt(std.math.maxInt(u64) - 2);
    try testing.expectError(error.Overflow, Buffer(u8).init(&backing, near_max));
}

test "unit: Buffer.initAligned rejects zero and non-power-of-two alignment" {
    var backing: [4]u8 = undefined;
    const dma = DMAAddr.fromInt(0x1000);
    try testing.expectError(error.Misaligned, Buffer(u8).initAligned(&backing, dma, 0));
    try testing.expectError(error.Misaligned, Buffer(u8).initAligned(&backing, dma, 3));
    try testing.expectError(error.Misaligned, Buffer(u8).initAligned(&backing, dma, 6));
}

test "unit: Buffer.initAligned enforces stricter runtime alignment" {
    var backing: [8]u8 = undefined;
    try testing.expectError(error.Misaligned, Buffer(u8).initAligned(&backing, DMAAddr.fromInt(0x1008), 16));
    _ = try Buffer(u8).initAligned(&backing, DMAAddr.fromInt(0x1000), 16);
}

test "unit: Buffer.initAligned equals Buffer.init at @alignOf(T)" {
    var backing: [4]u32 = undefined;
    const dma = DMAAddr.fromInt(0x1000);
    const a = try Buffer(u32).init(&backing, dma);
    const b = try Buffer(u32).initAligned(&backing, dma, @alignOf(u32));
    try testing.expectEqual(a.len(), b.len());
    try testing.expectEqual(a.dmaAddr().raw(), b.dmaAddr().raw());
}

test "unit: Buffer.initAligned(alignment=1) still enforces the type alignment" {
    var backing: [4]u32 = undefined;
    try testing.expectError(error.Misaligned, Buffer(u32).initAligned(&backing, DMAAddr.fromInt(0x1001), 1));
    _ = try Buffer(u32).initAligned(&backing, DMAAddr.fromInt(0x1000), 1);
}

test "unit: Buffer accessors mirror the underlying slice" {
    var backing: [3]u16 = .{ 1, 2, 3 };
    var buf = try Buffer(u16).init(&backing, DMAAddr.fromInt(0x1000));
    try testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, buf.constSlice());
    buf.slice()[0] = 9;
    try testing.expectEqual(@as(u16, 9), backing[0]);

    const b = buf.bytes();
    try testing.expectEqual(buf.byteLen(), b.len);
    const cb = buf.constBytes();
    try testing.expectEqual(buf.byteLen(), cb.len);
}

test "unit: Buffer.dmaAddr and dmaAddrAt agree at zero offset" {
    var backing: [4]u32 = undefined;
    const buf = try Buffer(u32).init(&backing, DMAAddr.fromInt(0x1000));
    try testing.expectEqual(buf.dmaAddr().raw(), (try buf.dmaAddrAt(0)).raw());
}

test "unit: Buffer.dmaAddrAt scales by @sizeOf(T)" {
    var backing: [4]u32 = undefined;
    const buf = try Buffer(u32).init(&backing, DMAAddr.fromInt(0x1000));
    try testing.expectEqual(@as(u64, 0x1000 + 4), (try buf.dmaAddrAt(1)).raw());
    try testing.expectEqual(@as(u64, 0x1000 + 8), (try buf.dmaAddrAt(2)).raw());
    try testing.expectEqual(@as(u64, 0x1000 + 16), (try buf.dmaAddrAt(4)).raw());
}

test "unit: Buffer.dmaAddrAt rejects offsets past virt.len" {
    var backing: [4]u32 = undefined;
    const buf = try Buffer(u32).init(&backing, DMAAddr.fromInt(0x1000));
    try testing.expectError(error.OutOfBounds, buf.dmaAddrAt(5));
    try testing.expectError(error.OutOfBounds, buf.dmaAddrAt(std.math.maxInt(usize)));
}

test "unit: Buffer.sub full range is value-equal to the source" {
    var backing: [4]u32 = undefined;
    const buf = try Buffer(u32).init(&backing, DMAAddr.fromInt(0x1000));
    const sub = try buf.sub(.{ .offset_items = 0, .count_items = buf.len() });
    try testing.expectEqual(buf.len(), sub.len());
    try testing.expectEqual(buf.dmaAddr().raw(), sub.dmaAddr().raw());
    try testing.expectEqual(buf.byteLen(), sub.byteLen());
}

test "unit: Buffer.sub narrows virt and dma together" {
    var backing: [8]u32 = undefined;
    const buf = try Buffer(u32).init(&backing, DMAAddr.fromInt(0x1000));
    const sub = try buf.sub(.{ .offset_items = 2, .count_items = 3 });
    try testing.expectEqual(@as(usize, 3), sub.len());
    try testing.expectEqual(@as(u64, 0x1000 + 8), sub.dmaAddr().raw());
    try testing.expectEqual(&backing[2], &sub.constSlice()[0]);
}

test "unit: Buffer.sub end cursor is a valid empty range" {
    var backing: [4]u32 = undefined;
    const buf = try Buffer(u32).init(&backing, DMAAddr.fromInt(0x1000));
    const end = try buf.sub(.{ .offset_items = buf.len(), .count_items = 0 });
    try testing.expect(end.isEmpty());
    try testing.expectEqual(@as(u64, 0x1000 + 16), end.dmaAddr().raw());
}

test "unit: Buffer.sub rejects windows that escape the buffer" {
    var backing: [4]u32 = undefined;
    const buf = try Buffer(u32).init(&backing, DMAAddr.fromInt(0x1000));
    try testing.expectError(error.OutOfBounds, buf.sub(.{ .offset_items = 2, .count_items = 3 }));
    try testing.expectError(error.OutOfBounds, buf.sub(.{ .offset_items = 5, .count_items = 0 }));
}

test "unit: Buffer.sub returns Overflow on offset_items + count_items wrap" {
    var backing: [4]u32 = undefined;
    const buf = try Buffer(u32).init(&backing, DMAAddr.fromInt(0x1000));
    try testing.expectError(error.Overflow, buf.sub(.{
        .offset_items = 1,
        .count_items = std.math.maxInt(usize),
    }));
}

test "unit: Buffer.assertValid accepts values returned by init" {
    var backing: [4]u32 = undefined;
    const buf = try Buffer(u32).init(&backing, DMAAddr.fromInt(0x1000));
    buf.assertValid();
}
