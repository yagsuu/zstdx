//! Strongly typed tag allocator family. See `docs/specs/tags/allocator.md`.

const std = @import("std");

const Bitmap = @import("bits").Set(u64);

const TagFactory = @import("tag.zig").Tag;
const BitmapWord = Bitmap.Word.Int;

pub const TagAllocator = struct {
    pub fn Static(
        comptime DomainT: type,
        comptime IntT: type,
        comptime capacity_tags: comptime_int,
    ) type {
        comptime {
            const max_tags: comptime_int = @as(comptime_int, std.math.maxInt(IntT)) + 1;

            if (capacity_tags <= 0) {
                @compileError("TagAllocator.Static capacity must be positive");
            }

            if (capacity_tags > max_tags) {
                @compileError("TagAllocator.Static capacity exceeds Int range");
            }
        }

        const TagT = TagFactory(DomainT, IntT);

        const Storage = Bitmap.Static(capacity_tags);

        return struct {
            bitmap: Storage = .{},
            allocated_count: usize = 0,

            const Self = @This();

            pub const Domain = DomainT;
            pub const Int = IntT;
            pub const Tag = TagT;

            pub const AllocError = error{OutOfTags};
            pub const ReserveError = error{ OutOfBounds, AlreadyAllocated };
            pub const FreeError = error{ OutOfBounds, NotAllocated };
            pub const Error = AllocError || ReserveError || FreeError;

            pub fn init() Self {
                return .{};
            }

            pub fn capacity(self: *const Self) usize {
                return self.bitmap.capacity();
            }

            pub fn allocated(self: *const Self) usize {
                return self.allocated_count;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.allocated_count;
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.allocated_count == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.allocated_count == self.capacity();
            }

            pub fn isAllocated(self: *const Self, tag: Tag) bool {
                const index = Impl.boundedIndex(tag, self.capacity()) orelse return false;
                return self.bitmap.isSet(index);
            }

            pub fn isFree(self: *const Self, tag: Tag) bool {
                const index = Impl.boundedIndex(tag, self.capacity()) orelse return false;
                return !self.bitmap.isSet(index);
            }

            pub fn allocOne(self: *Self) AllocError!Tag {
                return Impl.allocOne(Tag, &self.bitmap, &self.allocated_count);
            }

            pub fn reserveOne(self: *Self, tag: Tag) ReserveError!void {
                return Impl.reserveOne(Tag, &self.bitmap, &self.allocated_count, tag);
            }

            pub fn freeOne(self: *Self, tag: Tag) FreeError!void {
                return Impl.freeOne(Tag, &self.bitmap, &self.allocated_count, tag);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.bitmap.clearRetainingCapacity();
                self.allocated_count = 0;
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(&self.bitmap, self.allocated_count);
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
            }
        };
    }

    pub fn Bounded(
        comptime DomainT: type,
        comptime IntT: type,
    ) type {
        const TagT = TagFactory(DomainT, IntT);
        return struct {
            bitmap: Bitmap.Bounded,
            allocated_count: usize,

            const Self = @This();

            pub const Domain = DomainT;
            pub const Int = IntT;
            pub const Tag = TagT;

            pub const WrapError = error{OutOfBounds};
            pub const AllocError = error{OutOfTags};
            pub const ReserveError = error{ OutOfBounds, AlreadyAllocated };
            pub const FreeError = error{ OutOfBounds, NotAllocated };
            pub const Error = WrapError || AllocError || ReserveError || FreeError;

            pub fn wrap(words: []BitmapWord, tag_capacity: usize) WrapError!Self {
                if (!Impl.fitsInIntCapacity(Int, tag_capacity)) {
                    return error.OutOfBounds;
                }

                return .{
                    .bitmap = try Bitmap.Bounded.wrap(words, tag_capacity),
                    .allocated_count = 0,
                };
            }

            pub fn capacity(self: *const Self) usize {
                return self.bitmap.capacity();
            }

            pub fn allocated(self: *const Self) usize {
                return self.allocated_count;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.allocated_count;
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.allocated_count == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.allocated_count == self.capacity();
            }

            pub fn isAllocated(self: *const Self, tag: Tag) bool {
                const index = Impl.boundedIndex(tag, self.capacity()) orelse return false;
                return self.bitmap.isSet(index);
            }

            pub fn isFree(self: *const Self, tag: Tag) bool {
                const index = Impl.boundedIndex(tag, self.capacity()) orelse return false;
                return !self.bitmap.isSet(index);
            }

            pub fn allocOne(self: *Self) AllocError!Tag {
                return Impl.allocOne(Tag, &self.bitmap, &self.allocated_count);
            }

            pub fn reserveOne(self: *Self, tag: Tag) ReserveError!void {
                return Impl.reserveOne(Tag, &self.bitmap, &self.allocated_count, tag);
            }

            pub fn freeOne(self: *Self, tag: Tag) FreeError!void {
                return Impl.freeOne(Tag, &self.bitmap, &self.allocated_count, tag);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.bitmap.clearRetainingCapacity();
                self.allocated_count = 0;
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.fitsInIntCapacity(Int, self.capacity()) and
                    Impl.isValid(&self.bitmap, self.allocated_count);
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
            }
        };
    }
};

pub const unit = struct {
    const testing = std.testing;

    const DomainA = struct {};
    const DomainB = struct {};

    test "shared allocation order and errors" {
        const Tag = TagFactory(DomainA, u16);

        var bitmap = Bitmap.Static(130).init();
        var count: usize = 0;

        for (0..130) |index| {
            try testing.expectEqual(@as(u16, @intCast(index)), (try Impl.allocOne(Tag, &bitmap, &count)).raw());
        }

        const full = bitmap.items;

        try testing.expectError(error.OutOfTags, Impl.allocOne(Tag, &bitmap, &count));
        try testing.expectError(error.AlreadyAllocated, Impl.reserveOne(Tag, &bitmap, &count, Tag.from(3)));
        try testing.expectError(error.OutOfBounds, Impl.reserveOne(Tag, &bitmap, &count, Tag.from(130)));
        try testing.expectError(error.OutOfBounds, Impl.freeOne(Tag, &bitmap, &count, Tag.from(40000)));
        try testing.expectEqualSlices(u64, &full, &bitmap.items);
        try testing.expectEqual(@as(usize, 130), count);

        for ([_]u16{ 64, 1, 129 }) |index| {
            try Impl.freeOne(Tag, &bitmap, &count, Tag.from(index));
        }

        const holes = bitmap.items;

        try testing.expectError(error.NotAllocated, Impl.freeOne(Tag, &bitmap, &count, Tag.from(64)));
        try testing.expectEqualSlices(u64, &holes, &bitmap.items);
        try testing.expectEqual(@as(usize, 127), count);

        try Impl.reserveOne(Tag, &bitmap, &count, Tag.from(64));

        try testing.expectEqual(@as(u16, 1), (try Impl.allocOne(Tag, &bitmap, &count)).raw());
        try testing.expectEqual(@as(u16, 129), (try Impl.allocOne(Tag, &bitmap, &count)).raw());
        try testing.expect(Impl.isValid(&bitmap, count));
    }

    test "shared bitmap validation" {
        var words: [3]u64 = .{ 1, 1, 0 };
        var bitmap: Bitmap.Bounded = .{ .items = &words, .limit = 65 };

        try testing.expect(Impl.isValid(&bitmap, 2));
        bitmap.items = words[0..1];
        try testing.expect(!Impl.isValid(&bitmap, 1));
        bitmap.items = &words;
        try testing.expect(!Impl.isValid(&bitmap, 66));
        try testing.expect(!Impl.isValid(&bitmap, 1));

        words[1] = 2;
        try testing.expect(!Impl.isValid(&bitmap, 2));

        words[1] = 1;
        words[2] = 1;
        try testing.expect(!Impl.isValid(&bitmap, 2));
    }

    test "static storage and queries" {
        const S = TagAllocator.Static(DomainA, u16, 1);

        var a = S.init();

        try testing.expect(a.isEmpty());
        try testing.expect(!a.isFull());
        try testing.expectEqual(@as(usize, 1), a.capacity());
        try testing.expectEqual(@as(usize, 1), a.remaining());

        try a.reserveOne(S.Tag.from(0));

        try testing.expect(a.isFull());
        try testing.expect(a.isAllocated(S.Tag.from(0)));
        try testing.expect(!a.isFree(S.Tag.from(0)));
        try testing.expect(!a.isAllocated(S.Tag.from(1)));
        try testing.expect(!a.isFree(S.Tag.from(1)));

        try a.freeOne(S.Tag.from(0));
        try testing.expect(a.isFree(S.Tag.from(0)));

        _ = try a.allocOne();
        a.clearRetainingCapacity();
        try testing.expectEqual(@as(usize, 0), a.allocated());
        try testing.expectEqual(@as(u64, 0), a.bitmap.items[0]);

        a.assertValid();
    }

    test "borrowed storage and wrap validation" {
        const B = TagAllocator.Bounded(DomainA, u8);

        var words: [8]u64 = @splat(0xaa);
        const original = words;

        try testing.expectError(error.OutOfBounds, B.wrap(words[0..2], 129));
        try testing.expectError(error.OutOfBounds, B.wrap(&words, 257));
        try testing.expectEqualSlices(u64, &original, &words);

        var a = try B.wrap(&words, 256);
        try testing.expectEqual(@as(usize, 256), a.capacity());
        try testing.expectEqualSlices(u64, &@as([8]u64, @splat(0)), &words);

        try a.reserveOne(B.Tag.from(255));
        try testing.expect(a.isAllocated(B.Tag.from(255)));
        try testing.expectEqual(@as(usize, 255), a.remaining());

        try a.freeOne(B.Tag.from(255));
        try testing.expect(a.isFree(B.Tag.from(255)));
        try testing.expectEqual(@as(u8, 0), (try a.allocOne()).raw());

        words[7] = 1;
        try testing.expect(!a.isValid());

        a.clearRetainingCapacity();
        try testing.expectEqualSlices(u64, &@as([8]u64, @splat(0)), &words);

        a.assertValid();
        a.bitmap.limit = 257;
        try testing.expect(!a.isValid());

        var zero = try B.wrap(&words, 0);
        try testing.expect(zero.isEmpty());
        try testing.expect(zero.isFull());
        try testing.expectError(error.OutOfTags, zero.allocOne());
        try testing.expect(!zero.isAllocated(B.Tag.from(0)));
        try testing.expect(!zero.isFree(B.Tag.from(0)));

        zero.assertValid();

        const empty = try B.wrap(&.{}, 0);
        empty.assertValid();
    }

    test "allocator type identity" {
        comptime {
            const S = TagAllocator.Static(DomainA, u16, 64);
            std.debug.assert(S != TagAllocator.Static(DomainB, u16, 64));
            std.debug.assert(S != TagAllocator.Static(DomainA, u16, 128));
            std.debug.assert(TagAllocator.Bounded(DomainA, u16) != TagAllocator.Bounded(DomainB, u16));
            std.debug.assert(S.Tag == TagAllocator.Bounded(DomainA, u16).Tag);
            std.debug.assert(S.Tag == TagFactory(DomainA, u16));
        }
    }

    test "shared algorithms match reference" {
        try modelRun(DomainA, u16, 70, 0xC0FFEE, 4000);
        try modelRun(DomainB, u8, 200, 0xDEADBEEF, 4000);
        try modelRun(DomainA, u16, 129, 0xBADC0DE, 4000);
        try modelRun(DomainA, u5, 32, 0xABCDEF, 2000);
    }

    test "integer capacity boundary" {
        const Tag = TagFactory(DomainA, u5);
        var bitmap = Bitmap.Static(32).init();
        var count: usize = 0;

        for (0..32) |index| {
            try testing.expectEqual(@as(u5, @intCast(index)), (try Impl.allocOne(Tag, &bitmap, &count)).raw());
        }

        try testing.expectError(error.OutOfTags, Impl.allocOne(Tag, &bitmap, &count));
        try testing.expect(Impl.isValid(&bitmap, count));
    }

    fn modelRun(comptime Domain: type, comptime Int: type, capacity: usize, seed: u64, iterations: usize) !void {
        const Tag = TagFactory(Domain, Int);

        var words: [4]u64 = @splat(0);
        var bitmap = try Bitmap.Bounded.wrap(&words, capacity);
        var count: usize = 0;
        var used: [256]bool = @splat(false);

        var prng = std.Random.DefaultPrng.init(seed);
        const rng = prng.random();

        for (0..iterations) |_| {
            switch (rng.intRangeAtMost(u8, 0, 9)) {
                0, 1, 2, 3 => {
                    var first: ?usize = null;
                    for (used[0..capacity], 0..) |occupied, index| {
                        if (!occupied) {
                            first = index;
                            break;
                        }
                    }
                    const result = Impl.allocOne(Tag, &bitmap, &count);
                    if (first) |index| {
                        try testing.expectEqual(@as(Int, @intCast(index)), (try result).raw());
                        used[index] = true;
                    } else {
                        try testing.expectError(error.OutOfTags, result);
                    }
                },
                4, 5, 6, 7 => |op| {
                    const index = rng.intRangeAtMost(usize, 0, capacity + 4);
                    if (index > std.math.maxInt(Int)) {
                        continue;
                    }
                    const tag = Tag.from(@intCast(index));
                    if (op <= 5) {
                        const result = Impl.reserveOne(Tag, &bitmap, &count, tag);
                        if (index >= capacity) {
                            try testing.expectError(error.OutOfBounds, result);
                        } else if (used[index]) {
                            try testing.expectError(error.AlreadyAllocated, result);
                        } else {
                            try result;
                            used[index] = true;
                        }
                    } else {
                        const result = Impl.freeOne(Tag, &bitmap, &count, tag);
                        if (index >= capacity) {
                            try testing.expectError(error.OutOfBounds, result);
                        } else if (!used[index]) {
                            try testing.expectError(error.NotAllocated, result);
                        } else {
                            try result;
                            used[index] = false;
                        }
                    }
                },
                8 => {
                    bitmap.clearRetainingCapacity();
                    count = 0;
                    @memset(&used, false);
                },
                9 => {
                    for (used[0..capacity], 0..) |occupied, index| {
                        try testing.expectEqual(occupied, bitmap.isSet(index));
                    }
                },
                else => unreachable,
            }
            var expected_count: usize = 0;
            for (used[0..capacity]) |occupied| {
                expected_count += @intFromBool(occupied);
            }
            try testing.expectEqual(expected_count, count);
            try testing.expect(Impl.isValid(&bitmap, count));
        }

        for (used[0..capacity], 0..) |occupied, index| {
            try testing.expectEqual(occupied, bitmap.isSet(index));
        }
    }
};

const Impl = struct {
    fn allocOne(comptime Tag: type, bitmap: anytype, count: *usize) error{OutOfTags}!Tag {
        std.debug.assert(count.* <= bitmap.capacity());

        const index = bitmap.firstUnset() orelse return error.OutOfTags;
        _ = bitmap.set(index) catch unreachable;
        count.* += 1;

        return Tag.from(@intCast(index));
    }

    fn reserveOne(
        comptime Tag: type,
        bitmap: anytype,
        count: *usize,
        tag: Tag,
    ) error{ OutOfBounds, AlreadyAllocated }!void {
        std.debug.assert(count.* <= bitmap.capacity());

        const index = boundedIndex(tag, bitmap.capacity()) orelse return error.OutOfBounds;
        if (bitmap.set(index) catch unreachable) {
            return error.AlreadyAllocated;
        }
        count.* += 1;
    }

    fn freeOne(
        comptime Tag: type,
        bitmap: anytype,
        count: *usize,
        tag: Tag,
    ) error{ OutOfBounds, NotAllocated }!void {
        std.debug.assert(count.* <= bitmap.capacity());

        const index = boundedIndex(tag, bitmap.capacity()) orelse return error.OutOfBounds;
        if (!(bitmap.unset(index) catch unreachable)) {
            return error.NotAllocated;
        }
        count.* -= 1;
    }

    fn boundedIndex(tag: anytype, capacity: usize) ?usize {
        const raw: @TypeOf(tag).Int = tag.raw();
        const index = std.math.cast(usize, raw) orelse return null;
        if (index >= capacity) {
            return null;
        }
        return index;
    }

    fn fitsInIntCapacity(comptime IntT: type, capacity: usize) bool {
        const max_tags: comptime_int = @as(comptime_int, std.math.maxInt(IntT)) + 1;
        if (max_tags >= @as(comptime_int, std.math.maxInt(usize)) + 1) {
            return true;
        }
        return capacity <= @as(usize, max_tags);
    }

    fn isValid(bitmap: anytype, count: usize) bool {
        const capacity = bitmap.capacity();
        const words: []const BitmapWord = bitmap.items[0..];
        const word_count = capacity / Bitmap.Word.width + @intFromBool(capacity % Bitmap.Word.width != 0);
        if (word_count > words.len or count > capacity) {
            return false;
        }

        const remainder = capacity % Bitmap.Word.width;
        const last_mask = if (remainder == 0) Bitmap.Word.full else Bitmap.Word.maskOf(remainder) - 1;

        var total: usize = 0;
        for (words[0..word_count], 0..) |value, index| {
            if (index == word_count - 1 and value & ~last_mask != 0) {
                return false;
            }
            total += @popCount(value);
        }

        if (total != count) {
            return false;
        }

        for (words[word_count..]) |value| {
            if (value != 0) {
                return false;
            }
        }

        return true;
    }
};
