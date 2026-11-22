const std = @import("std");

const addr = @import("addr").address;
const debug = @import("core").debug;

const DmaAddr = addr.DmaAddr;

pub fn Buffer(comptime T: type) type {
    comptime Impl.requireRuntimeValue(T);

    return struct {
        memory: []T,
        address: DmaAddr,

        pub const Item = T;
        pub const Address = DmaAddr;

        pub const InitError = error{ Misaligned, Overflow };
        pub const OffsetError = error{OutOfBounds};
        pub const SubError = error{ Overflow, OutOfBounds };
        pub const Error = InitError || OffsetError || SubError;

        pub const SubArgs = struct {
            offset: usize,
            count: usize,
        };

        const Self = @This();

        pub fn init(memory: []T, address: Address) InitError!Self {
            return Impl.init(T, memory, address, @alignOf(T));
        }

        pub fn initAligned(memory: []T, address: Address, alignment: Address.Int) InitError!Self {
            if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) {
                return error.Misaligned;
            }

            return Impl.init(T, memory, address, alignment);
        }

        pub fn slice(self: Self) []const T {
            if (debug.checksEnabled()) {
                self.assertValid();
            }

            return self.memory;
        }

        pub fn sliceMut(self: Self) []T {
            if (debug.checksEnabled()) {
                self.assertValid();
            }

            return self.memory;
        }

        pub fn bytes(self: Self) []const u8 {
            if (debug.checksEnabled()) {
                self.assertValid();
            }

            return std.mem.sliceAsBytes(self.memory);
        }

        pub fn bytesMut(self: Self) []u8 {
            if (debug.checksEnabled()) {
                self.assertValid();
            }

            return std.mem.sliceAsBytes(self.memory);
        }

        pub fn len(self: Self) usize {
            if (debug.checksEnabled()) {
                self.assertValid();
            }

            return self.memory.len;
        }

        pub fn byteLen(self: Self) Address.Int {
            if (debug.checksEnabled()) {
                self.assertValid();
            }

            const count: Address.Int = @intCast(self.memory.len);
            return count * @sizeOf(T);
        }

        pub fn isEmpty(self: Self) bool {
            if (debug.checksEnabled()) {
                self.assertValid();
            }

            return self.memory.len == 0;
        }

        pub fn dmaAddr(self: Self) Address {
            if (debug.checksEnabled()) {
                self.assertValid();
            }

            return self.address;
        }

        pub fn dmaAddrAt(self: Self, offset_items: usize) OffsetError!Address {
            if (debug.checksEnabled()) {
                self.assertValid();
            }

            return Impl.dmaAddrAt(T, self.memory.len, self.address, offset_items);
        }

        pub fn sub(self: Self, args: SubArgs) SubError!Self {
            if (debug.checksEnabled()) {
                self.assertValid();
            }

            const end = try Impl.subEnd(self.memory.len, args.offset, args.count);

            return .{
                .memory = self.memory[args.offset..end],
                .address = Impl.offset(T, self.address, args.offset),
            };
        }

        pub fn assertValid(self: Self) void {
            std.debug.assert(self.address.isAligned(@alignOf(T)));

            const count: Address.Int = std.math.cast(Address.Int, self.memory.len) orelse unreachable;
            const byte_len = std.math.mul(Address.Int, count, @sizeOf(T)) catch unreachable;
            _ = std.math.add(Address.Int, self.address.raw(), byte_len) catch unreachable;
        }
    };
}

const Impl = struct {
    fn init(comptime T: type, memory: []T, address: DmaAddr, alignment: DmaAddr.Int) Buffer(T).InitError!Buffer(T) {
        std.debug.assert(alignment != 0);
        std.debug.assert(std.math.isPowerOfTwo(alignment));

        const required = @max(alignment, @as(DmaAddr.Int, @alignOf(T)));
        if (!address.isAligned(required)) {
            return error.Misaligned;
        }

        const len: DmaAddr.Int = std.math.cast(DmaAddr.Int, memory.len) orelse return error.Overflow;
        const bytes = std.math.mul(DmaAddr.Int, len, @sizeOf(T)) catch return error.Overflow;
        _ = std.math.add(DmaAddr.Int, address.raw(), bytes) catch return error.Overflow;

        return .{ .memory = memory, .address = address };
    }

    fn dmaAddrAt(comptime T: type, len: usize, address: DmaAddr, index: usize) Buffer(T).OffsetError!DmaAddr {
        if (index > len) {
            return error.OutOfBounds;
        }

        return offset(T, address, index);
    }

    fn offset(comptime T: type, address: DmaAddr, index: usize) DmaAddr {
        const raw: DmaAddr.Int = @intCast(index);
        return address.add(raw * @sizeOf(T)) catch unreachable;
    }

    fn subEnd(len: usize, start: usize, count: usize) error{ Overflow, OutOfBounds }!usize {
        const end = std.math.add(usize, start, count) catch return error.Overflow;

        if (end > len) {
            return error.OutOfBounds;
        }

        return end;
    }

    fn requireRuntimeValue(comptime T: type) void {
        if (@sizeOf(T) == 0) {
            @compileError("Buffer element type must have nonzero size");
        }
    }
};

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
        try testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, buf.slice());

        buf.sliceMut()[0] = 9;

        try testing.expectEqual(@as(u16, 9), backing[0]);
        try testing.expectEqual(buf.byteLen(), buf.bytes().len);
        try testing.expectEqual(buf.byteLen(), buf.bytesMut().len);
        try testing.expectEqual(@intFromPtr(&backing), @intFromPtr(buf.bytes().ptr));
        try testing.expectEqual(@intFromPtr(&backing), @intFromPtr(buf.bytesMut().ptr));

        buf.bytesMut()[0] = 0;
        try testing.expectEqual(@as(u8, 0), std.mem.sliceAsBytes(&backing)[0]);

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

        try testing.expectError(error.Misaligned, Impl.init(u8, &bytes, DmaAddr.from(0x1008), 16));
        _ = try Impl.init(u8, &bytes, DmaAddr.from(0x1000), 16);

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
        try testing.expectError(error.Overflow, Impl.init(u8, &backing, near_max, 1));
    }

    test "item addresses include the end cursor and reject larger offsets" {
        const address = DmaAddr.from(0x1000);

        for ([_]usize{ 0, 1, 2, 4 }) |offset| {
            try testing.expectEqual(@as(u64, 0x1000 + offset * @sizeOf(u32)), (try Impl.dmaAddrAt(u32, 4, address, offset)).raw());
        }

        try testing.expectError(error.OutOfBounds, Impl.dmaAddrAt(u32, 4, address, 5));
        try testing.expectError(error.OutOfBounds, Impl.dmaAddrAt(u32, 4, address, std.math.maxInt(usize)));
    }

    test "subranges preserve backing pointers and distinguish bounds from overflow" {
        var backing: [8]u32 = undefined;
        const buf = try Buffer(u32).init(&backing, DmaAddr.from(0x1000));
        const full = try buf.sub(.{ .offset = 0, .count = buf.len() });

        try testing.expectEqual(buf.len(), full.len());
        try testing.expectEqual(buf.dmaAddr().raw(), full.dmaAddr().raw());
        try testing.expectEqual(buf.byteLen(), full.byteLen());
        try testing.expectEqual(buf.slice().ptr, full.slice().ptr);

        const sub = try buf.sub(.{ .offset = 2, .count = 3 });

        try testing.expectEqual(@as(usize, 3), sub.len());
        try testing.expectEqual(@as(u64, 0x1008), sub.dmaAddr().raw());
        try testing.expectEqual(&backing[2], &sub.slice()[0]);

        const end = try buf.sub(.{ .offset = buf.len(), .count = 0 });

        try testing.expect(end.isEmpty());
        try testing.expectEqual(@as(u64, 0x1020), end.dmaAddr().raw());
        try testing.expectEqual(backing[backing.len..].ptr, end.slice().ptr);
        try testing.expectError(error.OutOfBounds, Impl.subEnd(buf.len(), 6, 3));
        try testing.expectError(error.OutOfBounds, Impl.subEnd(buf.len(), 9, 0));
        try testing.expectError(error.Overflow, Impl.subEnd(buf.len(), 1, std.math.maxInt(usize)));
    }
};
