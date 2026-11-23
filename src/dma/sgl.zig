//! DMA scatter-gather entries, lists, and aligned builders.

const std = @import("std");

const address = @import("addr").address;
const debug = @import("core").debug;
const layout = @import("layout");
const ranges = @import("ranges");

const buffer = @import("buffer.zig");

const DmaAddr = address.DmaAddr;
const DmaRange = ranges.InclusiveRange(DmaAddr.Int);

/// Describes an untyped device-visible byte range.
pub const Entry = struct {
    addr: DmaAddr,
    len: DmaAddr.Int,

    pub const Address = DmaAddr;

    pub const Error = error{Overflow};

    pub fn init(addr: DmaAddr, len: DmaAddr.Int) Error!Entry {
        const self: Entry = .{ .addr = addr, .len = len };
        _ = try self.range();

        return self;
    }

    pub fn fromBuffer(comptime T: type, buf: buffer.Buffer(T)) Entry {
        if (debug.checksEnabled()) {
            buf.assertValid();
        }

        return .{ .addr = buf.dmaAddr(), .len = buf.byteLen() };
    }

    pub fn isEmpty(self: Entry) bool {
        return self.len == 0;
    }

    pub fn isAligned(self: Entry, alignment: DmaAddr.Int) bool {
        if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) {
            return false;
        }

        return self.addr.isAligned(alignment) and layout.isAligned(DmaAddr.Int, self.len, alignment);
    }

    pub fn range(self: Entry) Error!?DmaRange {
        if (self.isEmpty()) {
            return null;
        }

        return DmaRange.fromStartLen(self.addr.raw(), self.len) catch |err| switch (err) {
            error.InvalidRange => unreachable,
            error.Overflow => error.Overflow,
        };
    }

    pub fn assertValid(self: Entry) void {
        _ = self.range() catch {
            std.debug.assert(false);
            return;
        };
    }
};

pub const List = struct {
    pub fn Static(comptime capacity_entries: usize) type {
        comptime Impl.requireCapacity(capacity_entries);

        return struct {
            buffer: [capacity_entries]Entry = undefined,
            count: usize = 0,

            pub const Error = error{ Full, OutOfBounds };

            const Self = @This();

            pub fn init() Self {
                return .{};
            }

            pub fn len(self: *const Self) usize {
                std.debug.assert(self.count <= self.buffer.len);
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return capacity_entries;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.len() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.len() == capacity_entries;
            }

            pub fn sliceMut(self: *Self) []Entry {
                std.debug.assert(self.count <= self.buffer.len);
                return self.buffer[0..self.count];
            }

            pub fn slice(self: *const Self) []const Entry {
                std.debug.assert(self.count <= self.buffer.len);
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                std.debug.assert(self.count <= self.buffer.len);
                self.count = 0;
            }

            pub fn append(self: *Self, entry: Entry) error{Full}!void {
                return Impl.append(&self.buffer, &self.count, entry);
            }

            pub fn appendAssumeCapacity(self: *Self, entry: Entry) void {
                Impl.appendAssumeCapacity(&self.buffer, &self.count, entry);
            }

            pub fn appendBuffer(self: *Self, comptime T: type, buf: buffer.Buffer(T)) error{Full}!void {
                return self.append(Entry.fromBuffer(T, buf));
            }

            pub fn atMut(self: *Self, index: usize) error{OutOfBounds}!*Entry {
                std.debug.assert(self.count <= self.buffer.len);
                if (index >= self.count) {
                    return error.OutOfBounds;
                }

                return &self.buffer[index];
            }

            pub fn at(self: *const Self, index: usize) error{OutOfBounds}!*const Entry {
                std.debug.assert(self.count <= self.buffer.len);
                if (index >= self.count) {
                    return error.OutOfBounds;
                }

                return &self.buffer[index];
            }

            pub fn totalByteLen(self: *const Self) error{Overflow}!DmaAddr.Int {
                return Impl.totalByteLen(self.slice());
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertValid(&self.buffer, self.count);
            }
        };
    }

    pub const Bounded = struct {
        buffer: []Entry,
        count: usize = 0,

        pub const Error = error{ Full, OutOfBounds };

        pub fn wrap(buf: []Entry) Bounded {
            return .{ .buffer = buf };
        }

        pub fn len(self: *const Bounded) usize {
            std.debug.assert(self.count <= self.buffer.len);
            return self.count;
        }

        pub fn capacity(self: *const Bounded) usize {
            std.debug.assert(self.count <= self.buffer.len);
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

        pub fn sliceMut(self: *Bounded) []Entry {
            std.debug.assert(self.count <= self.buffer.len);
            return self.buffer[0..self.count];
        }

        pub fn slice(self: *const Bounded) []const Entry {
            std.debug.assert(self.count <= self.buffer.len);
            return self.buffer[0..self.count];
        }

        pub fn clearRetainingCapacity(self: *Bounded) void {
            std.debug.assert(self.count <= self.buffer.len);

            self.count = 0;
        }

        pub fn append(self: *Bounded, entry: Entry) error{Full}!void {
            return Impl.append(self.buffer, &self.count, entry);
        }

        pub fn appendAssumeCapacity(self: *Bounded, entry: Entry) void {
            Impl.appendAssumeCapacity(self.buffer, &self.count, entry);
        }

        pub fn appendBuffer(self: *Bounded, comptime T: type, buf: buffer.Buffer(T)) error{Full}!void {
            return self.append(Entry.fromBuffer(T, buf));
        }

        pub fn atMut(self: *Bounded, index: usize) error{OutOfBounds}!*Entry {
            std.debug.assert(self.count <= self.buffer.len);
            if (index >= self.count) {
                return error.OutOfBounds;
            }

            return &self.buffer[index];
        }

        pub fn at(self: *const Bounded, index: usize) error{OutOfBounds}!*const Entry {
            std.debug.assert(self.count <= self.buffer.len);
            if (index >= self.count) {
                return error.OutOfBounds;
            }

            return &self.buffer[index];
        }

        pub fn totalByteLen(self: *const Bounded) error{Overflow}!DmaAddr.Int {
            return Impl.totalByteLen(self.slice());
        }

        pub fn assertValid(self: *const Bounded) void {
            Impl.assertValid(self.buffer, self.count);
        }
    };
};

pub const Builder = struct {
    pub fn Static(comptime capacity_entries: usize, comptime alignment_value: DmaAddr.Int) type {
        comptime Impl.requireCapacity(capacity_entries);
        comptime Impl.requireAlignment(alignment_value);

        return struct {
            list: List.Static(capacity_entries) = .{},

            pub const Error = error{ Full, Misaligned };

            pub const alignment = alignment_value;

            const Self = @This();
            const InnerList = List.Static(capacity_entries);

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

            pub fn sliceMut(self: *Self) []Entry {
                return self.list.sliceMut();
            }

            pub fn slice(self: *const Self) []const Entry {
                return self.list.slice();
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.list.clearRetainingCapacity();
            }

            pub fn append(self: *Self, entry: Entry) Error!void {
                return Impl.appendAligned(alignment, &self.list.buffer, &self.list.count, entry);
            }

            pub fn appendBuffer(self: *Self, comptime T: type, buf: buffer.Buffer(T)) Error!void {
                return self.append(Entry.fromBuffer(T, buf));
            }

            pub fn finish(self: *const Self) *const InnerList {
                if (debug.checksEnabled()) {
                    self.assertValid();
                }

                return &self.list;
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertAligned(alignment, &self.list.buffer, self.list.count);
            }
        };
    }

    pub fn Bounded(comptime alignment_value: DmaAddr.Int) type {
        comptime Impl.requireAlignment(alignment_value);

        return struct {
            list: List.Bounded,

            pub const Error = error{ Full, Misaligned };

            pub const alignment = alignment_value;

            const Self = @This();

            pub fn wrap(buf: []Entry) Self {
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

            pub fn sliceMut(self: *Self) []Entry {
                return self.list.sliceMut();
            }

            pub fn slice(self: *const Self) []const Entry {
                return self.list.slice();
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.list.clearRetainingCapacity();
            }

            pub fn append(self: *Self, entry: Entry) Error!void {
                return Impl.appendAligned(alignment, self.list.buffer, &self.list.count, entry);
            }

            pub fn appendBuffer(self: *Self, comptime T: type, buf: buffer.Buffer(T)) Error!void {
                return self.append(Entry.fromBuffer(T, buf));
            }

            pub fn finish(self: *const Self) *const List.Bounded {
                if (debug.checksEnabled()) {
                    self.assertValid();
                }

                return &self.list;
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertAligned(alignment, self.list.buffer, self.list.count);
            }
        };
    }
};

const Impl = struct {
    fn append(entries: []Entry, count: *usize, entry: Entry) error{Full}!void {
        std.debug.assert(count.* <= entries.len);
        if (debug.checksEnabled()) {
            assertValid(entries, count.*);
        }

        if (count.* == entries.len) {
            return error.Full;
        }

        appendAssumeCapacity(entries, count, entry);
    }

    fn appendAssumeCapacity(entries: []Entry, count: *usize, entry: Entry) void {
        std.debug.assert(count.* < entries.len);
        if (debug.checksEnabled()) {
            entry.assertValid();
        }

        entries[count.*] = entry;
        count.* += 1;

        std.debug.assert(count.* <= entries.len);
    }

    fn totalByteLen(entries: []const Entry) error{Overflow}!DmaAddr.Int {
        var total: DmaAddr.Int = 0;

        for (entries) |entry| {
            total = std.math.add(DmaAddr.Int, total, entry.len) catch return error.Overflow;
        }

        return total;
    }

    fn assertValid(entries: []const Entry, count: usize) void {
        std.debug.assert(count <= entries.len);
        for (entries[0..count]) |entry| {
            entry.assertValid();
        }
    }

    fn appendAligned(comptime alignment: DmaAddr.Int, entries: []Entry, count: *usize, entry: Entry) error{ Full, Misaligned }!void {
        std.debug.assert(count.* <= entries.len);
        if (debug.checksEnabled()) {
            assertAligned(alignment, entries, count.*);
        }

        if (!entry.isAligned(alignment)) {
            return error.Misaligned;
        }

        return append(entries, count, entry);
    }

    fn assertAligned(comptime alignment: DmaAddr.Int, entries: []const Entry, count: usize) void {
        assertValid(entries, count);
        for (entries[0..count]) |entry| {
            std.debug.assert(entry.isAligned(alignment));
        }
    }

    fn requireCapacity(comptime capacity: usize) void {
        if (capacity == 0) {
            @compileError("DMA static capacity must be non-zero");
        }
    }

    fn requireAlignment(comptime alignment: DmaAddr.Int) void {
        if (alignment == 0) {
            @compileError("Builder alignment must be non-zero");
        }
        if (!std.math.isPowerOfTwo(alignment)) {
            @compileError("Builder alignment must be a power of two");
        }
    }
};

pub const unit = struct {
    const Buffer = buffer.Buffer;

    const AlignmentCase = struct {
        base: u64,
        len: u64,
        alignment: u64,
        expected: bool,
    };

    const testing = std.testing;

    fn entry(base: u64, len: DmaAddr.Int) Entry {
        return .{ .addr = DmaAddr.from(base), .len = len };
    }

    test "entry construction and accessors" {
        for ([_]u64{ 0, 1, 42, 128, 256 }) |len| {
            const range = try Entry.init(DmaAddr.from(0x1000), len);

            try testing.expectEqual(len == 0, range.isEmpty());
            try testing.expectEqual(len, range.len);

            const bounds = try range.range();

            if (len == 0) {
                try testing.expect(bounds == null);
            } else {
                try testing.expectEqual(range.addr.raw(), bounds.?.start);
                try testing.expectEqual(range.len - 1, bounds.?.end - bounds.?.start);
                try testing.expectEqual(@as(DmaAddr.Int, 0x1000) + len - 1, bounds.?.end);
            }
        }

        const empty = try Entry.init(DmaAddr.from(0xDEAD), 0);

        try testing.expect(empty.isEmpty());
        try testing.expect((try empty.range()) == null);
    }

    test "entry inclusive ranges accept the final address and reject overflow" {
        const near_max = DmaAddr.from(std.math.maxInt(u64) - 10);
        try testing.expectError(error.Overflow, Entry.init(near_max, 20));

        const max = std.math.maxInt(DmaAddr.Int);
        const last = try Entry.init(DmaAddr.from(max), 1);
        const tail = try Entry.init(DmaAddr.from(max - 3), 4);
        const empty = try Entry.init(DmaAddr.from(max), 0);

        last.assertValid();
        tail.assertValid();
        empty.assertValid();
        try testing.expectEqual(max, (try last.range()).?.start);
        try testing.expectEqual(max, (try last.range()).?.end);
        try testing.expectEqual(max - 3, (try tail.range()).?.start);
        try testing.expectEqual(max, (try tail.range()).?.end);
        try testing.expect((try empty.range()) == null);
        try testing.expectError(error.Overflow, Entry.init(DmaAddr.from(max), 2));

        {
            const bad = entry(std.math.maxInt(u64) - 1, 10);
            try testing.expectError(error.Overflow, bad.range());
        }
    }

    test "Entry.fromBuffer matches buffer.dmaAddr and buffer.byteLen" {
        var backing: [4]u32 = undefined;
        const buf = try Buffer(u32).init(&backing, DmaAddr.from(0x1000));
        const s = Entry.fromBuffer(u32, buf);

        try testing.expectEqual(buf.dmaAddr().raw(), s.addr.raw());
        try testing.expectEqual(buf.byteLen(), s.len);
    }

    test "entry alignment validates address and byte length" {
        const cases = [_]AlignmentCase{
            .{ .base = 0, .len = 0, .alignment = 1, .expected = true },
            .{ .base = 1, .len = 3, .alignment = 1, .expected = true },
            .{ .base = 0xABCDEF, .len = 0xFEDCBA, .alignment = 1, .expected = true },
            .{ .base = 0, .len = 0, .alignment = 0, .expected = false },
            .{ .base = 0x1000, .len = 4096, .alignment = 0, .expected = false },
            .{ .base = 0x1000, .len = 4096, .alignment = 3, .expected = false },
            .{ .base = 0x1000, .len = 4096, .alignment = 4096, .expected = true },
            .{ .base = 0x1001, .len = 4096, .alignment = 4096, .expected = false },
            .{ .base = 0x1000, .len = 4097, .alignment = 4096, .expected = false },
            .{ .base = 0x1000, .len = 512, .alignment = 512, .expected = true },
        };

        for (cases) |case| {
            try testing.expectEqual(case.expected, entry(case.base, case.len).isAligned(case.alignment));
        }
    }

    test "Impl append, total length and validation" {
        var entries: [2]Entry = undefined;
        var count: usize = 0;

        try Impl.append(&entries, &count, entry(0x1000, 64));

        Impl.appendAssumeCapacity(&entries, &count, entry(0x2000, 128));
        Impl.assertValid(&entries, count);

        try testing.expectEqual(@as(usize, 2), count);
        try testing.expectEqual(@as(DmaAddr.Int, 192), try Impl.totalByteLen(entries[0..count]));
        try testing.expectError(error.Full, Impl.append(&entries, &count, entry(std.math.maxInt(DmaAddr.Int), 1)));
        try testing.expectEqual(@as(usize, 2), count);
        try testing.expectEqual(@as(DmaAddr.Int, 128), entries[1].len);

        const large = [_]Entry{ entry(0, std.math.maxInt(DmaAddr.Int)), entry(0, 1) };
        try testing.expectError(error.Overflow, Impl.totalByteLen(&large));
    }

    test "Impl aligned append preserves errors and contents" {
        var entries: [1]Entry = undefined;
        var count: usize = 0;

        try testing.expectError(error.Misaligned, Impl.appendAligned(4096, &entries, &count, entry(0x1001, 4096)));
        try testing.expectError(error.Misaligned, Impl.appendAligned(4096, &entries, &count, entry(0x1000, 4097)));
        try testing.expectEqual(@as(usize, 0), count);
        try Impl.appendAligned(4096, &entries, &count, entry(0x1000, 4096));
        Impl.assertAligned(4096, &entries, count);
        try testing.expectError(error.Misaligned, Impl.appendAligned(4096, &entries, &count, entry(0x1001, 4096)));
        try testing.expectError(error.Full, Impl.appendAligned(4096, &entries, &count, entry(0x2000, 4096)));
        try testing.expectEqual(@as(usize, 1), count);
        try testing.expectEqual(@as(DmaAddr.Int, 0x1000), entries[0].addr.raw());

        count = 0;
        try Impl.appendAligned(1, &entries, &count, entry(0x1001, 3));
        Impl.assertAligned(1, &entries, count);
    }

    test "inline lists own storage and expose const and mutable access" {
        var backing: [4]u32 = undefined;
        const buf = try Buffer(u32).init(&backing, DmaAddr.from(0x1000));

        var list = List.Static(2).init();
        try testing.expect(list.isEmpty());

        try list.appendBuffer(u32, buf);

        var copy = list;
        (try copy.atMut(0)).len = 8;

        try testing.expectEqual(@as(DmaAddr.Int, 16), (try list.at(0)).len);
        try testing.expectEqual(@as(DmaAddr.Int, 8), copy.slice()[0].len);

        copy.sliceMut()[0].len = 4;
        try testing.expectEqual(@as(DmaAddr.Int, 4), try copy.totalByteLen());

        copy.clearRetainingCapacity();
        try testing.expect(copy.isEmpty());
        try testing.expectEqual(@as(usize, 2), copy.remaining());
    }

    test "bounded lists borrow storage and accept zero capacity" {
        var storage = [_]Entry{entry(0x3000, 32)};
        var list = List.Bounded.wrap(&storage);

        try testing.expect(list.isEmpty());
        try testing.expectEqual(@as(usize, 0), list.slice().len);
        try testing.expectEqual(@as(DmaAddr.Int, 32), storage[0].len);
        try testing.expectError(error.OutOfBounds, list.at(0));
        try testing.expectError(error.OutOfBounds, list.atMut(0));

        list.appendAssumeCapacity(entry(0x1000, 8));

        try testing.expectEqual(&storage[0], try list.atMut(0));
        list.sliceMut()[0].len = 4;

        const view: *const List.Bounded = &list;
        try testing.expectEqual(@as(DmaAddr.Int, 4), (try view.at(0)).len);
        list.assertValid();

        try testing.expectEqual(@as(DmaAddr.Int, 4), storage[0].len);
        try testing.expectEqual(@as(DmaAddr.Int, 4), try list.totalByteLen());
        list.clearRetainingCapacity();
        try testing.expectEqual(@as(usize, 1), list.remaining());

        var empty: [0]Entry = .{};
        var zero = List.Bounded.wrap(&empty);

        try testing.expect(zero.isEmpty());
        try testing.expect(zero.isFull());
        try testing.expectError(error.Full, zero.append(entry(0, 0)));
        try testing.expectError(error.OutOfBounds, zero.at(0));
        try testing.expectError(error.OutOfBounds, zero.atMut(0));
        try testing.expectEqual(@as(usize, 0), zero.slice().len);
    }

    test "inline builders finish through a const receiver" {
        var backing: [8]u8 = undefined;
        const buf = try Buffer(u8).init(&backing, DmaAddr.from(0x1000));

        var builder = Builder.Static(1, 8).init();
        try builder.appendBuffer(u8, buf);

        try testing.expect(builder.isFull());

        const ptr: *const @TypeOf(builder) = &builder;
        try testing.expectEqual(@as(DmaAddr.Int, 8), (try ptr.finish().at(0)).len);
        try testing.expectEqual(@as(usize, 1), ptr.slice().len);

        builder.sliceMut()[0].len = 8;
        builder.assertValid();

        try testing.expectEqual(@as(DmaAddr.Int, 8), builder.slice()[0].len);

        builder.clearRetainingCapacity();
        try testing.expectEqual(@as(usize, 1), builder.remaining());
    }

    test "bounded builders retain borrowed ownership and zero capacity" {
        var storage = [_]Entry{entry(0x4000, 16)};
        var builder = Builder.Bounded(8).wrap(&storage);

        try testing.expect(builder.isEmpty());
        try testing.expectEqual(@as(usize, 0), builder.finish().slice().len);
        try testing.expectEqual(@as(DmaAddr.Int, 16), storage[0].len);

        try builder.append(entry(0x1000, 8));
        try testing.expectEqual(&storage[0], &builder.sliceMut()[0]);

        builder.sliceMut()[0].len = 16;

        const ptr: *const @TypeOf(builder) = &builder;
        try testing.expectEqual(@as(DmaAddr.Int, 16), ptr.finish().slice()[0].len);

        builder.assertValid();
        builder.clearRetainingCapacity();

        try testing.expect(builder.isEmpty());
        try testing.expectEqual(@as(usize, 1), builder.capacity());

        var empty: [0]Entry = .{};
        var zero = Builder.Bounded(8).wrap(&empty);
        try testing.expectError(error.Misaligned, zero.append(entry(1, 8)));
        try testing.expectError(error.Full, zero.append(entry(0, 8)));
    }
};
