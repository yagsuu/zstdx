const std = @import("std");

const address = @import("addr").address;

const buffer = @import("buffer.zig");

const DmaAddr = address.DmaAddr;
const DmaInt = DmaAddr.Int;

/// A segment describes an untyped device-visible byte range.
pub const Segment = struct {
    addr: DmaAddr,
    len_bytes: DmaInt,

    pub const Address = DmaAddr;

    /// `Overflow`: `addr.raw() + len_bytes` exceeds `Address.Int`.
    pub const Error = error{Overflow};

    /// Validates that `[addr, addr + len_bytes)` does not overflow.
    pub fn init(addr: DmaAddr, len_bytes: DmaInt) Error!Segment {
        _ = std.math.add(DmaInt, addr.raw(), len_bytes) catch return error.Overflow;
        return .{ .addr = addr, .len_bytes = len_bytes };
    }

    pub fn fromBuffer(comptime T: type, buf: buffer.Buffer(T)) Segment {
        return .{ .addr = buf.dmaAddr(), .len_bytes = buf.byteLen() };
    }

    pub fn byteLen(self: Segment) DmaInt {
        return self.len_bytes;
    }

    pub fn isEmpty(self: Segment) bool {
        return self.len_bytes == 0;
    }

    /// The returned address is one byte past the segment.
    pub fn endAddr(self: Segment) Error!DmaAddr {
        const raw = std.math.add(DmaInt, self.addr.raw(), self.len_bytes) catch return error.Overflow;
        return DmaAddr.from(raw);
    }

    /// Returns `false` for zero or non-power-of-two alignment.
    pub fn isAligned(self: Segment, alignment: DmaInt) bool {
        if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) return false;
        const mask = alignment - 1;
        if ((self.addr.raw() & mask) != 0) return false;
        return (self.len_bytes & mask) == 0;
    }

    pub fn assertValid(self: Segment) void {
        _ = std.math.add(DmaInt, self.addr.raw(), self.len_bytes) catch unreachable;
    }
};

/// `Static` owns segment-list storage. `Bounded` borrows storage.
pub const List = struct {
    pub fn Static(comptime capacity_segments: usize) type {
        comptime if (capacity_segments == 0) @compileError("dma.List.Static capacity_segments must be non-zero");
        return struct {
            buffer: [capacity_segments]Segment = undefined,
            count: usize = 0,

            const Self = @This();

            /// `Full`: The list is at capacity.
            /// `OutOfBounds`: The index is at or past `count`.
            pub const Error = error{ Full, OutOfBounds };

            pub const segment_capacity = capacity_segments;

            pub fn init() Self {
                return .{};
            }

            pub fn len(self: *const Self) usize {
                self.assertValid();
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return segment_capacity;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.len() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.len() == segment_capacity;
            }

            pub fn asSlice(self: *Self) []Segment {
                self.assertValid();
                return self.buffer[0..self.count];
            }

            pub fn asConstSlice(self: *const Self) []const Segment {
                self.assertValid();
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            pub fn append(self: *Self, segment: Segment) error{Full}!void {
                if (self.isFull()) return error.Full;
                self.appendAssumeCapacity(segment);
            }

            pub fn appendAssumeCapacity(self: *Self, segment: Segment) void {
                std.debug.assert(!self.isFull());
                if (segment_capacity == 0) unreachable;

                self.buffer[self.count] = segment;
                self.count += 1;
            }

            pub fn appendBuffer(self: *Self, comptime T: type, buf: buffer.Buffer(T)) error{Full}!void {
                return self.append(Segment.fromBuffer(T, buf));
            }

            pub fn at(self: *Self, index: usize) error{OutOfBounds}!*Segment {
                if (index >= self.count) return error.OutOfBounds;
                return &self.buffer[index];
            }

            pub fn constAt(self: *const Self, index: usize) error{OutOfBounds}!*const Segment {
                if (index >= self.count) return error.OutOfBounds;
                return &self.buffer[index];
            }

            /// `error.Overflow` is returned if the sum exceeds `Address.Int`.
            pub fn totalByteLen(self: *const Self) error{Overflow}!DmaInt {
                return sumSegmentLens(self.asConstSlice());
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.count <= segment_capacity);
                for (self.buffer[0..self.count]) |segment| segment.assertValid();
            }
        };
    }

    /// Bounded lists borrow storage. Their capacity is `buffer.len`.
    pub const Bounded = struct {
        buffer: []Segment,
        count: usize = 0,

        /// `Full`: The list is at capacity.
        /// `OutOfBounds`: The index is at or past `count`.
        pub const Error = error{ Full, OutOfBounds };

        pub fn wrap(buf: []Segment) Bounded {
            return .{ .buffer = buf };
        }

        pub fn len(self: *const Bounded) usize {
            self.assertValid();
            return self.count;
        }

        pub fn capacity(self: *const Bounded) usize {
            self.assertValid();
            return self.buffer.len;
        }

        pub fn remaining(self: *const Bounded) usize {
            return self.capacity() - self.len();
        }

        pub fn isEmpty(self: *const Bounded) bool {
            return self.len() == 0;
        }

        pub fn isFull(self: *const Bounded) bool {
            return self.len() == self.capacity();
        }

        pub fn asSlice(self: *Bounded) []Segment {
            self.assertValid();
            return self.buffer[0..self.count];
        }

        pub fn asConstSlice(self: *const Bounded) []const Segment {
            self.assertValid();
            return self.buffer[0..self.count];
        }

        pub fn clearRetainingCapacity(self: *Bounded) void {
            self.count = 0;
        }

        pub fn append(self: *Bounded, segment: Segment) error{Full}!void {
            if (self.isFull()) return error.Full;
            self.appendAssumeCapacity(segment);
        }

        pub fn appendAssumeCapacity(self: *Bounded, segment: Segment) void {
            std.debug.assert(!self.isFull());
            if (self.buffer.len == 0) unreachable;

            self.buffer[self.count] = segment;
            self.count += 1;
        }

        pub fn appendBuffer(self: *Bounded, comptime T: type, buf: buffer.Buffer(T)) error{Full}!void {
            return self.append(Segment.fromBuffer(T, buf));
        }

        pub fn at(self: *Bounded, index: usize) error{OutOfBounds}!*Segment {
            if (index >= self.count) return error.OutOfBounds;
            return &self.buffer[index];
        }

        pub fn constAt(self: *const Bounded, index: usize) error{OutOfBounds}!*const Segment {
            if (index >= self.count) return error.OutOfBounds;
            return &self.buffer[index];
        }

        pub fn totalByteLen(self: *const Bounded) error{Overflow}!DmaInt {
            return sumSegmentLens(self.asConstSlice());
        }

        pub fn assertValid(self: *const Bounded) void {
            std.debug.assert(self.count <= self.buffer.len);
            for (self.buffer[0..self.count]) |segment| segment.assertValid();
        }
    };
};

fn requireAlignment(comptime alignment: DmaInt) void {
    if (alignment == 0) @compileError("Builder alignment must be non-zero");
    if (!std.math.isPowerOfTwo(alignment)) @compileError("Builder alignment must be a power of two");
}

/// Builders require a uniform alignment for each appended segment.
pub const Builder = struct {
    /// Static builders own inline segment storage.
    pub fn Static(comptime capacity_segments: usize, comptime alignment: DmaInt) type {
        comptime if (capacity_segments == 0) @compileError("dma.Builder.Static capacity_segments must be non-zero");
        comptime requireAlignment(alignment);
        return struct {
            list: List.Static(capacity_segments) = .{},

            const Self = @This();
            const InnerList = List.Static(capacity_segments);

            /// `Full`: The underlying list is at capacity.
            /// `Misaligned`: The segment fails `isAligned(alignment)`.
            pub const Error = error{ Full, Misaligned };

            pub const segment_alignment = alignment;

            pub fn init() Self {
                return .{};
            }

            pub fn len(self: *const Self) usize {
                return self.list.len();
            }

            pub fn capacity(self: *const Self) usize {
                return self.list.capacity();
            }

            pub fn remaining(self: *const Self) usize {
                return self.list.remaining();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.list.isEmpty();
            }

            pub fn isFull(self: *const Self) bool {
                return self.list.isFull();
            }

            pub fn asSlice(self: *Self) []Segment {
                return self.list.asSlice();
            }

            pub fn asConstSlice(self: *const Self) []const Segment {
                return self.list.asConstSlice();
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.list.clearRetainingCapacity();
            }

            /// Misalignment is reported before capacity. Errors leave the list unchanged.
            pub fn append(self: *Self, segment: Segment) Error!void {
                if (alignment != 1 and !segment.isAligned(alignment)) return error.Misaligned;
                self.list.append(segment) catch |err| switch (err) {
                    error.Full => return error.Full,
                };
            }

            pub fn appendBuffer(self: *Self, comptime T: type, buf: buffer.Buffer(T)) Error!void {
                return self.append(Segment.fromBuffer(T, buf));
            }

            /// Returns a const list view. Mutating or moving the builder invalidates the view.
            pub fn finish(self: *Self) *const InnerList {
                return &self.list;
            }

            pub fn assertValid(self: *const Self) void {
                self.list.assertValid();
                for (self.list.asConstSlice()) |segment| {
                    std.debug.assert(segment.isAligned(alignment));
                }
            }
        };
    }

    /// Bounded builders borrow segment storage.
    pub fn Bounded(comptime alignment: DmaInt) type {
        comptime requireAlignment(alignment);
        return struct {
            list: List.Bounded,

            const Self = @This();

            /// `Full`: The underlying list is at capacity.
            /// `Misaligned`: The segment fails `isAligned(alignment)`.
            pub const Error = error{ Full, Misaligned };

            pub const segment_alignment = alignment;

            pub fn wrap(buf: []Segment) Self {
                return .{ .list = List.Bounded.wrap(buf) };
            }

            pub fn len(self: *const Self) usize {
                return self.list.len();
            }

            pub fn capacity(self: *const Self) usize {
                return self.list.capacity();
            }

            pub fn remaining(self: *const Self) usize {
                return self.list.remaining();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.list.isEmpty();
            }

            pub fn isFull(self: *const Self) bool {
                return self.list.isFull();
            }

            pub fn asSlice(self: *Self) []Segment {
                return self.list.asSlice();
            }

            pub fn asConstSlice(self: *const Self) []const Segment {
                return self.list.asConstSlice();
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.list.clearRetainingCapacity();
            }

            /// Misalignment is reported before capacity. Errors leave the list unchanged.
            pub fn append(self: *Self, segment: Segment) Error!void {
                if (alignment != 1 and !segment.isAligned(alignment)) return error.Misaligned;
                self.list.append(segment) catch |err| switch (err) {
                    error.Full => return error.Full,
                };
            }

            pub fn appendBuffer(self: *Self, comptime T: type, buf: buffer.Buffer(T)) Error!void {
                return self.append(Segment.fromBuffer(T, buf));
            }

            /// Returns a const list view. Mutating or moving the builder invalidates the view.
            pub fn finish(self: *Self) *const List.Bounded {
                return &self.list;
            }

            pub fn assertValid(self: *const Self) void {
                self.list.assertValid();
                for (self.list.asConstSlice()) |segment| {
                    std.debug.assert(segment.isAligned(alignment));
                }
            }
        };
    }
};

fn sumSegmentLens(segments: []const Segment) error{Overflow}!DmaInt {
    var total: DmaInt = 0;
    for (segments) |segment| {
        total = std.math.add(DmaInt, total, segment.len_bytes) catch return error.Overflow;
    }
    return total;
}

pub const unit = struct {
    const Buffer = buffer.Buffer;

    const AlignmentCase = struct {
        base: u64,
        len_bytes: u64,
        alignment: u64,
        expected: bool,
    };

    const testing = std.testing;

    fn seg(base: u64, len_bytes: DmaAddr.Int) Segment {
        return .{ .addr = DmaAddr.from(base), .len_bytes = len_bytes };
    }

    // Compare construction and accessors for empty and non-empty byte ranges.
    test "segment construction and accessors" {
        for ([_]u64{ 0, 1, 42, 128, 256 }) |len_bytes| {
            const segment = try Segment.init(DmaAddr.from(0x1000), len_bytes);
            try testing.expectEqual(len_bytes == 0, segment.isEmpty());
            try testing.expectEqual(len_bytes, segment.byteLen());
            try testing.expectEqual(@as(u64, 0x1000) + len_bytes, (try segment.endAddr()).raw());
        }
        const empty = try Segment.init(DmaAddr.from(0xDEAD), 0);
        try testing.expect(empty.isEmpty());
        try testing.expectEqual(@as(u64, 0xDEAD), (try empty.endAddr()).raw());
    }

    test "Segment.init returns Overflow when addr + len_bytes exceeds Address.Int" {
        const near_max = DmaAddr.from(std.math.maxInt(u64) - 10);
        try testing.expectError(error.Overflow, Segment.init(near_max, 20));
        {
            const bad = seg(std.math.maxInt(u64) - 1, 10);
            try testing.expectError(error.Overflow, bad.endAddr());
        }
    }

    test "Segment.fromBuffer matches buffer.dmaAddr and buffer.byteLen" {
        var backing: [4]u32 = undefined;
        const buf = try Buffer(u32).init(&backing, DmaAddr.from(0x1000));
        const s = Segment.fromBuffer(u32, buf);
        try testing.expectEqual(buf.dmaAddr().raw(), s.addr.raw());
        try testing.expectEqual(buf.byteLen(), s.byteLen());
    }

    // Compare address and length alignment across valid and invalid requirements.
    test "segment alignment validates address and byte length" {
        const cases = [_]AlignmentCase{
            .{ .base = 0, .len_bytes = 0, .alignment = 1, .expected = true },
            .{ .base = 1, .len_bytes = 3, .alignment = 1, .expected = true },
            .{ .base = 0xABCDEF, .len_bytes = 0xFEDCBA, .alignment = 1, .expected = true },
            .{ .base = 0, .len_bytes = 0, .alignment = 0, .expected = false },
            .{ .base = 0x1000, .len_bytes = 4096, .alignment = 0, .expected = false },
            .{ .base = 0x1000, .len_bytes = 4096, .alignment = 3, .expected = false },
            .{ .base = 0x1000, .len_bytes = 4096, .alignment = 4096, .expected = true },
            .{ .base = 0x1001, .len_bytes = 4096, .alignment = 4096, .expected = false },
            .{ .base = 0x1000, .len_bytes = 4097, .alignment = 4096, .expected = false },
            .{ .base = 0x1000, .len_bytes = 512, .alignment = 512, .expected = true },
        };

        for (cases) |case| {
            try testing.expectEqual(case.expected, seg(case.base, case.len_bytes).isAligned(case.alignment));
        }
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

    test "List.Static exercises append/at/totalByteLen/clear" {
        var list = List.Static(3).init();
        try exerciseList(@TypeOf(list), &list);
    }

    test "List.Bounded exercises the same sequence over borrowed storage" {
        var storage: [3]Segment = undefined;
        var list = List.Bounded.wrap(&storage);
        try exerciseList(@TypeOf(list), &list);
    }

    test "List.Bounded with a zero-length backing slice is empty and full" {
        var storage: [0]Segment = .{};
        var list = List.Bounded.wrap(&storage);
        try testing.expect(list.isEmpty());
        try testing.expect(list.isFull());
        try testing.expectError(error.Full, list.append(seg(0, 0)));
    }

    test "List.Static.appendBuffer combines fromBuffer and append" {
        var backing: [4]u32 = undefined;
        const buf = try Buffer(u32).init(&backing, DmaAddr.from(0x1000));
        var list = List.Static(2).init();
        try list.appendBuffer(u32, buf);
        try testing.expectEqual(@as(usize, 1), list.len());
        try testing.expectEqual(@as(u64, 16), (try list.constAt(0)).byteLen());
        try testing.expectEqual(@as(u64, 0x1000), (try list.constAt(0)).addr.raw());
    }

    test "List.totalByteLen returns Overflow on sum wraparound" {
        var storage: [2]Segment = undefined;
        var list = List.Bounded.wrap(&storage);
        try list.append(seg(0, std.math.maxInt(u64) - 3));
        try list.append(seg(0x1000, 8));
        try testing.expectError(error.Overflow, list.totalByteLen());
    }

    test "Builder.Static(alignment=1) accepts every segment" {
        var b = Builder.Static(4, 1).init();
        try b.append(seg(0x1001, 3));
        try b.append(seg(0xABCDEF, 7));
        try testing.expectEqual(@as(usize, 2), b.len());
    }

    // Inspect finished contents, clear the builder, and reuse its retained capacity.
    test "aligned builder lifecycle preserves contents and capacity" {
        var builder = Builder.Static(4, 512).init();
        try testing.expect(builder.isEmpty());
        try builder.append(seg(0x1000, 512));
        try builder.append(seg(0x1200, 1024));
        const list = builder.finish();
        try testing.expectEqual(@as(usize, 2), list.len());
        try testing.expectEqual(@as(u64, 0x1200), (try list.constAt(1)).addr.raw());
        try testing.expectEqual(@as(u64, 1536), try list.totalByteLen());
        builder.clearRetainingCapacity();
        try testing.expect(builder.isEmpty());
        try testing.expectEqual(@as(usize, 4), builder.capacity());
        try builder.append(seg(0x1800, 512));
        try testing.expectEqual(@as(usize, 1), builder.len());
        try testing.expectEqual(@as(u64, 0x1800), (try builder.finish().constAt(0)).addr.raw());
    }

    test "Builder.Static returns Misaligned before Full" {
        var b = Builder.Static(1, 4096).init();
        try b.append(seg(0x1000, 4096));
        try testing.expect(b.isFull());
        try testing.expectError(error.Misaligned, b.append(seg(0x1001, 4096)));
        try testing.expectError(error.Full, b.append(seg(0x2000, 4096)));
        try testing.expectEqual(@as(usize, 1), b.len());
    }

    test "Builder.Static.append leaves the list unchanged on Misaligned" {
        var b = Builder.Static(4, 4096).init();
        try b.append(seg(0x1000, 4096));
        try testing.expectError(error.Misaligned, b.append(seg(0x1001, 4096)));
        try testing.expectError(error.Misaligned, b.append(seg(0x2000, 4097)));
        try testing.expectEqual(@as(usize, 1), b.len());
    }

    test "Builder.Static.appendBuffer inherits Misaligned and Full" {
        var page_backing: [4096]u8 align(4096) = undefined;
        const buf = try Buffer(u8).initAligned(&page_backing, DmaAddr.from(0x1000), 4096);
        var b = Builder.Static(1, 4096).init();
        try b.appendBuffer(u8, buf);
        try testing.expectError(error.Full, b.appendBuffer(u8, buf));

        var small_backing: [8]u8 = undefined;
        const small = try Buffer(u8).init(&small_backing, DmaAddr.from(0x2000));
        var b2 = Builder.Static(1, 4096).init();
        try testing.expectError(error.Misaligned, b2.appendBuffer(u8, small));
    }

    test "Builder.Bounded shares the same behavior over borrowed storage" {
        var storage: [4]Segment = undefined;
        var b = Builder.Bounded(4096).wrap(&storage);
        try b.append(seg(0x1000, 4096));
        try testing.expectError(error.Misaligned, b.append(seg(0x1001, 4096)));
        try b.append(seg(0x2000, 8192));
        try testing.expectEqual(@as(usize, 2), b.len());

        const list = b.finish();
        try testing.expectEqual(@as(u64, 0x2000), (try list.constAt(1)).addr.raw());
    }
};
