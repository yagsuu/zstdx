//! Inline and borrowed fixed-capacity bit sets.

const std = @import("std");

const debug = @import("core").debug;

const WordType = @import("word.zig").Word;

pub fn Set(comptime T: type) type {
    return struct {
        pub const Word = WordType(T);

        pub fn Static(comptime capacity_bits: usize) type {
            if (capacity_bits == 0) {
                @compileError("Set.Static requires capacity_bits >= 1");
            }

            return struct {
                items: [Impl.wordCount(capacity_bits)]T = @splat(0),

                const Self = @This();

                pub fn init() Self {
                    return .{};
                }

                pub fn full() Self {
                    var self: Self = .{};
                    self.setAll();
                    return self;
                }

                pub fn capacity(self: *const Self) usize {
                    _ = self;
                    return capacity_bits;
                }

                pub fn words(self: *const Self) []const T {
                    return &self.items;
                }

                pub fn clearRetainingCapacity(self: *Self) void {
                    @memset(&self.items, 0);
                }

                pub fn setAll(self: *Self) void {
                    Impl.setAll(&self.items, capacity_bits);
                }

                pub fn isEmpty(self: *const Self) bool {
                    return Impl.isEmpty(&self.items, capacity_bits);
                }

                pub fn isFull(self: *const Self) bool {
                    return Impl.isFull(&self.items, capacity_bits);
                }

                pub fn count(self: *const Self) usize {
                    return Impl.count(&self.items, capacity_bits);
                }

                pub fn isSet(self: *const Self, index: usize) bool {
                    return Impl.isSet(&self.items, capacity_bits, index);
                }

                pub fn set(self: *Self, index: usize) error{OutOfBounds}!bool {
                    return Impl.set(&self.items, capacity_bits, index);
                }

                pub fn unset(self: *Self, index: usize) error{OutOfBounds}!bool {
                    return Impl.unset(&self.items, capacity_bits, index);
                }

                pub fn assign(self: *Self, index: usize, value: bool) error{OutOfBounds}!bool {
                    return Impl.assign(&self.items, capacity_bits, index, value);
                }

                pub fn toggle(self: *Self, index: usize) error{OutOfBounds}!bool {
                    return Impl.toggle(&self.items, capacity_bits, index);
                }

                pub fn firstSet(self: *const Self) ?usize {
                    return Impl.firstSet(&self.items, capacity_bits);
                }

                pub fn firstUnset(self: *const Self) ?usize {
                    return Impl.firstUnset(&self.items, capacity_bits);
                }

                pub fn popFirstSet(self: *Self) ?usize {
                    return Impl.popFirstSet(&self.items, capacity_bits);
                }

                pub fn eql(self: *const Self, other: *const Self) bool {
                    return Impl.eql(&self.items, &other.items, capacity_bits);
                }

                pub fn containsAll(self: *const Self, other: *const Self) bool {
                    return Impl.containsAll(&self.items, &other.items, capacity_bits);
                }

                pub fn containsAny(self: *const Self, other: *const Self) bool {
                    return Impl.containsAny(&self.items, &other.items, capacity_bits);
                }

                pub fn unionWith(self: *Self, other: *const Self) void {
                    Impl.unionWith(&self.items, &other.items, capacity_bits);
                }

                pub fn intersectWith(self: *Self, other: *const Self) void {
                    Impl.intersectWith(&self.items, &other.items, capacity_bits);
                }

                pub fn differenceWith(self: *Self, other: *const Self) void {
                    Impl.differenceWith(&self.items, &other.items, capacity_bits);
                }

                pub fn assertValid(self: *const Self) void {
                    Impl.assertValid(&self.items, capacity_bits);
                }
            };
        }

        pub const Bounded = struct {
            items: []T,
            limit: usize,

            const Self = @This();

            pub fn wrap(items: []T, capacity_bits: usize) error{OutOfBounds}!Self {
                if (Impl.wordCount(capacity_bits) > items.len) {
                    return error.OutOfBounds;
                }
                @memset(items, 0);
                return .{ .items = items, .limit = capacity_bits };
            }

            pub fn capacity(self: *const Self) usize {
                return self.limit;
            }

            pub fn words(self: *const Self) []const T {
                return self.items[0..Impl.wordCount(self.limit)];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                @memset(self.items, 0);
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
            fn wordCount(capacity_bits: usize) usize {
                return capacity_bits / Word.width + @intFromBool(capacity_bits % Word.width != 0);
            }

            fn lastMask(capacity_bits: usize) T {
                if (capacity_bits == 0) {
                    return 0;
                }

                const remainder = capacity_bits % Word.width;
                if (remainder == 0) {
                    return Word.full;
                }

                return (@as(T, 1) << @as(Word.Shift, @intCast(remainder))) - 1;
            }

            fn isEmpty(words: []const T, capacity_bits: usize) bool {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity_bits);
                }

                for (words[0..wordCount(capacity_bits)]) |word| {
                    if (word != 0) {
                        return false;
                    }
                }

                return true;
            }

            fn isFull(words: []const T, capacity_bits: usize) bool {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity_bits);
                }

                const n = wordCount(capacity_bits);
                if (n == 0) {
                    return true;
                }

                for (words[0 .. n - 1]) |word| {
                    if (word != Word.full) {
                        return false;
                    }
                }

                return words[n - 1] == lastMask(capacity_bits);
            }

            fn count(words: []const T, capacity_bits: usize) usize {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity_bits);
                }

                var total: usize = 0;
                for (words[0..wordCount(capacity_bits)]) |word| {
                    total += @popCount(word);
                }

                return total;
            }

            fn isSet(words: []const T, capacity_bits: usize, index: usize) bool {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity_bits);
                }

                if (index >= capacity_bits) {
                    return false;
                }

                return Word.isSet(words[index / Word.width], index % Word.width);
            }

            fn set(words: []T, capacity_bits: usize, index: usize) error{OutOfBounds}!bool {
                if (index >= capacity_bits) {
                    return error.OutOfBounds;
                }

                if (debug.checksEnabled()) {
                    assertValid(words, capacity_bits);
                }

                const word = &words[index / Word.width];
                const mask = Word.maskOf(index % Word.width);
                const prior = (word.* & mask) != 0;
                word.* |= mask;
                return prior;
            }

            fn unset(words: []T, capacity_bits: usize, index: usize) error{OutOfBounds}!bool {
                if (index >= capacity_bits) {
                    return error.OutOfBounds;
                }

                if (debug.checksEnabled()) {
                    assertValid(words, capacity_bits);
                }

                const word = &words[index / Word.width];
                const mask = Word.maskOf(index % Word.width);
                const prior = (word.* & mask) != 0;
                word.* &= ~mask;
                return prior;
            }

            fn assign(words: []T, capacity_bits: usize, index: usize, value: bool) error{OutOfBounds}!bool {
                if (index >= capacity_bits) {
                    return error.OutOfBounds;
                }

                if (debug.checksEnabled()) {
                    assertValid(words, capacity_bits);
                }

                const word = &words[index / Word.width];
                const mask = Word.maskOf(index % Word.width);
                const prior = (word.* & mask) != 0;

                if (value) {
                    word.* |= mask;
                } else {
                    word.* &= ~mask;
                }

                return prior;
            }

            fn toggle(words: []T, capacity_bits: usize, index: usize) error{OutOfBounds}!bool {
                if (index >= capacity_bits) {
                    return error.OutOfBounds;
                }

                if (debug.checksEnabled()) {
                    assertValid(words, capacity_bits);
                }

                const word = &words[index / Word.width];
                const mask = Word.maskOf(index % Word.width);
                word.* ^= mask;
                return (word.* & mask) != 0;
            }

            fn setAll(words: []T, capacity_bits: usize) void {
                const n = wordCount(capacity_bits);
                @memset(words[0..n], Word.full);

                if (n != 0) {
                    words[n - 1] &= lastMask(capacity_bits);
                }
                @memset(words[n..], 0);
            }

            fn firstSet(words: []const T, capacity_bits: usize) ?usize {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity_bits);
                }
                for (words[0..wordCount(capacity_bits)], 0..) |word, i| {
                    if (word != 0) {
                        return i * Word.width + @ctz(word);
                    }
                }
                return null;
            }

            fn firstUnset(words: []const T, capacity_bits: usize) ?usize {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity_bits);
                }

                for (words[0..wordCount(capacity_bits)], 0..) |word, i| {
                    const available = ~word & (if (i + 1 == wordCount(capacity_bits)) lastMask(capacity_bits) else Word.full);
                    if (available != 0) {
                        return i * Word.width + @ctz(available);
                    }
                }

                return null;
            }

            fn popFirstSet(words: []T, capacity_bits: usize) ?usize {
                if (debug.checksEnabled()) {
                    assertValid(words, capacity_bits);
                }

                for (words[0..wordCount(capacity_bits)], 0..) |word, i| {
                    if (word != 0) {
                        Word.clear(&words[i], @ctz(word));
                        return i * Word.width + @ctz(word);
                    }
                }

                return null;
            }

            fn eql(a: []const T, b: []const T, capacity_bits: usize) bool {
                if (debug.checksEnabled()) {
                    assertValid(a, capacity_bits);
                    assertValid(b, capacity_bits);
                }
                return std.mem.eql(T, a[0..wordCount(capacity_bits)], b[0..wordCount(capacity_bits)]);
            }

            fn containsAll(a: []const T, b: []const T, capacity_bits: usize) bool {
                if (debug.checksEnabled()) {
                    assertValid(a, capacity_bits);
                    assertValid(b, capacity_bits);
                }

                for (a[0..wordCount(capacity_bits)], b[0..wordCount(capacity_bits)]) |left, right| {
                    if ((left & right) != right) {
                        return false;
                    }
                }

                return true;
            }

            fn containsAny(a: []const T, b: []const T, capacity_bits: usize) bool {
                if (debug.checksEnabled()) {
                    assertValid(a, capacity_bits);
                    assertValid(b, capacity_bits);
                }

                for (a[0..wordCount(capacity_bits)], b[0..wordCount(capacity_bits)]) |left, right| {
                    if ((left & right) != 0) {
                        return true;
                    }
                }

                return false;
            }

            fn unionWith(a: []T, b: []const T, capacity_bits: usize) void {
                if (debug.checksEnabled()) {
                    assertValid(a, capacity_bits);
                    assertValid(b, capacity_bits);
                }

                for (a[0..wordCount(capacity_bits)], b[0..wordCount(capacity_bits)]) |*left, right| {
                    left.* |= right;
                }
            }

            fn intersectWith(a: []T, b: []const T, capacity_bits: usize) void {
                if (debug.checksEnabled()) {
                    assertValid(a, capacity_bits);
                    assertValid(b, capacity_bits);
                }

                for (a[0..wordCount(capacity_bits)], b[0..wordCount(capacity_bits)]) |*left, right| {
                    left.* &= right;
                }
            }

            fn differenceWith(a: []T, b: []const T, capacity_bits: usize) void {
                if (debug.checksEnabled()) {
                    assertValid(a, capacity_bits);
                    assertValid(b, capacity_bits);
                }

                for (a[0..wordCount(capacity_bits)], b[0..wordCount(capacity_bits)]) |*left, right| {
                    left.* &= ~right;
                }
            }

            fn assertValid(words: []const T, capacity_bits: usize) void {
                const n = wordCount(capacity_bits);
                std.debug.assert(n <= words.len);

                if (n != 0) {
                    std.debug.assert((words[n - 1] & ~lastMask(capacity_bits)) == 0);
                }

                for (words[n..]) |word| {
                    std.debug.assert(word == 0);
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

            const width = Set(T).Word.width;
            const targets = [_]usize{ 0, 1, width - 1, width, width + 1, 2 * width - 1, 2 * width, 3 * width };

            var words: [4]T = @splat(0);

            for (targets) |index| {
                try testing.expectEqual(false, try I.set(&words, 4 * width, index));
                try testing.expectEqual(true, try I.set(&words, 4 * width, index));

                var i: usize = 0;
                while (i < 4 * width) : (i += 1) {
                    try testing.expectEqual(i == index, I.isSet(&words, 4 * width, i));
                }

                try testing.expectEqual(true, try I.unset(&words, 4 * width, index));
                try testing.expectEqual(false, try I.unset(&words, 4 * width, index));
                try testing.expectEqual([_]T{0} ** 4, words);
            }
        }

        var words = [_]u64{ 0, 0 };
        const I = Set(u64).Impl;

        _ = try I.set(&words, 128, 127);
        try testing.expectEqual([_]u64{ 0, @as(u64, 1) << 63 }, words);
        _ = try I.unset(&words, 128, 127);
        try testing.expectEqual([_]u64{ 0, 0 }, words);
    }

    test "core mutations return prior values except toggle" {
        const I = Set(u64).Impl;

        var words = [_]u64{0};

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

        var full = [_]u64{ 0, 0, 0, 0 };
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

    test "core counts and masks cover capacity boundaries" {
        inline for (.{ u8, u32, u64 }) |T| {
            const I = Set(T).Impl;
            const W = Set(T).Word;

            const capacities = [_]usize{ 0, 1, W.width, W.width + 1, 3 * W.width - 1, 3 * W.width, 3 * W.width + 1 };
            const counts = [_]usize{ 0, 1, 1, 2, 3, 3, 4 };

            for (capacities, counts) |capacity_bits, expected| {
                try testing.expectEqual(expected, I.wordCount(capacity_bits));
            }

            try testing.expectEqual(@as(T, 0), I.lastMask(0));

            var capacity_bits: usize = 1;
            while (capacity_bits <= 3 * W.width) : (capacity_bits += 1) {
                const remainder = capacity_bits % W.width;
                const expected = if (remainder == 0) W.full else (@as(T, 1) << @as(W.Shift, @intCast(remainder))) - 1;
                try testing.expectEqual(expected, I.lastMask(capacity_bits));
            }
        }
        comptime {
            std.debug.assert(Set(u64).Impl.wordCount(65) == 2);
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
        try testing.expectEqualSlices(u7, &.{ 127, 127, 1 }, set.words());

        set.assertValid();

        try testing.expect(Set(u64).Static(1).full().isFull());
        try testing.expect(Set(u64).Static(64).full().isFull());
        try testing.expect(Set(u64).Static(65).full().isFull());
    }

    test "borrowed storage retains its slice and clears tail and excess words" {
        var words = [_]u8{ 255, 255, 255, 255 };
        var set = try Set(u8).Bounded.wrap(&words, 9);
        var other_words = [_]u8{ 0, 0 };
        var other = try Set(u8).Bounded.wrap(&other_words, 9);

        try testing.expectEqual(@as(usize, 4), set.items.len);
        try testing.expectEqual(@as(usize, 9), set.capacity());
        try testing.expectEqual([_]u8{ 0, 0, 0, 0 }, words);

        set.setAll();

        try testing.expectEqualSlices(u8, &.{ 255, 1 }, set.words());
        try testing.expectEqual([_]u8{ 255, 1, 0, 0 }, words);

        _ = try other.set(8);
        set.intersectWith(&other);

        try testing.expect(set.eql(&other));
        set.clearRetainingCapacity();

        try testing.expect(set.isEmpty());
        set.assertValid();
    }

    test "zero capacity is empty and full and failed wrapping leaves storage unchanged" {
        var words = [_]u8{ 255, 255 };

        try testing.expectError(error.OutOfBounds, Set(u8).Bounded.wrap(&words, 17));
        try testing.expectEqual([_]u8{ 255, 255 }, words);

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

        try testing.expectEqual([_]u8{ 0, 0 }, words);
        zero.assertValid();

        var empty: [0]u8 = .{};
        const no_storage = try Set(u8).Bounded.wrap(&empty, 0);
        no_storage.assertValid();
    }
};
