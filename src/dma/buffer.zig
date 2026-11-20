//! DMA buffer primitive. See `docs/specs/dma/buffer.md`.

const std = @import("std");

const address = @import("addr").address;

const DmaAddr = address.DmaAddr;

fn requireRuntimeValue(comptime T: type) void {
    if (@sizeOf(T) == 0) @compileError("Buffer element type must have nonzero size");
}

pub fn Buffer(comptime T: type) type {
    comptime requireRuntimeValue(T);

    return struct {
        virt: []T,
        dma: DmaAddr,

        const Self = @This();

        pub const Item = T;
        pub const Address = DmaAddr;

        pub const InitError = error{ Misaligned, Overflow };
        pub const OffsetError = error{OutOfBounds};
        pub const SubError = error{ Overflow, OutOfBounds };
        pub const Error = InitError || OffsetError || SubError;

        /// A subrange names an item window for `sub`. Both fields are item counts, not bytes.
        pub const SubRange = struct {
            offset_items: usize,
            count_items: usize,
        };

        /// Validates `dma` against `@alignOf(T)` and the buffer address range.
        pub fn init(virt: []T, dma: Address) InitError!Self {
            return initAlignedWith(virt, dma, @alignOf(T));
        }

        /// Validates `dma` against `max(alignment, @alignOf(T))` and the buffer address range.
        /// A zero or non-power-of-two alignment returns `error.Misaligned`.
        pub fn initAligned(virt: []T, dma: Address, alignment: Address.Int) InitError!Self {
            if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) return error.Misaligned;
            return initAlignedWith(virt, dma, alignment);
        }

        fn initAlignedWith(virt: []T, dma: Address, alignment: Address.Int) InitError!Self {
            const type_alignment: Address.Int = @alignOf(T);
            const required = @max(alignment, type_alignment);
            if ((dma.raw() & (required - 1)) != 0) return error.Misaligned;

            const elem_size: Address.Int = @sizeOf(T);
            const virt_len: Address.Int = std.math.cast(Address.Int, virt.len) orelse return error.Overflow;
            const byte_len = std.math.mul(Address.Int, virt_len, elem_size) catch return error.Overflow;
            _ = std.math.add(Address.Int, dma.raw(), byte_len) catch return error.Overflow;

            return .{ .virt = virt, .dma = dma };
        }

        pub fn slice(self: Self) []T {
            self.assertValid();
            return self.virt;
        }

        pub fn constSlice(self: Self) []const T {
            self.assertValid();
            return self.virt;
        }

        pub fn bytes(self: Self) []u8 {
            self.assertValid();
            return std.mem.sliceAsBytes(self.virt);
        }

        pub fn constBytes(self: Self) []const u8 {
            self.assertValid();
            return std.mem.sliceAsBytes(self.virt);
        }

        pub fn len(self: Self) usize {
            self.assertValid();
            return self.virt.len;
        }

        /// Construction proves that the byte length does not overflow `Address.Int`.
        pub fn byteLen(self: Self) Address.Int {
            self.assertValid();
            const virt_len: Address.Int = @intCast(self.virt.len);
            return virt_len * @sizeOf(T);
        }

        pub fn isEmpty(self: Self) bool {
            self.assertValid();
            return self.virt.len == 0;
        }

        pub fn dmaAddr(self: Self) Address {
            self.assertValid();
            return self.dma;
        }

        /// `len()` is a valid one-past-the-end item offset.
        pub fn dmaAddrAt(self: Self, offset_items: usize) OffsetError!Address {
            self.assertValid();
            if (offset_items > self.virt.len) return error.OutOfBounds;
            const offset_raw: Address.Int = @intCast(offset_items);
            const byte_offset = offset_raw * @sizeOf(T);
            return self.dma.add(byte_offset) catch unreachable;
        }

        /// Returns a validated subrange that preserves the caller's contiguity claim.
        pub fn sub(self: Self, range: SubRange) SubError!Self {
            self.assertValid();
            const end = std.math.add(
                usize,
                range.offset_items,
                range.count_items,
            ) catch return error.Overflow;
            if (end > self.virt.len) return error.OutOfBounds;

            const offset_raw: Address.Int = @intCast(range.offset_items);
            const byte_offset = offset_raw * @sizeOf(T);
            return .{
                .virt = self.virt[range.offset_items..end],
                .dma = self.dma.add(byte_offset) catch unreachable,
            };
        }

        pub fn assertValid(self: Self) void {
            std.debug.assert((self.dma.raw() & (@as(Address.Int, @alignOf(T)) - 1)) == 0);
            const virt_len: Address.Int = std.math.cast(Address.Int, self.virt.len) orelse unreachable;
            const byte_len = std.math.mul(Address.Int, virt_len, @sizeOf(T)) catch unreachable;
            _ = std.math.add(Address.Int, self.dma.raw(), byte_len) catch unreachable;
        }
    };
}

pub const unit = struct {
    const testing = std.testing;

    const WireEntry = extern struct {
        a: u32,
        b: u32,
    };

    test "construction and accessors preserve backing storage" {
        var empty: [0]u8 = .{};
        const empty_buf = try Buffer(u8).init(&empty, DmaAddr.from(0xDEAD));
        try testing.expect(empty_buf.isEmpty());
        try testing.expectEqual(@as(usize, 0), empty_buf.len());
        try testing.expectEqual(@as(u64, 0), empty_buf.byteLen());
        try testing.expectEqual(@as(u64, 0xDEAD), empty_buf.dmaAddr().raw());

        var backing: [3]u16 = .{ 1, 2, 3 };
        const buf = try Buffer(u16).init(&backing, DmaAddr.from(0x1000));

        try testing.expect(!buf.isEmpty());
        try testing.expectEqual(@as(usize, 3), buf.len());
        try testing.expectEqual(@as(u64, 6), buf.byteLen());
        try testing.expectEqual(@as(u64, 0x1000), buf.dmaAddr().raw());
        try testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, buf.constSlice());

        buf.slice()[0] = 9;

        try testing.expectEqual(@as(u16, 9), backing[0]);
        try testing.expectEqual(buf.byteLen(), buf.bytes().len);
        try testing.expectEqual(buf.byteLen(), buf.constBytes().len);
        try testing.expectEqual(@intFromPtr(&backing), @intFromPtr(buf.bytes().ptr));
        try testing.expectEqual(@intFromPtr(&backing), @intFromPtr(buf.constBytes().ptr));

        var entries: [2]WireEntry = undefined;
        const wire = try Buffer(WireEntry).init(&entries, DmaAddr.from(0x2000));

        try testing.expectEqual(@as(usize, 2), wire.len());
        try testing.expectEqual(@as(u64, 2 * @sizeOf(WireEntry)), wire.byteLen());
        try testing.expectError(error.Misaligned, Buffer(WireEntry).init(&entries, DmaAddr.from(0x2001)));
    }

    test "alignment validates runtime and element requirements" {
        var bytes: [8]u8 = undefined;
        for ([_]u64{ 0, 3, 6 }) |alignment| {
            try testing.expectError(error.Misaligned, Buffer(u8).initAligned(&bytes, DmaAddr.from(0x1000), alignment));
        }

        try testing.expectError(error.Misaligned, Buffer(u8).initAligned(&bytes, DmaAddr.from(0x1008), 16));
        _ = try Buffer(u8).initAligned(&bytes, DmaAddr.from(0x1000), 16);

        var backing: [4]u32 = undefined;

        for ([_]u64{ 0x1001, 0x1002 }) |base| {
            try testing.expectError(error.Misaligned, Buffer(u32).init(&backing, DmaAddr.from(base)));
            try testing.expectError(error.Misaligned, Buffer(u32).initAligned(&backing, DmaAddr.from(base), 1));
        }

        const ordinary = try Buffer(u32).init(&backing, DmaAddr.from(0x1000));

        for ([_]u64{ 1, @alignOf(u32) }) |alignment| {
            const aligned = try Buffer(u32).initAligned(&backing, DmaAddr.from(0x1000), alignment);
            try testing.expectEqual(ordinary.len(), aligned.len());
            try testing.expectEqual(ordinary.dmaAddr().raw(), aligned.dmaAddr().raw());
        }
    }

    test "construction rejects address overflow" {
        var backing: [4]u8 = undefined;
        const near_max = DmaAddr.from(std.math.maxInt(u64) - 2);
        try testing.expectError(error.Overflow, Buffer(u8).init(&backing, near_max));
    }

    test "item addresses include the end cursor and reject larger offsets" {
        var backing: [4]u32 = undefined;
        const buf = try Buffer(u32).init(&backing, DmaAddr.from(0x1000));

        for ([_]usize{ 0, 1, 2, 4 }) |offset| {
            try testing.expectEqual(@as(u64, 0x1000 + offset * @sizeOf(u32)), (try buf.dmaAddrAt(offset)).raw());
        }

        try testing.expectError(error.OutOfBounds, buf.dmaAddrAt(5));
        try testing.expectError(error.OutOfBounds, buf.dmaAddrAt(std.math.maxInt(usize)));
    }

    test "subranges preserve backing pointers and distinguish bounds from overflow" {
        var backing: [8]u32 = undefined;
        const buf = try Buffer(u32).init(&backing, DmaAddr.from(0x1000));
        const full = try buf.sub(.{ .offset_items = 0, .count_items = buf.len() });

        try testing.expectEqual(buf.len(), full.len());
        try testing.expectEqual(buf.dmaAddr().raw(), full.dmaAddr().raw());
        try testing.expectEqual(buf.byteLen(), full.byteLen());
        try testing.expectEqual(buf.constSlice().ptr, full.constSlice().ptr);

        const sub = try buf.sub(.{ .offset_items = 2, .count_items = 3 });

        try testing.expectEqual(@as(usize, 3), sub.len());
        try testing.expectEqual(@as(u64, 0x1008), sub.dmaAddr().raw());
        try testing.expectEqual(&backing[2], &sub.constSlice()[0]);

        const end = try buf.sub(.{ .offset_items = buf.len(), .count_items = 0 });

        try testing.expect(end.isEmpty());
        try testing.expectEqual(@as(u64, 0x1020), end.dmaAddr().raw());
        try testing.expectEqual(backing[backing.len..].ptr, end.constSlice().ptr);
        try testing.expectError(error.OutOfBounds, buf.sub(.{ .offset_items = 6, .count_items = 3 }));
        try testing.expectError(error.OutOfBounds, buf.sub(.{ .offset_items = 9, .count_items = 0 }));
        try testing.expectError(error.Overflow, buf.sub(.{
            .offset_items = 1,
            .count_items = std.math.maxInt(usize),
        }));
    }
};
