//! fixed-unit buddy allocation

const std = @import("std");

const debug = @import("core").debug;
const buddy = @import("algo").alloc.buddy;

const Bitmap = @import("bits").Set(u64);
const Shift = std.math.Log2Int(usize);

pub const BuddyAllocator = struct {
    pub fn Static(comptime count: usize, comptime orders: u8) type {
        comptime Impl.requireShape(count, orders);

        const initial = Impl.initial(count, orders);

        return struct {
            bitmap: Bitmap.Static(Layout.offset(count, orders) * Bitmap.Word.width) = initial,

            pub const bound = count;

            pub const Word = Bitmap.Word;
            pub const Block = buddy.Block;
            pub const Range = @import("core").Range(usize);
            pub const Error = Impl.Error;

            const Self = @This();

            pub fn init() Self {
                return .{};
            }

            pub fn capacity(_: *const Self) usize {
                return count;
            }

            pub fn orderCount(_: *const Self) u8 {
                return orders;
            }

            pub fn maxOrder(_: *const Self) u8 {
                return orders - 1;
            }

            pub fn allocated(self: *const Self) usize {
                return count - self.remaining();
            }

            pub fn remaining(self: *const Self) usize {
                return Impl.remaining(&self.bitmap, count, orders);
            }

            pub fn hasFreeBlock(self: *const Self, block: Block) bool {
                return Impl.hasFreeBlock(&self.bitmap, count, orders, block);
            }

            pub fn alloc(self: *Self, order: u8) Error!Block {
                return Impl.alloc(&self.bitmap, count, orders, order);
            }

            pub fn free(self: *Self, block: Block) Error!void {
                return Impl.free(&self.bitmap, count, orders, block);
            }

            pub fn reserve(self: *Self, range: Range) Error!void {
                return Impl.reserve(&self.bitmap, count, orders, range);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.bitmap = initial;
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(&self.bitmap, count, orders);
            }
        };
    }

    pub const Bounded = struct {
        bitmap: Bitmap.Bounded,
        bound: usize,
        orders: u8,

        const Self = @This();
        pub const Word = Bitmap.Word;
        pub const Block = buddy.Block;
        pub const Range = @import("core").Range(usize);
        pub const Error = Impl.Error;

        /// items must outlive the allocator; invalid arguments leave them unchanged
        pub fn wrap(items: []Word, count: usize, orders: u8) Error!Self {
            if (count == 0 or orders == 0 or orders > 32) {
                return error.InvalidRequest;
            }
            if (count > std.math.shr(usize, std.math.maxInt(usize), orders - 1)) {
                return error.InvalidRequest;
            }
            const words = Layout.offset(count, orders);
            if (items.len < words) {
                return error.InvalidRequest;
            }
            const bits = std.math.mul(usize, words, Word.width) catch return error.InvalidRequest;
            var bitmap = Bitmap.Bounded.wrap(items, bits) catch return error.InvalidRequest;
            Impl.initialize(&bitmap, count, orders);
            return .{ .bitmap = bitmap, .bound = count, .orders = orders };
        }

        pub fn capacity(self: *const Self) usize {
            return self.bound;
        }

        pub fn orderCount(self: *const Self) u8 {
            return self.orders;
        }

        pub fn maxOrder(self: *const Self) u8 {
            return self.orders - 1;
        }

        pub fn allocated(self: *const Self) usize {
            return self.bound - self.remaining();
        }

        pub fn remaining(self: *const Self) usize {
            return Impl.remaining(&self.bitmap, self.bound, self.orders);
        }

        pub fn hasFreeBlock(self: *const Self, block: Block) bool {
            return Impl.hasFreeBlock(&self.bitmap, self.bound, self.orders, block);
        }

        pub fn alloc(self: *Self, order: u8) Error!Block {
            return Impl.alloc(&self.bitmap, self.bound, self.orders, order);
        }

        pub fn free(self: *Self, block: Block) Error!void {
            return Impl.free(&self.bitmap, self.bound, self.orders, block);
        }

        pub fn reserve(self: *Self, range: Range) Error!void {
            return Impl.reserve(&self.bitmap, self.bound, self.orders, range);
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.bitmap.clearRetainingCapacity();
            Impl.initialize(&self.bitmap, self.bound, self.orders);
        }

        pub fn isValid(self: *const Self) bool {
            return Impl.isValid(&self.bitmap, self.bound, self.orders);
        }
    };
};

const Layout = struct {
    fn slots(capacity: usize, order: u8) usize {
        const size = @as(usize, 1) << @as(Shift, @intCast(order));
        return @divFloor(capacity, size) + @intFromBool(capacity % size != 0);
    }

    fn validSlots(capacity: usize, order: u8) usize {
        const size = @as(usize, 1) << @as(Shift, @intCast(order));
        return @divFloor(capacity, size);
    }

    fn words(capacity: usize, order: u8) usize {
        return Bitmap.Word.wordsFor(slots(capacity, order));
    }

    fn offset(capacity: usize, order: u8) usize {
        var result: usize = 0;
        var k: u8 = 0;
        while (k < order) : (k += 1) {
            result += words(capacity, k);
        }
        return result;
    }
};

const Impl = struct {
    const Word = Bitmap.Word;
    const Block = buddy.Block;
    const Range = @import("core").Range(usize);

    const Error = error{
        OutOfMemory,
        OutOfBounds,
        InvalidOrder,
        InvalidRequest,
        AlreadyAllocated,
        NotAllocated,
    };

    fn requireShape(comptime capacity: usize, comptime orders: u8) void {
        if (orders == 0) {
            @compileError("BuddyAllocator.Static: orders must be at least 1");
        }

        if (orders > 32) {
            @compileError("BuddyAllocator.Static: orders must be at most 32");
        }

        if (capacity == 0) {
            @compileError("BuddyAllocator.Static: capacity must be at least 1");
        }

        if (capacity > (std.math.maxInt(usize) >> (orders - 1))) {
            @compileError(
                "BuddyAllocator.Static: capacity exceeds (maxInt(usize) >> (orders - 1))",
            );
        }
    }

    fn initial(comptime capacity: usize, comptime orders: u8) Bitmap.Static(Layout.offset(capacity, orders) * Word.width) {
        @setEvalBranchQuota(100_000);
        var bitmap = Bitmap.Static(Layout.offset(capacity, orders) * Word.width).init();
        initialize(&bitmap, capacity, orders);
        return bitmap;
    }

    fn assertStorage(bitmap: anytype, capacity: usize, orders: u8) void {
        if (debug.checksEnabled()) {
            std.debug.assert(orders > 0 and orders <= 32);
            std.debug.assert(capacity > 0);
            std.debug.assert(capacity <= std.math.shr(usize, std.math.maxInt(usize), orders - 1));
            const required = Layout.offset(capacity, orders);
            std.debug.assert(bitmap.items.len >= required);
            std.debug.assert(bitmap.capacity() == required * Bitmap.Word.width);
            bitmap.assertValid();
        }
    }

    fn isSet(bitmap: anytype, capacity: usize, order: u8, slot: usize) bool {
        const word_index = Layout.offset(capacity, order) + slot / Bitmap.Word.width;
        return bitmap.items[word_index].isSet(slot % Bitmap.Word.width);
    }

    fn set(bitmap: anytype, capacity: usize, order: u8, slot: usize) void {
        const word_index = Layout.offset(capacity, order) + slot / Bitmap.Word.width;
        bitmap.items[word_index].set(slot % Bitmap.Word.width);
    }

    fn unset(bitmap: anytype, capacity: usize, order: u8, slot: usize) void {
        const word_index = Layout.offset(capacity, order) + slot / Bitmap.Word.width;
        bitmap.items[word_index].unset(slot % Bitmap.Word.width);
    }

    fn firstFree(bitmap: anytype, capacity: usize, order: u8) ?usize {
        const words = bitmap.words();
        const off = Layout.offset(capacity, order);
        const wc = Layout.words(capacity, order);

        var wi: usize = 0;
        while (wi < wc) : (wi += 1) {
            const w = words[off + wi].raw();
            if (w != 0) {
                const bit = @ctz(w);
                const slot = wi * Bitmap.Word.width + bit;
                std.debug.assert(slot < Layout.validSlots(capacity, order));
                return slot;
            }
        }

        return null;
    }

    fn initialize(bitmap: anytype, capacity: usize, orders: u8) void {
        if (capacity == 0) {
            return;
        }

        assertStorage(bitmap, capacity, orders);

        var cursor: usize = 0;
        var k: u8 = orders - 1;
        while (cursor < capacity) {
            while (k > 0 and cursor + (@as(usize, 1) << @as(Shift, @intCast(k))) > capacity) {
                k -= 1;
            }

            const size = @as(usize, 1) << @as(Shift, @intCast(k));

            std.debug.assert(cursor + size <= capacity);
            std.debug.assert(cursor % size == 0);

            set(bitmap, capacity, k, cursor >> @as(Shift, @intCast(k)));
            cursor += size;
        }
    }

    fn remaining(bitmap: anytype, capacity: usize, orders: u8) usize {
        const words = bitmap.words();

        var total: usize = 0;
        var k: u8 = 0;
        while (k < orders) : (k += 1) {
            const off = Layout.offset(capacity, k);
            const wc = Layout.words(capacity, k);

            var pop: usize = 0;
            for (words[off..][0..wc]) |w| {
                pop += @popCount(w.raw());
            }

            const size = @as(usize, 1) << @as(Shift, @intCast(k));
            total += pop * size;
        }

        return total;
    }

    fn hasFreeBlock(
        bitmap: anytype,
        capacity: usize,
        orders: u8,
        block: Block,
    ) bool {
        if (block.order >= orders) {
            return false;
        }

        const size = @as(usize, 1) << @as(Shift, @intCast(block.order));
        if (block.start % size != 0) {
            return false;
        }

        const end = std.math.add(usize, block.start, size) catch return false;
        if (end > capacity) {
            return false;
        }

        assertStorage(bitmap, capacity, orders);
        return isSet(bitmap, capacity, block.order, block.start >> @as(Shift, @intCast(block.order)));
    }

    fn alloc(
        bitmap: anytype,
        capacity: usize,
        orders: u8,
        order: u8,
    ) Error!Block {
        if (order >= orders) {
            return error.InvalidOrder;
        }

        assertStorage(bitmap, capacity, orders);

        // select the lowest-start free block; break same-start ties by order.
        var best_start: usize = std.math.maxInt(usize);
        var best_order: u8 = 0;
        var found = false;

        var k: u8 = order;
        while (k < orders) : (k += 1) {
            const slot = firstFree(bitmap, capacity, k) orelse continue;
            const start = slot << @as(Shift, @intCast(k));
            const beats_start = start < best_start;
            const beats_order = start == best_start and k < best_order;
            const should_replace = !found or beats_start or beats_order;

            if (should_replace) {
                best_start = start;
                best_order = k;
                found = true;
            }
        }

        if (!found) {
            return error.OutOfMemory;
        }

        const source_slot = best_start >> @as(Shift, @intCast(best_order));
        unset(bitmap, capacity, best_order, source_slot);

        var current: Block = .{ .start = best_start, .order = best_order };
        while (current.order > order) {
            std.debug.assert(current.order > 0);
            const pair = current.split() catch unreachable;

            const right = pair[1];
            set(
                bitmap,
                capacity,
                right.order,
                right.start >> @as(Shift, @intCast(right.order)),
            );

            current = pair[0];
        }

        if (debug.checksEnabled()) {
            const slot = current.start >> @as(Shift, @intCast(current.order));
            std.debug.assert(!isSet(bitmap, capacity, current.order, slot));
        }

        return current;
    }

    fn free(
        bitmap: anytype,
        capacity: usize,
        orders: u8,
        block: Block,
    ) Error!void {
        if (block.order >= orders) {
            return error.InvalidOrder;
        }

        const size = @as(usize, 1) << @as(Shift, @intCast(block.order));
        const aligned = block.start % size == 0;

        if (debug.checksEnabled()) {
            std.debug.assert(aligned);
        }

        if (!aligned) {
            return error.InvalidRequest;
        }

        const end = std.math.add(usize, block.start, size) catch return error.InvalidRequest;
        if (end > capacity) {
            return error.InvalidRequest;
        }

        assertStorage(bitmap, capacity, orders);

        const slot = block.start >> @as(Shift, @intCast(block.order));
        if (isSet(bitmap, capacity, block.order, slot)) {
            if (debug.checksEnabled()) {
                std.debug.assert(false);
            }
            return error.NotAllocated;
        }

        var current = block;
        while (current.order + 1 < orders) {
            const sibling = current.buddy() catch break;
            const sibling_size = @as(usize, 1) << @as(Shift, @intCast(sibling.order));
            const sibling_end = std.math.add(usize, sibling.start, sibling_size) catch break;

            if (sibling_end > capacity) {
                break;
            }

            const sibling_slot = sibling.start >> @as(Shift, @intCast(sibling.order));
            if (!isSet(bitmap, capacity, sibling.order, sibling_slot)) {
                break;
            }

            unset(bitmap, capacity, sibling.order, sibling_slot);
            current = current.parent() catch break;
        }

        set(
            bitmap,
            capacity,
            current.order,
            current.start >> @as(Shift, @intCast(current.order)),
        );

        if (debug.checksEnabled()) {
            std.debug.assert(!hasFreeBuddies(bitmap, capacity, orders));
        }
    }

    fn reserve(
        bitmap: anytype,
        capacity: usize,
        orders: u8,
        range: Range,
    ) Error!void {
        if (!range.isValid()) {
            return error.InvalidRequest;
        }

        if (range.isEmpty()) {
            if (range.start > capacity) {
                return error.OutOfBounds;
            }
            return;
        }

        if (range.end > capacity) {
            return error.OutOfBounds;
        }

        assertStorage(bitmap, capacity, orders);

        var probe: usize = range.start;
        while (probe < range.end) : (probe += 1) {
            if (containingOrder(bitmap, capacity, orders, probe) == null) {
                return error.AlreadyAllocated;
            }
        }

        var u: usize = range.start;
        while (u < range.end) : (u += 1) {
            const k = containingOrder(bitmap, capacity, orders, u).?;
            const size_k = @as(usize, 1) << @as(Shift, @intCast(k));
            const block_start = @divFloor(u, size_k) * size_k;

            unset(bitmap, capacity, k, block_start >> @as(Shift, @intCast(k)));

            var current: Block = .{ .start = block_start, .order = k };
            while (current.order > 0) {
                std.debug.assert(current.order > 0);

                const pair = current.split() catch unreachable;
                const left = pair[0];
                const right = pair[1];
                const left_end = left.start + (@as(usize, 1) << @as(Shift, @intCast(left.order)));

                if (u < left_end) {
                    set(
                        bitmap,
                        capacity,
                        right.order,
                        right.start >> @as(Shift, @intCast(right.order)),
                    );
                    current = left;
                } else {
                    set(
                        bitmap,
                        capacity,
                        left.order,
                        left.start >> @as(Shift, @intCast(left.order)),
                    );
                    current = right;
                }
            }

            std.debug.assert(current.order == 0);
            std.debug.assert(current.start == u);
        }
    }

    fn containingOrder(
        bitmap: anytype,
        capacity: usize,
        orders: u8,
        index: usize,
    ) ?u8 {
        var k: u8 = 0;
        while (k < orders) : (k += 1) {
            const size_k = @as(usize, 1) << @as(Shift, @intCast(k));
            const slot = @divFloor(index, size_k);

            if (slot >= Layout.validSlots(capacity, k)) {
                return null;
            }

            if (isSet(bitmap, capacity, k, slot)) {
                return k;
            }
        }
        return null;
    }

    fn hasFreeBuddies(bitmap: anytype, capacity: usize, orders: u8) bool {
        if (orders == 0) {
            return false;
        }

        var k: u8 = 0;
        while (k + 1 < orders) : (k += 1) {
            const valid = Layout.validSlots(capacity, k);

            var pair: usize = 0;
            while (pair * 2 + 1 < valid) : (pair += 1) {
                const left = pair * 2;
                const right = left + 1;

                if (isSet(bitmap, capacity, k, left) and
                    isSet(bitmap, capacity, k, right))
                {
                    return true;
                }
            }
        }

        return false;
    }

    fn hasUnusedBits(words: []const Word, capacity: usize, orders: u8) bool {
        var k: u8 = 0;
        while (k < orders) : (k += 1) {
            const valid = Layout.validSlots(capacity, k);
            const off = Layout.offset(capacity, k);
            const wc = Layout.words(capacity, k);

            var wi: usize = 0;
            while (wi < wc) : (wi += 1) {
                const base = wi * Bitmap.Word.width;
                const w = words[off + wi].raw();

                if (base >= valid) {
                    if (w != 0) {
                        return true;
                    }
                    continue;
                }

                const in_word = valid - base;
                if (in_word >= Bitmap.Word.width) {
                    continue;
                }

                const high_mask = ~((@as(Word.Int, 1) << @as(Bitmap.Word.Shift, @intCast(in_word))) - 1);
                if ((w & high_mask) != 0) {
                    return true;
                }
            }
        }
        return false;
    }

    fn isValid(bitmap: anytype, capacity: usize, orders: u8) bool {
        if (capacity == 0 or orders == 0 or orders > 32) {
            return false;
        }

        if (capacity > std.math.shr(usize, std.math.maxInt(usize), orders - 1)) {
            return false;
        }

        const count = Layout.offset(capacity, orders);
        if (bitmap.items.len < count) {
            return false;
        }

        const bits = std.math.mul(usize, count, Word.width) catch return false;
        if (bitmap.capacity() != bits) {
            return false;
        }

        const words = bitmap.items[0..];
        if (hasUnusedBits(words, capacity, orders)) {
            return false;
        }

        for (words[count..]) |word| {
            if (word.raw() != 0) {
                return false;
            }
        }

        if (hasFreeBuddies(bitmap, capacity, orders)) {
            return false;
        }

        const free_units = remaining(bitmap, capacity, orders);
        if (free_units > capacity) {
            return false;
        }

        return true;
    }
};

pub const unit = struct {
    const testing = std.testing;

    const Word = Bitmap.Word;
    const Block = buddy.Block;
    const Range = @import("core").Range(usize);

    test "splitting chooses the lowest index and free eagerly coalesces" {
        var bitmap = Impl.initial(8, 4);
        const first = try Impl.alloc(&bitmap, 8, 4, 0);
        const second = try Impl.alloc(&bitmap, 8, 4, 0);
        const middle = try Impl.alloc(&bitmap, 8, 4, 1);
        const last = try Impl.alloc(&bitmap, 8, 4, 2);

        try testing.expectEqual(Block{ .start = 0, .order = 0 }, first);
        try testing.expectEqual(Block{ .start = 1, .order = 0 }, second);
        try testing.expectEqual(Block{ .start = 2, .order = 1 }, middle);
        try testing.expectEqual(Block{ .start = 4, .order = 2 }, last);
        try testing.expectError(error.OutOfMemory, Impl.alloc(&bitmap, 8, 4, 0));

        try Impl.free(&bitmap, 8, 4, first);
        try testing.expect(Impl.hasFreeBlock(&bitmap, 8, 4, first));

        try Impl.free(&bitmap, 8, 4, second);
        try testing.expect(Impl.hasFreeBlock(&bitmap, 8, 4, .{ .start = 0, .order = 1 }));

        try Impl.free(&bitmap, 8, 4, middle);
        try Impl.free(&bitmap, 8, 4, last);
        try testing.expectEqualSlices(Word, Impl.initial(8, 4).words(), bitmap.words());
        try testing.expect(Impl.isValid(&bitmap, 8, 4));
    }

    test "irregular decomposition and reservation errors preserve state" {
        var bitmap = Impl.initial(13, 4);

        try testing.expect(Impl.hasFreeBlock(&bitmap, 13, 4, .{ .start = 0, .order = 3 }));
        try testing.expect(Impl.hasFreeBlock(&bitmap, 13, 4, .{ .start = 8, .order = 2 }));
        try testing.expect(Impl.hasFreeBlock(&bitmap, 13, 4, .{ .start = 12, .order = 0 }));

        try Impl.reserve(&bitmap, 13, 4, try Range.init(3, 7));
        const snapshot = bitmap.items;

        try testing.expectError(error.AlreadyAllocated, Impl.reserve(&bitmap, 13, 4, try Range.init(1, 5)));
        try testing.expectError(error.OutOfBounds, Impl.reserve(&bitmap, 13, 4, try Range.init(12, 14)));
        try testing.expectError(error.InvalidRequest, Impl.reserve(&bitmap, 13, 4, .{ .start = 5, .end = 4 }));
        try testing.expectError(error.InvalidOrder, Impl.alloc(&bitmap, 13, 4, 4));
        try testing.expectError(error.InvalidRequest, Impl.free(&bitmap, 13, 4, .{ .start = 14, .order = 1 }));

        try Impl.reserve(&bitmap, 13, 4, try Range.init(13, 13));
        try testing.expectEqualSlices(Word, &snapshot, bitmap.words());
        try testing.expectEqual(@as(usize, 9), Impl.remaining(&bitmap, 13, 4));
        try testing.expect(Impl.isValid(&bitmap, 13, 4));
    }

    test "validation rejects shape storage padding and uncoalesced buddies" {
        var bitmap = Impl.initial(16, 5);

        try testing.expect(!Impl.isValid(&bitmap, 0, 5));
        try testing.expect(!Impl.isValid(&bitmap, 16, 0));
        try testing.expect(!Impl.isValid(&bitmap, 16, 33));
        try testing.expect(!Impl.isValid(&bitmap, std.math.maxInt(usize), 5));
        try testing.expect(!Impl.isValid(&bitmap, 4096, 8));

        _ = try bitmap.set(16);
        try testing.expect(!Impl.isValid(&bitmap, 16, 5));

        bitmap = Impl.initial(16, 5);
        Impl.set(&bitmap, 16, 0, 0);
        Impl.set(&bitmap, 16, 0, 1);
        try testing.expect(!Impl.isValid(&bitmap, 16, 5));

        var irregular = Impl.initial(13, 4);
        Impl.set(&irregular, 13, 2, 3);
        try testing.expect(!Impl.isValid(&irregular, 13, 4));
    }

    test "static and borrowed clear restore storage and wrap validates before mutation" {
        var fixed = BuddyAllocator.Static(13, 4).init();
        var words: [8]Word = @splat(Word.from(0x1234));
        const untouched = words;

        inline for (.{ .{ 0, 4 }, .{ 13, 0 }, .{ 13, 33 }, .{ std.math.maxInt(usize), 5 } }) |shape| {
            try testing.expectError(error.InvalidRequest, BuddyAllocator.Bounded.wrap(&words, shape[0], shape[1]));
            try testing.expectEqualSlices(Word, &untouched, &words);
        }

        try testing.expectError(error.InvalidRequest, BuddyAllocator.Bounded.wrap(words[0..1], 13, 4));
        try testing.expectEqualSlices(Word, &untouched, &words);

        var borrowed = try BuddyAllocator.Bounded.wrap(&words, 13, 4);
        _ = try fixed.alloc(0);
        try borrowed.reserve(try Range.init(2, 6));
        fixed.clearRetainingCapacity();
        borrowed.clearRetainingCapacity();

        try testing.expectEqualSlices(Word, fixed.bitmap.words(), borrowed.bitmap.words());
        try testing.expectEqual(@as(usize, 13), fixed.remaining());
        try testing.expectEqual(@as(usize, 0), borrowed.allocated());
        try testing.expect(fixed.isValid() and borrowed.isValid());

        words[7].set(0);
        try testing.expect(!borrowed.isValid());

        borrowed.clearRetainingCapacity();
        borrowed.bitmap.limit -= 1;
        try testing.expect(!borrowed.isValid());

        borrowed.bitmap.limit += 1;
        borrowed.bound = 0;
        try testing.expect(!borrowed.isValid());
    }

    test "deterministic reference model covers both storage variants" {
        inline for (.{ 1, 4, 8, 16, 64 }) |capacity| {
            inline for (.{ 1, 2, 3, 5 }) |orders| {
                var fixed = BuddyAllocator.Static(capacity, orders).init();
                try runModel(&fixed, capacity, orders, 0xdeadbeef);

                var words: [Layout.offset(capacity, orders)]Word = undefined;
                var borrowed = try BuddyAllocator.Bounded.wrap(&words, capacity, orders);
                try runModel(&borrowed, capacity, orders, 0xdeadbeef);
            }
        }
    }

    const Reference = struct {
        used: []bool,

        fn init(allocator: std.mem.Allocator, capacity: usize) !Reference {
            const used = try allocator.alloc(bool, capacity);
            @memset(used, false);
            return .{ .used = used };
        }

        fn deinit(self: *Reference, allocator: std.mem.Allocator) void {
            allocator.free(self.used);
        }

        fn allocated(self: Reference) usize {
            var n: usize = 0;
            for (self.used) |u| {
                n += @intFromBool(u);
            }
            return n;
        }

        fn alloc(self: *Reference, order: u8) ?usize {
            const size = @as(usize, 1) << @as(u6, @intCast(order));

            var start: usize = 0;
            while (start + size <= self.used.len) : (start += size) {
                var all_free = true;
                var i: usize = 0;
                while (i < size) : (i += 1) {
                    if (self.used[start + i]) {
                        all_free = false;
                        break;
                    }
                }

                if (all_free) {
                    i = 0;
                    while (i < size) : (i += 1) {
                        self.used[start + i] = true;
                    }
                    return start;
                }
            }

            return null;
        }

        fn free(self: *Reference, start: usize, order: u8) void {
            const size = @as(usize, 1) << @as(u6, @intCast(order));
            var i: usize = 0;
            while (i < size) : (i += 1) {
                self.used[start + i] = false;
            }
        }

        fn reserve(self: *Reference, start: usize, end: usize) void {
            var i: usize = start;
            while (i < end) : (i += 1) {
                self.used[i] = true;
            }
        }
    };

    fn runModel(a: anytype, comptime capacity: usize, comptime orders: u8, seed: u64) !void {
        const T = @TypeOf(a.*);
        var ref = try Reference.init(std.testing.allocator, capacity);
        defer ref.deinit(std.testing.allocator);

        var live_alloc = std.ArrayList(T.Block).empty;
        defer live_alloc.deinit(std.testing.allocator);

        var prng = std.Random.DefaultPrng.init(seed);
        const rng = prng.random();

        var op: usize = 0;
        const op_count: usize = 400;
        while (op < op_count) : (op += 1) {
            const roll = rng.uintLessThan(u8, 100);

            if (roll < 50) {
                const order = rng.uintLessThan(u8, orders);
                const got = a.alloc(order);
                const ref_got = ref.alloc(order);

                if (got) |b| {
                    try testing.expect(ref_got != null);
                    try testing.expectEqual(ref_got.?, b.start);
                    try live_alloc.append(std.testing.allocator, b);
                } else |err| {
                    try testing.expectEqual(@as(anyerror, error.OutOfMemory), err);
                    try testing.expect(ref_got == null);
                }
            } else if (roll < 85 and live_alloc.items.len > 0) {
                const idx = rng.uintLessThan(usize, live_alloc.items.len);
                const b = live_alloc.swapRemove(idx);
                try a.free(b);
                ref.free(b.start, b.order);
            } else if (capacity >= 2) {
                const start = rng.uintLessThan(usize, capacity);
                const end_off = rng.uintLessThan(usize, @min(capacity - start, 4)) + 1;
                const end = start + end_off;

                var any_used = false;
                var i: usize = start;
                while (i < end) : (i += 1) {
                    if (ref.used[i]) {
                        any_used = true;
                        break;
                    }
                }

                if (any_used) {
                    var snapshot: [Layout.offset(capacity, orders)]Word = undefined;
                    @memcpy(&snapshot, a.bitmap.words());
                    try testing.expectError(error.AlreadyAllocated, a.reserve(try Range.init(start, end)));
                    try testing.expectEqualSlices(T.Word, snapshot[0..], a.bitmap.words());
                } else {
                    try a.reserve(try Range.init(start, end));
                    ref.reserve(start, end);
                }
            }

            try testing.expectEqual(ref.allocated(), a.allocated());
            try testing.expect(a.isValid());
        }
    }
};
