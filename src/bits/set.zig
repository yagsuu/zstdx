//! inline and borrowed fixed-capacity bit sets.

const std = @import("std");

const debug = @import("core").debug;

const WordType = @import("word.zig").Word;

pub fn Set(comptime T: type) type {
    return struct {
        pub const Word = WordType(T);

        pub fn Static(comptime limit: usize) type {
            if (limit == 0) {
                @compileError("Set.Static requires limit >= 1");
            }

            return struct {
                items: [Word.wordsFor(limit)]Word = @splat(.zero),

                const Self = @This();

                pub fn init() Self {
                    return .{};
                }

                pub fn full() Self {
                    var self: Self = .{};
                    self.setAll();
                    return self;
                }

                pub fn capacity(_: *const Self) usize {
                    return limit;
                }

                pub fn words(self: *const Self) []const Word {
                    return &self.items;
                }

                pub fn clearRetainingCapacity(self: *Self) void {
                    @memset(&self.items, .zero);
                }

                pub fn setAll(self: *Self) void {
                    Impl.setAll(&self.items, limit);
                }

                pub fn isEmpty(self: *const Self) bool {
                    return Impl.isEmpty(&self.items, limit);
                }

                pub fn isFull(self: *const Self) bool {
                    return Impl.isFull(&self.items, limit);
                }

                pub fn count(self: *const Self) usize {
                    return Impl.count(&self.items, limit);
                }

                pub fn isSet(self: *const Self, index: usize) bool {
                    return Impl.isSet(&self.items, limit, index);
                }

                pub fn set(self: *Self, index: usize) error{OutOfBounds}!bool {
                    return Impl.set(&self.items, limit, index);
                }

                pub fn unset(self: *Self, index: usize) error{OutOfBounds}!bool {
                    return Impl.unset(&self.items, limit, index);
                }

                pub fn assign(self: *Self, index: usize, value: bool) error{OutOfBounds}!bool {
                    return Impl.assign(&self.items, limit, index, value);
                }

                pub fn toggle(self: *Self, index: usize) error{OutOfBounds}!bool {
                    return Impl.toggle(&self.items, limit, index);
                }

                pub fn firstSet(self: *const Self) ?usize {
                    return Impl.firstSet(&self.items, limit);
                }

                pub fn firstUnset(self: *const Self) ?usize {
                    return Impl.firstUnset(&self.items, limit);
                }

                pub fn popFirstSet(self: *Self) ?usize {
                    return Impl.popFirstSet(&self.items, limit);
                }

                pub fn eql(self: *const Self, other: *const Self) bool {
                    return Impl.eql(&self.items, &other.items, limit);
                }

                pub fn containsAll(self: *const Self, other: *const Self) bool {
                    return Impl.containsAll(&self.items, &other.items, limit);
                }

                pub fn containsAny(self: *const Self, other: *const Self) bool {
                    return Impl.containsAny(&self.items, &other.items, limit);
                }

                pub fn unionWith(self: *Self, other: *const Self) void {
                    Impl.unionWith(&self.items, &other.items, limit);
                }

                pub fn intersectWith(self: *Self, other: *const Self) void {
                    Impl.intersectWith(&self.items, &other.items, limit);
                }

                pub fn differenceWith(self: *Self, other: *const Self) void {
                    Impl.differenceWith(&self.items, &other.items, limit);
                }

                pub fn assertValid(self: *const Self) void {
                    Impl.assertValid(&self.items, limit);
                }
            };
        }

        pub const Bounded = struct {
            items: []Word,
            limit: usize,

            const Self = @This();

            pub fn wrap(items: []Word, limit: usize) error{OutOfBounds}!Self {
                if (Word.wordsFor(limit) > items.len) {
                    return error.OutOfBounds;
                }
                @memset(items, .zero);
                return .{ .items = items, .limit = limit };
            }

            pub fn capacity(self: *const Self) usize {
                return self.limit;
            }

            pub fn words(self: *const Self) []const Word {
                return self.items[0..Word.wordsFor(self.limit)];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                @memset(self.items, .zero);
            }

            pub fn setAll(self: *Self) void {
                Impl.setAll(self.items, self.limit);
            }

            pub fn isEmpty(self: *const Self) bool {
                return Impl.isEmpty(self.items, self.limit);
            }

            pub fn isFull(self: *const Self) bool {
                return Impl.isFull(self.items, self.limit);
            }

            pub fn count(self: *const Self) usize {
                return Impl.count(self.items, self.limit);
            }

            pub fn isSet(self: *const Self, index: usize) bool {
                return Impl.isSet(self.items, self.limit, index);
            }

            pub fn set(self: *Self, index: usize) error{OutOfBounds}!bool {
                return Impl.set(self.items, self.limit, index);
            }

            pub fn unset(self: *Self, index: usize) error{OutOfBounds}!bool {
                return Impl.unset(self.items, self.limit, index);
            }

            pub fn assign(self: *Self, index: usize, value: bool) error{OutOfBounds}!bool {
                return Impl.assign(self.items, self.limit, index, value);
            }

            pub fn toggle(self: *Self, index: usize) error{OutOfBounds}!bool {
                return Impl.toggle(self.items, self.limit, index);
            }

            pub fn firstSet(self: *const Self) ?usize {
                return Impl.firstSet(self.items, self.limit);
            }

            pub fn firstUnset(self: *const Self) ?usize {
                return Impl.firstUnset(self.items, self.limit);
            }

            pub fn popFirstSet(self: *Self) ?usize {
                return Impl.popFirstSet(self.items, self.limit);
            }

            pub fn eql(self: *const Self, other: *const Self) bool {
                if (debug.checksEnabled()) {
                    std.debug.assert(self.limit == other.limit);
                }
                return Impl.eql(self.items, other.items, self.limit);
            }

            pub fn containsAll(self: *const Self, other: *const Self) bool {
                if (debug.checksEnabled()) {
                    std.debug.assert(self.limit == other.limit);
                }
                return Impl.containsAll(self.items, other.items, self.limit);
            }

            pub fn containsAny(self: *const Self, other: *const Self) bool {
                if (debug.checksEnabled()) {
                    std.debug.assert(self.limit == other.limit);
                }
                return Impl.containsAny(self.items, other.items, self.limit);
            }

            pub fn unionWith(self: *Self, other: *const Self) void {
                if (debug.checksEnabled()) {
                    std.debug.assert(self.limit == other.limit);
                }
                Impl.unionWith(self.items, other.items, self.limit);
            }

            pub fn intersectWith(self: *Self, other: *const Self) void {
                if (debug.checksEnabled()) {
                    std.debug.assert(self.limit == other.limit);
                }
                Impl.intersectWith(self.items, other.items, self.limit);
            }

            pub fn differenceWith(self: *Self, other: *const Self) void {
                if (debug.checksEnabled()) {
                    std.debug.assert(self.limit == other.limit);
                }
                Impl.differenceWith(self.items, other.items, self.limit);
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertValid(self.items, self.limit);
            }
        };

        const Impl = struct {
            fn lastMask(capacity: usize) T {
                if (capacity == 0) {
                    return 0;
                }

                const remainder = capacity % Word.width;
                if (remainder == 0) {
                    return Word.full.raw();
                }

                return (@as(T, 1) << @as(Word.Shift, @intCast(remainder))) - 1;
            }

            fn isEmpty(words: []const Word, capacity: usize) bool {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity);
                }

                for (words[0..Word.wordsFor(capacity)]) |word| {
                    if (word != .zero) {
                        return false;
                    }
                }

                return true;
            }

            fn isFull(words: []const Word, capacity: usize) bool {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity);
                }

                const n = Word.wordsFor(capacity);
                if (n == 0) {
                    return true;
                }

                for (words[0 .. n - 1]) |word| {
                    if (word != Word.full) {
                        return false;
                    }
                }

                return words[n - 1].raw() == lastMask(capacity);
            }

            fn count(words: []const Word, capacity: usize) usize {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity);
                }

                var total: usize = 0;
                for (words[0..Word.wordsFor(capacity)]) |word| {
                    total += @popCount(word.raw());
                }

                return total;
            }

            fn isSet(words: []const Word, capacity: usize, index: usize) bool {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity);
                }

                if (index >= capacity) {
                    return false;
                }

                return words[index / Word.width].isSet(index % Word.width);
            }

            fn set(words: []Word, capacity: usize, index: usize) error{OutOfBounds}!bool {
                if (index >= capacity) {
                    return error.OutOfBounds;
                }

                if (debug.checksEnabled()) {
                    assertValid(words, capacity);
                }

                const word = &words[index / Word.width];
                const bit = index % Word.width;
                const prior = word.isSet(bit);
                word.set(bit);
                return prior;
            }

            fn unset(words: []Word, capacity: usize, index: usize) error{OutOfBounds}!bool {
                if (index >= capacity) {
                    return error.OutOfBounds;
                }

                if (debug.checksEnabled()) {
                    assertValid(words, capacity);
                }

                const word = &words[index / Word.width];
                const bit = index % Word.width;
                const prior = word.isSet(bit);
                word.unset(bit);
                return prior;
            }

            fn assign(words: []Word, capacity: usize, index: usize, value: bool) error{OutOfBounds}!bool {
                if (index >= capacity) {
                    return error.OutOfBounds;
                }

                if (debug.checksEnabled()) {
                    assertValid(words, capacity);
                }

                const word = &words[index / Word.width];
                const bit = index % Word.width;
                const prior = word.isSet(bit);

                if (value) {
                    word.set(bit);
                } else {
                    word.unset(bit);
                }

                return prior;
            }

            fn toggle(words: []Word, capacity: usize, index: usize) error{OutOfBounds}!bool {
                if (index >= capacity) {
                    return error.OutOfBounds;
                }

                if (debug.checksEnabled()) {
                    assertValid(words, capacity);
                }

                const word = &words[index / Word.width];
                const bit = index % Word.width;
                word.toggle(bit);
                return word.isSet(bit);
            }

            fn setAll(words: []Word, capacity: usize) void {
                const n = Word.wordsFor(capacity);
                @memset(words[0..n], Word.full);

                if (n != 0) {
                    words[n - 1] = Word.from(lastMask(capacity));
                }
                @memset(words[n..], .zero);
            }

            fn firstSet(words: []const Word, capacity: usize) ?usize {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity);
                }
                for (words[0..Word.wordsFor(capacity)], 0..) |word, i| {
                    if (word != .zero) {
                        return i * Word.width + @ctz(word.raw());
                    }
                }
                return null;
            }

            fn firstUnset(words: []const Word, capacity: usize) ?usize {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity);
                }

                for (words[0..Word.wordsFor(capacity)], 0..) |word, i| {
                    const mask = switch (i + 1 == Word.wordsFor(capacity)) {
                        true => lastMask(capacity),
                        false => Word.full.raw(),
                    };
                    const available = ~word.raw() & mask;
                    if (available != 0) {
                        return i * Word.width + @ctz(available);
                    }
                }

                return null;
            }

            fn popFirstSet(words: []Word, capacity: usize) ?usize {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity);
                }

                for (words[0..Word.wordsFor(capacity)], 0..) |word, i| {
                    if (word != .zero) {
                        const bit = @ctz(word.raw());
                        words[i].unset(bit);
                        return i * Word.width + bit;
                    }
                }

                return null;
            }

            fn eql(a: []const Word, b: []const Word, capacity: usize) bool {
                if (debug.checksEnabled()) {
                    assertValid(a, capacity);
                    assertValid(b, capacity);
                }
                return std.mem.eql(Word, a[0..Word.wordsFor(capacity)], b[0..Word.wordsFor(capacity)]);
            }

            fn containsAll(a: []const Word, b: []const Word, capacity: usize) bool {
                if (debug.checksEnabled()) {
                    assertValid(a, capacity);
                    assertValid(b, capacity);
                }

                for (a[0..Word.wordsFor(capacity)], b[0..Word.wordsFor(capacity)]) |left, right| {
                    if ((left.raw() & right.raw()) != right.raw()) {
                        return false;
                    }
                }

                return true;
            }

            fn containsAny(a: []const Word, b: []const Word, capacity: usize) bool {
                if (debug.checksEnabled()) {
                    assertValid(a, capacity);
                    assertValid(b, capacity);
                }

                for (a[0..Word.wordsFor(capacity)], b[0..Word.wordsFor(capacity)]) |left, right| {
                    if ((left.raw() & right.raw()) != 0) {
                        return true;
                    }
                }

                return false;
            }

            fn unionWith(a: []Word, b: []const Word, capacity: usize) void {
                if (debug.checksEnabled()) {
                    assertValid(a, capacity);
                    assertValid(b, capacity);
                }

                for (a[0..Word.wordsFor(capacity)], b[0..Word.wordsFor(capacity)]) |*left, right| {
                    left.* = Word.from(left.raw() | right.raw());
                }
            }

            fn intersectWith(a: []Word, b: []const Word, capacity: usize) void {
                if (debug.checksEnabled()) {
                    assertValid(a, capacity);
                    assertValid(b, capacity);
                }

                for (a[0..Word.wordsFor(capacity)], b[0..Word.wordsFor(capacity)]) |*left, right| {
                    left.* = Word.from(left.raw() & right.raw());
                }
            }

            fn differenceWith(a: []Word, b: []const Word, capacity: usize) void {
                if (debug.checksEnabled()) {
                    assertValid(a, capacity);
                    assertValid(b, capacity);
                }

                for (a[0..Word.wordsFor(capacity)], b[0..Word.wordsFor(capacity)]) |*left, right| {
                    left.* = Word.from(left.raw() & ~right.raw());
                }
            }

            fn assertValid(words: []const Word, capacity: usize) void {
                const n = Word.wordsFor(capacity);
                std.debug.assert(n <= words.len);

                if (n != 0) {
                    std.debug.assert((words[n - 1].raw() & ~lastMask(capacity)) == 0);
                }

                for (words[n..]) |word| {
                    std.debug.assert(word == .zero);
                }
            }
        };
    };
}

pub const unit = struct {
    const testing = std.testing;

    test "core mutations preserve neighbors across word boundaries" {
        inline for (.{ u8, u64 }) |T| {
            const I = Set(T).Impl;
            const W = Set(T).Word;

            const width = Set(T).Word.width;
            const targets = [_]usize{ 0, 1, width - 1, width, width + 1, 2 * width - 1, 2 * width, 3 * width };

            var words: [4]W = @splat(.zero);

            for (targets) |index| {
                try testing.expectEqual(false, try I.set(&words, 4 * width, index));
                try testing.expectEqual(true, try I.set(&words, 4 * width, index));

                var i: usize = 0;
                while (i < 4 * width) : (i += 1) {
                    try testing.expectEqual(i == index, I.isSet(&words, 4 * width, i));
                }

                try testing.expectEqual(true, try I.unset(&words, 4 * width, index));
                try testing.expectEqual(false, try I.unset(&words, 4 * width, index));
                try testing.expectEqual([_]W{.zero} ** 4, words);
            }
        }

        const W = Set(u64).Word;
        var words = [_]W{ .zero, .zero };
        const I = Set(u64).Impl;

        _ = try I.set(&words, 128, 127);
        try testing.expectEqual([_]W{ .zero, W.from(@as(u64, 1) << 63) }, words);
        _ = try I.unset(&words, 128, 127);
        try testing.expectEqual([_]W{ .zero, .zero }, words);
    }

    test "core mutations return prior values except toggle" {
        const I = Set(u64).Impl;

        var words = [_]Set(u64).Word{.zero};

        try testing.expectEqual(false, try I.assign(&words, 64, 3, false));
        try testing.expectEqual(false, try I.assign(&words, 64, 3, true));
        try testing.expectEqual(true, try I.assign(&words, 64, 3, true));
        try testing.expectEqual(true, try I.assign(&words, 64, 3, false));
        try testing.expectEqual(true, try I.toggle(&words, 64, 12));
        try testing.expectEqual(false, try I.toggle(&words, 64, 12));
        try testing.expect(!I.isSet(&words, 64, 64));
        try testing.expectError(error.OutOfBounds, I.set(&words, 64, 64));
        try testing.expectError(error.OutOfBounds, I.unset(&words, 64, 64));
        try testing.expectError(error.OutOfBounds, I.assign(&words, 64, 64, true));
        try testing.expectError(error.OutOfBounds, I.toggle(&words, 64, 64));

        I.assertValid(&words, 64);
    }

    test "core scans and algebra preserve partial tails and excess words" {
        const I = Set(u64).Impl;

        var full = [_]Set(u64).Word{ .zero, .zero, .zero, .zero };
        var other = full;
        var unioned = full;

        I.setAll(&full, 129);
        _ = try I.set(&other, 129, 128);

        try testing.expect(I.isFull(&full, 129));
        try testing.expectEqual(@as(usize, 129), I.count(&full, 129));
        try testing.expectEqual(@as(?usize, null), I.firstUnset(&full, 129));
        try testing.expect(I.containsAll(&full, &other, 129));
        try testing.expect(I.containsAny(&full, &other, 129));

        I.unionWith(&unioned, &other, 129);
        try testing.expect(I.eql(&unioned, &other, 129));

        I.intersectWith(&unioned, &other, 129);
        try testing.expect(I.eql(&unioned, &other, 129));
        try testing.expectEqual(@as(?usize, 128), I.firstSet(&unioned, 129));
        try testing.expectEqual(@as(?usize, 0), I.firstUnset(&unioned, 129));
        try testing.expectEqual(@as(?usize, 128), I.popFirstSet(&unioned, 129));
        try testing.expectEqual(@as(?usize, null), I.popFirstSet(&unioned, 129));

        I.unionWith(&unioned, &other, 129);
        I.differenceWith(&unioned, &other, 129);
        try testing.expect(I.isEmpty(&unioned, 129));

        I.assertValid(&unioned, 129);
    }

    test "core masks cover capacity boundaries" {
        inline for (.{ u8, u32, u64 }) |T| {
            const I = Set(T).Impl;
            const W = Set(T).Word;

            try testing.expectEqual(@as(T, 0), I.lastMask(0));

            var capacity_bits: usize = 1;
            while (capacity_bits <= 3 * W.width) : (capacity_bits += 1) {
                const remainder = capacity_bits % W.width;
                const expected = switch (remainder) {
                    0 => W.full.raw(),
                    else => (@as(T, 1) << @as(W.Shift, @intCast(remainder))) - 1,
                };
                try testing.expectEqual(expected, I.lastMask(capacity_bits));
            }
        }

        comptime {
            std.debug.assert(Set(u64).Impl.lastMask(64) == std.math.maxInt(u64));
        }
    }

    test "static storage initializes clears and masks odd-width words" {
        const S = Set(u7).Static(15);
        var set = S.init();

        try testing.expect(set.isEmpty());
        try testing.expectEqual(@as(usize, 15), set.capacity());

        _ = try set.set(0);
        _ = try set.set(7);
        _ = try set.set(14);

        try testing.expectEqual(@as(usize, 3), set.count());
        try testing.expectEqual(@as(?usize, 0), set.popFirstSet());

        set.clearRetainingCapacity();
        try testing.expect(set.isEmpty());

        set = S.full();
        try testing.expect(set.isFull());
        try testing.expectEqualSlices(Set(u7).Word, &.{ .full, .full, .from(1) }, set.words());

        set.assertValid();

        try testing.expect(Set(u64).Static(1).full().isFull());
        try testing.expect(Set(u64).Static(64).full().isFull());
        try testing.expect(Set(u64).Static(65).full().isFull());
    }

    test "borrowed storage retains its slice and clears tail and excess words" {
        const W = Set(u8).Word;
        var words = [_]W{ .full, .full, .full, .full };
        var set = try Set(u8).Bounded.wrap(&words, 9);
        var other_words = [_]W{ .zero, .zero };
        var other = try Set(u8).Bounded.wrap(&other_words, 9);

        try testing.expectEqual(@as(usize, 4), set.items.len);
        try testing.expectEqual(@as(usize, 9), set.capacity());
        try testing.expectEqual([_]W{ .zero, .zero, .zero, .zero }, words);

        set.setAll();

        try testing.expectEqualSlices(W, &.{ .full, .from(1) }, set.words());
        try testing.expectEqual([_]W{ .full, .from(1), .zero, .zero }, words);

        _ = try other.set(8);
        set.intersectWith(&other);

        try testing.expect(set.eql(&other));
        set.clearRetainingCapacity();

        try testing.expect(set.isEmpty());
        set.assertValid();
    }

    test "zero capacity is empty and full and failed wrapping leaves storage unchanged" {
        const W = Set(u8).Word;
        var words = [_]W{ .full, .full };

        try testing.expectError(error.OutOfBounds, Set(u8).Bounded.wrap(&words, 17));
        try testing.expectEqual([_]W{ .full, .full }, words);

        var zero = try Set(u8).Bounded.wrap(&words, 0);

        try testing.expect(zero.isEmpty());
        try testing.expect(zero.isFull());
        try testing.expectEqual(@as(usize, 0), zero.words().len);
        try testing.expectEqual(@as(usize, 0), zero.count());
        try testing.expectEqual(@as(?usize, null), zero.firstSet());
        try testing.expectEqual(@as(?usize, null), zero.firstUnset());
        try testing.expectEqual(@as(?usize, null), zero.popFirstSet());
        try testing.expect(!zero.isSet(0));
        try testing.expectError(error.OutOfBounds, zero.set(0));

        zero.setAll();

        try testing.expectEqual([_]W{ .zero, .zero }, words);
        zero.assertValid();

        var empty: [0]W = .{};
        const no_storage = try Set(u8).Bounded.wrap(&empty, 0);
        no_storage.assertValid();
    }
};
