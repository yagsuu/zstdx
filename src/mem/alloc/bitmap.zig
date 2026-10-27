//! fixed-unit allocation with lowest-index first-fit placement

const std = @import("std");

const debug = @import("core").debug;

const Bitmap = @import("bits").Set(u64);
const RangeUsize = @import("ranges").Range(usize);

pub const BitmapAllocator = struct {
    pub fn Static(comptime count: usize) type {
        if (count == 0) {
            @compileError("BitmapAllocator.Static count must be non-zero");
        }

        return struct {
            bitmap: Bitmap.Static(count) = .{},

            pub const bound = count;

            const Self = @This();

            pub const Range = RangeUsize;
            pub const Error = Impl.Error.All;
            pub const AllocError = Impl.Error.Alloc;
            pub const ReserveError = Impl.Error.Reserve;
            pub const FreeError = Impl.Error.Free;

            pub fn init() Self {
                return .{};
            }

            pub fn capacity(_: *const Self) usize {
                return bound;
            }

            pub fn allocated(self: *const Self) usize {
                return self.bitmap.count();
            }

            pub fn remaining(self: *const Self) usize {
                return bound - self.allocated();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.allocated() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.allocated() == bound;
            }

            pub fn isAllocated(self: *const Self, index: usize) bool {
                return self.bitmap.isSet(index);
            }

            pub fn isFree(self: *const Self, index: usize) bool {
                if (index >= bound) {
                    return false;
                }
                return !self.bitmap.isSet(index);
            }

            pub fn allocOne(self: *Self) AllocError!usize {
                return Impl.allocOne(&self.bitmap);
            }

            pub fn allocRange(self: *Self, len: usize) AllocError!Range {
                return Impl.allocRange(&self.bitmap, len);
            }

            pub fn reserveOne(self: *Self, index: usize) ReserveError!void {
                return Impl.reserveOne(&self.bitmap, index);
            }

            pub fn reserveRange(self: *Self, range: Range) ReserveError!void {
                return Impl.reserveRange(&self.bitmap, range);
            }

            pub fn freeOne(self: *Self, index: usize) FreeError!void {
                return Impl.freeOne(&self.bitmap, index);
            }

            pub fn freeRange(self: *Self, range: Range) FreeError!void {
                return Impl.freeRange(&self.bitmap, range);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.bitmap.clearRetainingCapacity();
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(&self.bitmap);
            }
        };
    }

    pub const Bounded = struct {
        bitmap: Bitmap.Bounded,

        const Self = @This();

        pub const Range = RangeUsize;
        pub const Word = Bitmap.Word;
        pub const WrapError = Impl.Error.Wrap;
        pub const AllocError = Impl.Error.Alloc;
        pub const ReserveError = Impl.Error.Reserve;
        pub const FreeError = Impl.Error.Free;
        pub const Error = Impl.Error.All;

        pub fn wrap(items: []Word, count: usize) WrapError!Self {
            return .{ .bitmap = try Bitmap.Bounded.wrap(items, count) };
        }

        pub fn capacity(self: *const Self) usize {
            return self.bitmap.capacity();
        }

        pub fn allocated(self: *const Self) usize {
            return self.bitmap.count();
        }

        pub fn remaining(self: *const Self) usize {
            return self.capacity() - self.allocated();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.allocated() == 0;
        }

        pub fn isFull(self: *const Self) bool {
            return self.allocated() == self.capacity();
        }

        pub fn isAllocated(self: *const Self, index: usize) bool {
            return self.bitmap.isSet(index);
        }

        pub fn isFree(self: *const Self, index: usize) bool {
            if (index >= self.capacity()) {
                return false;
            }
            return !self.bitmap.isSet(index);
        }

        pub fn allocOne(self: *Self) AllocError!usize {
            return Impl.allocOne(&self.bitmap);
        }

        pub fn allocRange(self: *Self, count: usize) AllocError!Range {
            return Impl.allocRange(&self.bitmap, count);
        }

        pub fn reserveOne(self: *Self, index: usize) ReserveError!void {
            return Impl.reserveOne(&self.bitmap, index);
        }

        pub fn reserveRange(self: *Self, range: Range) ReserveError!void {
            return Impl.reserveRange(&self.bitmap, range);
        }

        pub fn freeOne(self: *Self, index: usize) FreeError!void {
            return Impl.freeOne(&self.bitmap, index);
        }

        pub fn freeRange(self: *Self, range: Range) FreeError!void {
            return Impl.freeRange(&self.bitmap, range);
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.bitmap.clearRetainingCapacity();
        }

        pub fn isValid(self: *const Self) bool {
            return Impl.isValid(&self.bitmap);
        }
    };
};

const Impl = struct {
    const Error = struct {
        const Wrap = error{OutOfBounds};
        const Alloc = error{OutOfMemory};
        const Reserve = error{ OutOfBounds, AlreadyAllocated };
        const Free = error{ OutOfBounds, NotAllocated };
        const All = Wrap || Alloc || Reserve || Free;
    };

    fn allocOne(bitmap: anytype) Error.Alloc!usize {
        const index = bitmap.firstUnset() orelse return error.OutOfMemory;
        _ = bitmap.set(index) catch unreachable;
        return index;
    }

    fn allocRange(bitmap: anytype, count: usize) Error.Alloc!RangeUsize {
        if (count == 0) {
            return RangeUsize.empty(0);
        }

        if (count > bitmap.capacity()) {
            return error.OutOfMemory;
        }

        if (debug.checksEnabled()) {
            bitmap.assertValid();
        }

        const start = findFreeRun(bitmap, count) orelse return error.OutOfMemory;
        for (start..start + count) |index| {
            _ = bitmap.set(index) catch unreachable;
        }

        return RangeUsize.init(start, start + count) catch unreachable;
    }

    fn reserveOne(bitmap: anytype, index: usize) Error.Reserve!void {
        if (try bitmap.set(index)) {
            return error.AlreadyAllocated;
        }
    }

    fn reserveRange(bitmap: anytype, range: RangeUsize) Error.Reserve!void {
        range.assertValid();

        if (range.end > bitmap.capacity()) {
            return error.OutOfBounds;
        }

        if (!range.isEmpty() and debug.checksEnabled()) {
            bitmap.assertValid();
        }

        for (range.start..range.end) |index| {
            if (bitmap.isSet(index)) {
                return error.AlreadyAllocated;
            }
        }

        for (range.start..range.end) |index| {
            _ = bitmap.set(index) catch unreachable;
        }
    }

    fn freeOne(bitmap: anytype, index: usize) Error.Free!void {
        if (!(try bitmap.unset(index))) {
            return error.NotAllocated;
        }
    }

    fn freeRange(bitmap: anytype, range: RangeUsize) Error.Free!void {
        range.assertValid();

        if (range.end > bitmap.capacity()) {
            return error.OutOfBounds;
        }

        if (!range.isEmpty() and debug.checksEnabled()) {
            bitmap.assertValid();
        }

        for (range.start..range.end) |index| {
            if (!bitmap.isSet(index)) {
                return error.NotAllocated;
            }
        }

        for (range.start..range.end) |index| {
            _ = bitmap.unset(index) catch unreachable;
        }
    }

    fn findFreeRun(bitmap: anytype, count: usize) ?usize {
        var start: usize = 0;
        var len: usize = 0;

        for (0..bitmap.capacity()) |index| {
            if (bitmap.isSet(index)) {
                len = 0;
                continue;
            }

            if (len == 0) {
                start = index;
            }

            len += 1;

            if (len == count) {
                return start;
            }
        }

        return null;
    }

    fn isValid(bitmap: anytype) bool {
        const capacity = bitmap.capacity();
        const words = bitmap.items[0..];
        const count = Bitmap.Word.wordsFor(capacity);

        if (count > words.len) {
            return false;
        }

        const remainder = capacity % Bitmap.Word.width;
        if (count > 0 and remainder != 0) {
            const mask = Bitmap.Word.maskOf(remainder) - 1;
            if (words[count - 1].raw() & ~mask != 0) {
                return false;
            }
        }

        for (words[count..]) |word| {
            if (word != .zero) {
                return false;
            }
        }

        return true;
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "lowest-first allocation reuses released units and stops at the tail" {
        var bitmap = Bitmap.Static(65).init();
        try Impl.reserveOne(&bitmap, 0);

        for (1..65) |index| {
            try testing.expectEqual(index, try Impl.allocOne(&bitmap));
        }

        try testing.expectError(error.OutOfMemory, Impl.allocOne(&bitmap));
        try testing.expect(Impl.isValid(&bitmap));

        try Impl.freeOne(&bitmap, 31);

        try testing.expectEqual(@as(usize, 31), try Impl.allocOne(&bitmap));
        try testing.expectError(error.AlreadyAllocated, Impl.reserveOne(&bitmap, 31));
        try testing.expectError(error.OutOfBounds, Impl.reserveOne(&bitmap, 65));
        try testing.expectError(error.OutOfBounds, Impl.freeOne(&bitmap, 65));
    }

    test "contiguous placement crosses words and rejects fragmented free space" {
        var bitmap = Bitmap.Static(129).init();

        try Impl.reserveRange(&bitmap, try RangeUsize.init(0, 62));
        const range = try Impl.allocRange(&bitmap, 5);
        const tail = try Impl.allocRange(&bitmap, 62);

        try testing.expectEqual(try RangeUsize.init(62, 67), range);
        try testing.expectEqual(try RangeUsize.init(67, 129), tail);
        try testing.expectError(error.OutOfMemory, Impl.allocRange(&bitmap, 1));

        bitmap.clearRetainingCapacity();

        var index: usize = 1;
        while (index < bitmap.capacity()) : (index += 2) {
            try Impl.reserveOne(&bitmap, index);
        }

        const before = bitmap.items;

        try testing.expectError(error.OutOfMemory, Impl.allocRange(&bitmap, 2));
        try testing.expectEqual(before, bitmap.items);
    }

    test "range errors preflight all units and empty boundary ranges do not mutate" {
        var bitmap = Bitmap.Static(65).init();
        try Impl.reserveRange(&bitmap, try RangeUsize.init(62, 65));
        const before = bitmap.items;

        try testing.expectError(error.AlreadyAllocated, Impl.reserveRange(&bitmap, try RangeUsize.init(60, 64)));
        try testing.expectError(error.NotAllocated, Impl.freeRange(&bitmap, try RangeUsize.init(61, 65)));
        try testing.expectError(error.NotAllocated, Impl.freeOne(&bitmap, 0));
        try testing.expectError(error.OutOfBounds, Impl.reserveRange(&bitmap, try RangeUsize.init(64, 66)));
        try testing.expectError(error.OutOfBounds, Impl.freeRange(&bitmap, try RangeUsize.init(66, 66)));
        try testing.expectEqual(before, bitmap.items);

        try Impl.reserveRange(&bitmap, RangeUsize.empty(65));
        try Impl.freeRange(&bitmap, RangeUsize.empty(65));

        try testing.expectEqual(RangeUsize.empty(0), try Impl.allocRange(&bitmap, 0));
        try testing.expectEqual(before, bitmap.items);

        try Impl.freeRange(&bitmap, try RangeUsize.init(62, 65));

        try testing.expectEqual(@as(usize, 0), bitmap.count());
    }

    test "validation checks both tail bits and trailing borrowed words" {
        var items: [3]Bitmap.Word = @splat(.zero);
        var allocator = try BitmapAllocator.Bounded.wrap(&items, 65);
        items[1] = Bitmap.Word.from(2);

        try testing.expect(!allocator.isValid());

        items[1] = .zero;
        items[2] = Bitmap.Word.from(1);

        try testing.expect(!allocator.isValid());

        allocator.clearRetainingCapacity();

        try testing.expect(allocator.isValid());
        try testing.expectEqual([_]Bitmap.Word{ .zero, .zero, .zero }, items);
    }

    test "borrowed storage validates before clearing and supports zero capacity" {
        var items: [3]Bitmap.Word = .{ Bitmap.Word.from(0xff), Bitmap.Word.from(0xaa), Bitmap.Word.from(0x55) };
        const before = items;

        try testing.expectError(error.OutOfBounds, BitmapAllocator.Bounded.wrap(&items, 193));
        try testing.expectEqual(before, items);

        var allocator = try BitmapAllocator.Bounded.wrap(&items, 65);
        const range = try allocator.allocRange(65);

        try testing.expectEqual(try RangeUsize.init(0, 65), range);
        try testing.expect(allocator.isFull());
        try testing.expect(!allocator.isAllocated(65));
        try testing.expect(!allocator.isFree(65));
        try testing.expectEqual(Bitmap.Word.zero, items[2]);

        var empty = try BitmapAllocator.Bounded.wrap(&items, 0);

        try testing.expectEqual([_]Bitmap.Word{ .zero, .zero, .zero }, items);
        try testing.expect(empty.isEmpty() and empty.isFull());
        try testing.expectError(error.OutOfMemory, empty.allocOne());
        try testing.expectEqual(RangeUsize.empty(0), try empty.allocRange(0));

        try empty.reserveRange(RangeUsize.empty(0));
        try empty.freeRange(RangeUsize.empty(0));
    }

    test "static storage can be cleared and reused without changing capacity" {
        var allocator = BitmapAllocator.Static(1).init();
        const index = try allocator.allocOne();

        try testing.expectEqual(@as(usize, 0), index);
        try testing.expect(allocator.isFull());
        try testing.expect(!allocator.isAllocated(1) and !allocator.isFree(1));

        allocator.clearRetainingCapacity();

        try testing.expectEqual(@as(usize, 1), allocator.remaining());
        try testing.expectEqual(@as(usize, 0), try allocator.allocOne());
    }

    const Model = struct {
        items: [129]bool = @splat(false),

        fn alloc(self: *Model, count: usize) error{OutOfMemory}!RangeUsize {
            if (count == 0) {
                return RangeUsize.empty(0);
            }

            if (count > self.items.len) {
                return error.OutOfMemory;
            }

            for (0..self.items.len - count + 1) |start| {
                const run = self.items[start..][0..count];
                if (std.mem.findScalar(bool, run, true) == null) {
                    @memset(run, true);
                    return RangeUsize.init(start, start + count) catch unreachable;
                }
            }

            return error.OutOfMemory;
        }

        fn change(self: *Model, range: RangeUsize, allocated: bool) (Impl.Error.Reserve || Impl.Error.Free)!void {
            if (range.end > self.items.len) {
                return error.OutOfBounds;
            }

            const items = self.items[range.start..range.end];
            if (std.mem.findScalar(bool, items, allocated) != null) {
                return switch (allocated) {
                    true => error.AlreadyAllocated,
                    false => error.NotAllocated,
                };
            }

            @memset(items, allocated);
        }
    };

    fn expectResult(comptime T: type, expected: anyerror!T, actual: anyerror!T) !void {
        if (expected) |value| {
            try testing.expectEqualDeep(value, try actual);
        } else |err| {
            try testing.expectError(err, actual);
        }
    }

    fn checkModel(allocator: anytype) !void {
        var model: Model = .{};
        var rng = std.Random.DefaultPrng.init(0xBADC0FFEE_0DDF00D);

        const random = rng.random();

        for (0..4_000) |_| {
            const start = random.intRangeAtMost(usize, 0, model.items.len + 4);
            const end = random.intRangeAtMost(usize, start, model.items.len + 4);
            const range = try RangeUsize.init(start, end);

            switch (random.intRangeAtMost(u8, 0, 6)) {
                0 => {
                    const expected = model.alloc(1);
                    const actual = allocator.allocOne();

                    if (expected) |allocated| {
                        try testing.expectEqual(allocated.start, try actual);
                    } else |err| {
                        try testing.expectError(err, actual);
                    }
                },
                1 => {
                    const count = random.intRangeAtMost(usize, 0, 12);
                    try expectResult(RangeUsize, model.alloc(count), allocator.allocRange(count));
                },
                2 => try expectResult(void, model.change(try RangeUsize.init(start, start + 1), true), allocator.reserveOne(start)),
                3 => try expectResult(void, model.change(range, true), allocator.reserveRange(range)),
                4 => try expectResult(void, model.change(try RangeUsize.init(start, start + 1), false), allocator.freeOne(start)),
                5 => try expectResult(void, model.change(range, false), allocator.freeRange(range)),
                6 => {
                    allocator.clearRetainingCapacity();
                    @memset(&model.items, false);
                },
                else => unreachable,
            }

            var count: usize = 0;
            for (model.items, 0..) |allocated, index| {
                try testing.expectEqual(allocated, allocator.isAllocated(index));
                count += @intFromBool(allocated);
            }

            try testing.expectEqual(count, allocator.allocated());
            try testing.expectEqual(model.items.len - count, allocator.remaining());
            try testing.expect(allocator.isValid());
        }
    }

    test "both storage variants match the same deterministic allocation model" {
        var fixed = BitmapAllocator.Static(129).init();
        var items: [3]Bitmap.Word = @splat(.zero);
        var bounded = try BitmapAllocator.Bounded.wrap(&items, 129);

        try checkModel(&fixed);
        try checkModel(&bounded);
    }
};
