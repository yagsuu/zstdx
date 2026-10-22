//! Fixed-capacity canonical range sets. See `docs/specs/ranges/set.md`.

const std = @import("std");

const core = @import("core");

pub const RangeSet = struct {
    pub fn Static(comptime T: type, comptime capacity_ranges: usize) type {
        comptime {
            if (capacity_ranges == 0) {
                @compileError("RangeSet.Static capacity_ranges must be non-zero");
            }
        }

        return struct {
            buffer: [capacity_ranges]Range = undefined,
            count: usize = 0,

            const Self = @This();

            pub const Range = core.Range(T);
            pub const Error = error{ Full, InvalidRange };

            pub const range_capacity = capacity_ranges;

            pub fn init() Self {
                return .{};
            }

            pub fn len(self: *const Self) usize {
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return range_capacity;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.len() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.len() == range_capacity;
            }

            pub fn asSlice(self: *const Self) []const Range {
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            /// An empty range is a no-op. On success, prior slices are invalid. On error, the set is unchanged.
            pub fn insert(self: *Self, range: Range) Error!void {
                try Impl.insertRange(Range, self.buffer[0..], &self.count, range);
            }

            /// Empty or disjoint ranges are no-ops. On success, prior slices are invalid. On error, the set is unchanged.
            pub fn remove(self: *Self, range: Range) Error!void {
                try Impl.removeRange(Range, self.buffer[0..], &self.count, range);
            }

            pub fn contains(self: *const Self, value: T) bool {
                return self.findContaining(value) != null;
            }

            pub fn containsRange(self: *const Self, range: Range) bool {
                return Impl.containsRangeInSlice(Range, self.asSlice(), range);
            }

            pub fn overlaps(self: *const Self, range: Range) bool {
                return self.findIntersecting(range) != null;
            }

            pub fn findContaining(self: *const Self, value: T) ?Range {
                return Impl.findContainingValue(Range, self.asSlice(), value);
            }

            /// Returns the first non-empty intersection in ascending order, or `null` if no stored range intersects.
            pub fn findIntersecting(self: *const Self, range: Range) ?Range {
                return Impl.findIntersectingRange(Range, self.asSlice(), range);
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertCanonical(Range, self.buffer[0..], self.count);
            }
        };
    }

    pub fn Bounded(comptime T: type) type {
        return struct {
            buffer: []Range,
            count: usize = 0,

            const Self = @This();

            pub const Range = core.Range(T);
            pub const Error = error{ Full, InvalidRange };

            pub fn wrap(buffer: []Range) Self {
                return .{ .buffer = buffer };
            }

            pub fn len(self: *const Self) usize {
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                return self.buffer.len;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.len() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.len() == self.capacity();
            }

            pub fn asSlice(self: *const Self) []const Range {
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            /// An empty range is a no-op. On success, prior slices are invalid. On error, the set is unchanged.
            pub fn insert(self: *Self, range: Range) Error!void {
                try Impl.insertRange(Range, self.buffer, &self.count, range);
            }

            /// Empty or disjoint ranges are no-ops. On success, prior slices are invalid. On error, the set is unchanged.
            pub fn remove(self: *Self, range: Range) Error!void {
                try Impl.removeRange(Range, self.buffer, &self.count, range);
            }

            pub fn contains(self: *const Self, value: T) bool {
                return self.findContaining(value) != null;
            }

            pub fn containsRange(self: *const Self, range: Range) bool {
                return Impl.containsRangeInSlice(Range, self.asSlice(), range);
            }

            pub fn overlaps(self: *const Self, range: Range) bool {
                return self.findIntersecting(range) != null;
            }

            pub fn findContaining(self: *const Self, value: T) ?Range {
                return Impl.findContainingValue(Range, self.asSlice(), value);
            }

            /// Returns the first non-empty intersection in ascending order, or `null` if no stored range intersects.
            pub fn findIntersecting(self: *const Self, range: Range) ?Range {
                return Impl.findIntersectingRange(Range, self.asSlice(), range);
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertCanonical(Range, self.buffer, self.count);
            }
        };
    }
};

const Impl = struct {
    fn insertRange(comptime Range: type, buffer: []Range, count: *usize, range: Range) error{ Full, InvalidRange }!void {
        if (!range.isValid()) {
            return error.InvalidRange;
        }

        if (range.isEmpty()) {
            return;
        }

        var merged = range;
        var first: usize = 0;

        while (first < count.* and buffer[first].end < merged.start) : (first += 1) {}

        var last = first;
        while (last < count.* and buffer[last].start <= merged.end) : (last += 1) {
            merged = merged.span(buffer[last]);
        }

        const removed = last - first;
        const new_count = count.* - removed + 1;

        if (new_count > buffer.len) {
            return error.Full;
        }

        if (removed == 0) {
            std.mem.copyBackwards(Range, buffer[first + 1 .. count.* + 1], buffer[first..count.*]);
            buffer[first] = merged;
        } else {
            buffer[first] = merged;
            if (last < count.*) {
                std.mem.copyForwards(Range, buffer[first + 1 .. new_count], buffer[last..count.*]);
            }
        }

        count.* = new_count;
    }

    fn removeRange(comptime Range: type, buffer: []Range, count: *usize, range: Range) error{ Full, InvalidRange }!void {
        if (!range.isValid()) {
            return error.InvalidRange;
        }

        if (range.isEmpty()) {
            return;
        }

        if (count.* == buffer.len) {
            for (buffer[0..count.*]) |stored| {
                if (stored.start < range.start and range.end < stored.end) {
                    return error.Full;
                }
            }
        }

        var i: usize = 0;
        while (i < count.*) {
            const stored = buffer[i];
            switch (classify(Range, stored, range)) {
                .disjoint => i += 1,
                .covers => {
                    std.mem.copyForwards(Range, buffer[i .. count.* - 1], buffer[i + 1 .. count.*]);
                    count.* -= 1;
                },
                .trim_left => {
                    buffer[i].start = range.end;
                    i += 1;
                },
                .trim_right => {
                    buffer[i].end = range.start;
                    i += 1;
                },
                .split => {
                    const tail = Range{ .start = range.end, .end = stored.end };
                    buffer[i].end = range.start;
                    std.mem.copyBackwards(Range, buffer[i + 2 .. count.* + 1], buffer[i + 1 .. count.*]);
                    buffer[i + 1] = tail;
                    count.* += 1;
                    i += 2;
                },
            }
        }
    }

    fn findContainingValue(comptime Range: type, ranges: []const Range, value: anytype) ?Range {
        const Search = struct {
            fn compare(point: @TypeOf(value), stored: Range) std.math.Order {
                if (point < stored.start) {
                    return .lt;
                }
                if (point >= stored.end) {
                    return .gt;
                }
                return .eq;
            }
        };

        const index = std.sort.binarySearch(Range, ranges, value, Search.compare) orelse return null;
        return ranges[index];
    }

    fn containsRangeInSlice(comptime Range: type, ranges: []const Range, range: Range) bool {
        std.debug.assert(range.isValid());

        if (range.isEmpty()) {
            return containsEmptyBoundary(Range, ranges, range.start);
        }

        const containing = findContainingValue(Range, ranges, range.start) orelse return false;
        return containing.end >= range.end;
    }

    fn containsEmptyBoundary(comptime Range: type, ranges: []const Range, point: anytype) bool {
        for (ranges) |range| {
            if (range.start <= point and point <= range.end) {
                return true;
            }
            if (point < range.start) {
                return false;
            }
        }
        return false;
    }

    fn findIntersectingRange(comptime Range: type, ranges: []const Range, range: Range) ?Range {
        std.debug.assert(range.isValid());

        if (range.isEmpty()) {
            return null;
        }

        const Search = struct {
            fn before(start: @TypeOf(range.start), stored: Range) bool {
                return stored.end <= start;
            }
        };
        const index = std.sort.partitionPoint(Range, ranges, range.start, Search.before);
        if (index < ranges.len and ranges[index].start < range.end) {
            return ranges[index];
        }

        return null;
    }

    fn assertCanonical(comptime Range: type, buffer: []const Range, count: usize) void {
        std.debug.assert(count <= buffer.len);

        var previous: ?Range = null;
        for (buffer[0..count]) |range| {
            std.debug.assert(range.isValid());
            std.debug.assert(!range.isEmpty());

            if (previous) |prev| {
                std.debug.assert(prev.end < range.start);
            }

            previous = range;
        }
    }

    const Topology = enum { disjoint, covers, trim_left, trim_right, split };

    fn classify(comptime Range: type, stored: Range, range: Range) Topology {
        if (!stored.overlaps(range)) {
            return .disjoint;
        }

        if (range.start <= stored.start and range.end >= stored.end) {
            return .covers;
        }

        if (range.start <= stored.start) {
            return .trim_left;
        }

        if (range.end >= stored.end) {
            return .trim_right;
        }

        return .split;
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "variants retain static and borrowed capacity across clear" {
        var static = RangeSet.Static(u8, 1).init();
        var backing: [1]RangeSet.Bounded(u8).Range = undefined;
        var bounded = RangeSet.Bounded(u8).wrap(&backing);

        inline for (.{ &static, &bounded }) |set| {
            const Range = @TypeOf(set.*).Range;

            try set.insert(Range.of(10, 30));
            try testing.expect(set.asSlice().ptr == set.buffer[0..].ptr);
            try testing.expectEqual(@as(usize, 1), set.capacity());

            set.clearRetainingCapacity();

            try testing.expect(set.isEmpty());
            try testing.expectEqual(@as(usize, 1), set.capacity());
            try testing.expectEqual(@as(usize, 1), set.remaining());
            try testing.expectEqual(@as(usize, 0), set.asSlice().len);
            set.assertValid();
        }

        try testing.expect(bounded.asSlice().ptr == backing[0..].ptr);

        var zero_backing: [0]RangeSet.Bounded(u8).Range = .{};
        var zero = RangeSet.Bounded(u8).wrap(&zero_backing);

        try testing.expect(zero.isEmpty());
        try testing.expect(zero.isFull());
        try zero.insert(core.Range(u8).empty(0));
        try testing.expectError(error.Full, zero.insert(core.Range(u8).of(0, 1)));
        try zero.remove(core.Range(u8).of(0, 1));

        zero.assertValid();
    }

    test "insert canonicalizes sorted adjacent and overlapping ranges" {
        const Range = core.Range(u64);

        var buffer: [4]Range = undefined;
        var count: usize = 0;

        try Impl.insertRange(Range, &buffer, &count, Range.of(30, 40));
        try Impl.insertRange(Range, &buffer, &count, Range.of(10, 20));
        try Impl.insertRange(Range, &buffer, &count, Range.empty(25));

        try testing.expectEqualSlices(Range, &.{ Range.of(10, 20), Range.of(30, 40) }, buffer[0..count]);
        try Impl.insertRange(Range, &buffer, &count, Range.of(20, 30));
        try testing.expectEqualSlices(Range, &.{Range.of(10, 40)}, buffer[0..count]);
        try Impl.insertRange(Range, &buffer, &count, Range.of(15, 45));
        try testing.expectEqualSlices(Range, &.{Range.of(10, 45)}, buffer[0..count]);
        Impl.assertCanonical(Range, &buffer, count);
    }

    test "full and invalid mutations leave the canonical ranges unchanged" {
        const Range = core.Range(u8);

        var buffer = [_]Range{Range.of(10, 30)};
        var count: usize = 1;

        try testing.expectError(error.Full, Impl.insertRange(Range, &buffer, &count, Range.of(40, 50)));
        try testing.expectError(error.InvalidRange, Impl.insertRange(Range, &buffer, &count, .{ .start = 8, .end = 7 }));
        try testing.expectError(error.Full, Impl.removeRange(Range, &buffer, &count, Range.of(15, 20)));
        try testing.expectError(error.InvalidRange, Impl.removeRange(Range, &buffer, &count, .{ .start = 8, .end = 7 }));
        try testing.expectEqualSlices(Range, &.{Range.of(10, 30)}, buffer[0..count]);
        Impl.assertCanonical(Range, &buffer, count);
    }

    test "remove deletes shrinks splits and spans canonical ranges" {
        const Range = core.Range(u64);

        var buffer: [5]Range = undefined;
        buffer[0] = Range.of(10, 30);
        var count: usize = 1;

        try Impl.removeRange(Range, &buffer, &count, Range.empty(12));
        try Impl.removeRange(Range, &buffer, &count, Range.of(40, 50));
        try testing.expectEqualSlices(Range, &.{Range.of(10, 30)}, buffer[0..count]);
        try Impl.removeRange(Range, &buffer, &count, Range.of(10, 15));
        try testing.expectEqualSlices(Range, &.{Range.of(15, 30)}, buffer[0..count]);
        try Impl.removeRange(Range, &buffer, &count, Range.of(25, 30));
        try testing.expectEqualSlices(Range, &.{Range.of(15, 25)}, buffer[0..count]);
        try Impl.removeRange(Range, &buffer, &count, Range.of(18, 20));
        try testing.expectEqualSlices(Range, &.{ Range.of(15, 18), Range.of(20, 25) }, buffer[0..count]);

        try Impl.insertRange(Range, &buffer, &count, Range.of(40, 50));
        try Impl.insertRange(Range, &buffer, &count, Range.of(60, 70));
        try Impl.removeRange(Range, &buffer, &count, Range.of(17, 65));

        try testing.expectEqualSlices(Range, &.{ Range.of(15, 17), Range.of(65, 70) }, buffer[0..count]);
        try Impl.removeRange(Range, &buffer, &count, Range.of(15, 17));
        try testing.expectEqualSlices(Range, &.{Range.of(65, 70)}, buffer[0..count]);
        Impl.assertCanonical(Range, &buffer, count);
    }

    test "queries follow half-open endpoints and empty boundary containment" {
        const Range = core.Range(u64);
        const ranges = [_]Range{ Range.of(10, 20), Range.of(30, 40) };

        try testing.expectEqual(ranges[0], Impl.findContainingValue(Range, &ranges, @as(u64, 10)).?);
        try testing.expectEqual(ranges[0], Impl.findContainingValue(Range, &ranges, @as(u64, 19)).?);
        try testing.expectEqual(@as(?Range, null), Impl.findContainingValue(Range, &ranges, @as(u64, 20)));
        try testing.expectEqual(@as(?Range, null), Impl.findContainingValue(Range, &ranges, @as(u64, 25)));
        try testing.expect(Impl.containsRangeInSlice(Range, &ranges, Range.of(12, 18)));
        try testing.expect(!Impl.containsRangeInSlice(Range, &ranges, Range.of(18, 31)));
        try testing.expect(!Impl.containsRangeInSlice(Range, &ranges, Range.of(20, 30)));
        try testing.expect(Impl.containsRangeInSlice(Range, &ranges, Range.empty(10)));
        try testing.expect(Impl.containsRangeInSlice(Range, &ranges, Range.empty(20)));
        try testing.expect(!Impl.containsRangeInSlice(Range, &ranges, Range.empty(25)));
        try testing.expectEqual(@as(?Range, null), Impl.findIntersectingRange(Range, &ranges, Range.of(20, 30)));
        try testing.expectEqual(@as(?Range, null), Impl.findIntersectingRange(Range, &ranges, Range.empty(15)));
        try testing.expectEqual(ranges[1], Impl.findIntersectingRange(Range, &ranges, Range.of(25, 35)).?);
    }

    test "model: canonical ranges match a bitset over a small domain" {
        const Range = core.Range(u8);

        var buffer: [16]Range = undefined;
        var count: usize = 0;
        var model = [_]bool{false} ** 32;

        var prng = std.Random.Xoshiro256.init(0x12345678);
        const random = prng.random();

        var step: usize = 0;
        while (step < 160) : (step += 1) {
            const a = random.uintLessThan(u8, 32);
            const b = random.uintLessThan(u8, 32);
            const start = @min(a, b);
            const end = @max(a, b);
            const range = try Range.init(start, end);

            if (random.boolean()) {
                try Impl.insertRange(Range, &buffer, &count, range);
                for (model[start..end]) |*bit| {
                    bit.* = true;
                }
            } else {
                try Impl.removeRange(Range, &buffer, &count, range);
                for (model[start..end]) |*bit| {
                    bit.* = false;
                }
            }

            Impl.assertCanonical(Range, &buffer, count);

            for (model, 0..) |bit, index| {
                try testing.expectEqual(bit, Impl.findContainingValue(Range, buffer[0..count], @as(u8, @intCast(index))) != null);
            }

            var cursor: usize = 0;
            for (buffer[0..count]) |stored| {
                while (cursor < model.len and !model[cursor]) : (cursor += 1) {}

                const range_start = cursor;

                while (cursor < model.len and model[cursor]) : (cursor += 1) {}

                try testing.expectEqual(@as(u8, @intCast(range_start)), stored.start);
                try testing.expectEqual(@as(u8, @intCast(cursor)), stored.end);
            }

            while (cursor < model.len and !model[cursor]) : (cursor += 1) {}
            try testing.expectEqual(model.len, cursor);
        }
    }

    test "comptime: static ranges merge at compile time" {
        comptime {
            const Set = RangeSet.Static(u8, 4);

            var set = Set.init();
            try set.insert(Set.Range.of(1, 3));
            try set.insert(Set.Range.of(3, 5));

            std.debug.assert(set.len() == 1);
            std.debug.assert(set.contains(4));
            std.debug.assert(!set.contains(5));
        }
    }
};
