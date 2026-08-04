//! BitmapAllocator contract tests. See `docs/specs/mem/bitmap-allocator.md`.

const std = @import("std");

const stdx = @import("stdx");

const BitmapAllocator = stdx.mem.BitmapAllocator;

const testing = std.testing;

// ---------------------------------------------------------------------------
// Construction and capacity
// ---------------------------------------------------------------------------

test "unit: Static.init() is empty" {
    var bm = BitmapAllocator.Static(64).init();
    try testing.expectEqual(@as(usize, 64), bm.capacity());
    try testing.expectEqual(@as(usize, 0), bm.allocated());
    try testing.expectEqual(@as(usize, 64), bm.remaining());
    try testing.expect(bm.isEmpty());
    try testing.expect(!bm.isFull());
    bm.assertValid();
}

test "unit: default Static struct literal is empty" {
    var bm: BitmapAllocator.Static(65) = .{};
    try testing.expectEqual(@as(usize, 65), bm.capacity());
    try testing.expect(bm.isEmpty());
    bm.assertValid();
}

test "unit: Static(1) basic invariants" {
    var bm = BitmapAllocator.Static(1).init();
    try testing.expectEqual(@as(usize, 1), bm.capacity());
    try testing.expect(bm.isEmpty());
    const i = try bm.allocOne();
    try testing.expectEqual(@as(usize, 0), i);
    try testing.expect(bm.isFull());
    bm.assertValid();
}

test "unit: Static(64) covers one full word" {
    var bm = BitmapAllocator.Static(64).init();
    try testing.expectEqual(@as(usize, 1), @TypeOf(bm).word_count);
    var k: usize = 0;
    while (k < 64) : (k += 1) {
        const got = try bm.allocOne();
        try testing.expectEqual(k, got);
    }
    try testing.expect(bm.isFull());
    try testing.expectError(error.OutOfMemory, bm.allocOne());
    bm.assertValid();
}

test "unit: Static(65) needs two words and keeps unused bits clear" {
    var bm = BitmapAllocator.Static(65).init();
    try testing.expectEqual(@as(usize, 2), @TypeOf(bm).word_count);
    var k: usize = 0;
    while (k < 65) : (k += 1) _ = try bm.allocOne();
    try testing.expect(bm.isFull());
    // unused high bits of the last word must remain zero.
    try testing.expectEqual(@as(u64, 1), bm.words[1]);
    bm.assertValid();
}

test "unit: Static(129) tail-word semantics" {
    var bm = BitmapAllocator.Static(129).init();
    try testing.expectEqual(@as(usize, 3), @TypeOf(bm).word_count);
    var k: usize = 0;
    while (k < 129) : (k += 1) _ = try bm.allocOne();
    try testing.expect(bm.isFull());
    try testing.expectEqual(@as(u64, 1), bm.words[2]);
    bm.assertValid();
}

test "unit: allocated + remaining == capacity after construction" {
    var s = BitmapAllocator.Static(129).init();
    try testing.expectEqual(s.capacity(), s.allocated() + s.remaining());
    var storage: [3]u64 = .{ 0, 0, 0 };
    var b = try BitmapAllocator.Bounded.wrap(&storage, 129);
    try testing.expectEqual(b.capacity(), b.allocated() + b.remaining());
}

test "unit: Bounded.wrap clears borrowed words" {
    var storage: [4]u64 = .{ 0xFF, 0xAA, 0x55, 0xCC };
    var b = try BitmapAllocator.Bounded.wrap(&storage, 200);
    try testing.expectEqual(@as(usize, 200), b.capacity());
    for (storage) |w| try testing.expectEqual(@as(u64, 0), w);
    try testing.expect(b.isEmpty());
    b.assertValid();
}

test "unit: Bounded.wrap rejects unit_capacity > words.len*word_bits" {
    var storage: [2]u64 = .{ 0xDEADBEEF, 0xCAFEBABE };
    const original = storage;
    try testing.expectError(error.OutOfBounds, BitmapAllocator.Bounded.wrap(&storage, 129));
    // borrowed words are unchanged on rejection.
    try testing.expectEqual(original[0], storage[0]);
    try testing.expectEqual(original[1], storage[1]);
}

test "unit: Bounded with zero-capacity storage" {
    var empty: [0]u64 = .{};
    var b = try BitmapAllocator.Bounded.wrap(&empty, 0);
    try testing.expectEqual(@as(usize, 0), b.capacity());
    try testing.expect(b.isEmpty());
    try testing.expect(b.isFull());
    b.assertValid();
    try testing.expectError(error.OutOfMemory, b.allocOne());
}

test "unit: Bounded with capacity smaller than words.len*word_bits" {
    var storage: [3]u64 = .{ 0, 0, 0 };
    var b = try BitmapAllocator.Bounded.wrap(&storage, 100);
    try testing.expectEqual(@as(usize, 100), b.capacity());
    var k: usize = 0;
    while (k < 100) : (k += 1) _ = try b.allocOne();
    try testing.expect(b.isFull());
    try testing.expectError(error.OutOfMemory, b.allocOne());
    // The third word is borrowed but never used as a unit; assertValid
    // requires it to remain zero.
    try testing.expectEqual(@as(u64, 0), storage[2]);
    b.assertValid();
}

// ---------------------------------------------------------------------------
// Single-unit allocation
// ---------------------------------------------------------------------------

test "unit: allocOne returns lowest free index" {
    var bm = BitmapAllocator.Static(128).init();
    try bm.reserveOne(0);
    try bm.reserveOne(1);
    const got = try bm.allocOne();
    try testing.expectEqual(@as(usize, 2), got);
}

test "unit: repeated allocOne yields ascending indexes" {
    var bm = BitmapAllocator.Static(70).init();
    var k: usize = 0;
    while (k < 70) : (k += 1) {
        const got = try bm.allocOne();
        try testing.expectEqual(k, got);
    }
}

test "unit: allocOne returns OutOfMemory without mutation when full" {
    var bm = BitmapAllocator.Static(3).init();
    _ = try bm.allocOne();
    _ = try bm.allocOne();
    _ = try bm.allocOne();
    const snapshot = bm.words;
    try testing.expectError(error.OutOfMemory, bm.allocOne());
    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
}

test "unit: reserveOne succeeds for a free index" {
    var bm = BitmapAllocator.Static(64).init();
    try bm.reserveOne(7);
    try testing.expect(bm.isAllocated(7));
    try testing.expectEqual(@as(usize, 1), bm.allocated());
}

test "unit: reserveOne rejects out-of-bounds indexes" {
    var bm = BitmapAllocator.Static(64).init();
    try testing.expectError(error.OutOfBounds, bm.reserveOne(64));
    try testing.expectError(error.OutOfBounds, bm.reserveOne(1_000));
    try testing.expectEqual(@as(usize, 0), bm.allocated());
}

test "unit: reserveOne rejects an allocated index without mutation" {
    var bm = BitmapAllocator.Static(64).init();
    try bm.reserveOne(3);
    const snapshot = bm.words;
    try testing.expectError(error.AlreadyAllocated, bm.reserveOne(3));
    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
}

test "unit: freeOne succeeds for an allocated index" {
    var bm = BitmapAllocator.Static(64).init();
    try bm.reserveOne(5);
    try bm.freeOne(5);
    try testing.expect(bm.isFree(5));
    try testing.expectEqual(@as(usize, 0), bm.allocated());
}

test "unit: freeOne rejects out-of-bounds indexes" {
    var bm = BitmapAllocator.Static(64).init();
    try testing.expectError(error.OutOfBounds, bm.freeOne(64));
    try testing.expectError(error.OutOfBounds, bm.freeOne(999));
}

test "unit: freeOne rejects a free index without mutation" {
    var bm = BitmapAllocator.Static(64).init();
    const snapshot = bm.words;
    try testing.expectError(error.NotAllocated, bm.freeOne(2));
    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
}

test "unit: isAllocated and isFree return false for out-of-bounds" {
    var bm = BitmapAllocator.Static(64).init();
    try testing.expect(!bm.isAllocated(64));
    try testing.expect(!bm.isFree(64));
    try testing.expect(!bm.isAllocated(1_000_000));
    try testing.expect(!bm.isFree(1_000_000));
}

// ---------------------------------------------------------------------------
// Range allocation
// ---------------------------------------------------------------------------

test "unit: allocRange(0) returns empty range without mutation" {
    var bm = BitmapAllocator.Static(64).init();
    const snapshot = bm.words;
    const r = try bm.allocRange(0);
    try testing.expect(r.isEmpty());
    try testing.expectEqual(@as(usize, 0), r.start);
    try testing.expectEqual(@as(usize, 0), r.end);
    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
}

test "unit: allocRange(1) matches allocOne" {
    var bm = BitmapAllocator.Static(64).init();
    try bm.reserveOne(0);
    const r = try bm.allocRange(1);
    try testing.expectEqual(@as(usize, 1), r.start);
    try testing.expectEqual(@as(usize, 2), r.end);
}

test "unit: allocRange returns lowest first-fit run" {
    var bm = BitmapAllocator.Static(64).init();
    try bm.reserveOne(2);
    const r = try bm.allocRange(2);
    try testing.expectEqual(@as(usize, 0), r.start);
    try testing.expectEqual(@as(usize, 2), r.end);
    const r2 = try bm.allocRange(3);
    try testing.expectEqual(@as(usize, 3), r2.start);
    try testing.expectEqual(@as(usize, 6), r2.end);
}

test "unit: allocRange can allocate a range ending at capacity" {
    var bm = BitmapAllocator.Static(65).init();
    var k: usize = 0;
    while (k < 60) : (k += 1) try bm.reserveOne(k);
    const r = try bm.allocRange(5);
    try testing.expectEqual(@as(usize, 60), r.start);
    try testing.expectEqual(@as(usize, 65), r.end);
    try testing.expect(bm.isFull());
    bm.assertValid();
}

test "unit: allocRange returns OutOfMemory without mutation when exhausted" {
    var bm = BitmapAllocator.Static(8).init();
    _ = try bm.allocRange(8);
    const snapshot = bm.words;
    try testing.expectError(error.OutOfMemory, bm.allocRange(1));
    try testing.expectError(error.OutOfMemory, bm.allocRange(9));
    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
}

test "unit: allocRange fragmented free space without contiguous run" {
    var bm = BitmapAllocator.Static(16).init();
    // pattern: 0 free, 1 alloc, 2 free, 3 alloc, ... → 8 free total but
    // no contiguous run of 2.
    var k: usize = 0;
    while (k < 16) : (k += 2) try bm.reserveOne(k + 1);
    try testing.expectEqual(@as(usize, 8), bm.remaining());
    const snapshot = bm.words;
    try testing.expectError(error.OutOfMemory, bm.allocRange(2));
    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
}

// ---------------------------------------------------------------------------
// Explicit reserve and free ranges
// ---------------------------------------------------------------------------

const Range = BitmapAllocator.Bounded.Range;

test "unit: reserveRange succeeds on free non-empty range" {
    var bm = BitmapAllocator.Static(64).init();
    try bm.reserveRange(try Range.fromBounds(10, 20));
    try testing.expectEqual(@as(usize, 10), bm.allocated());
    var k: usize = 10;
    while (k < 20) : (k += 1) try testing.expect(bm.isAllocated(k));
    bm.assertValid();
}

test "unit: reserveRange accepts in-bounds empty range as no-op" {
    var bm = BitmapAllocator.Static(64).init();
    try bm.reserveRange(try Range.fromBounds(0, 0));
    try bm.reserveRange(try Range.fromBounds(64, 64));
    try testing.expectEqual(@as(usize, 0), bm.allocated());
    bm.assertValid();
}

test "unit: reserveRange rejects out-of-bounds ranges without mutation" {
    var bm = BitmapAllocator.Static(64).init();
    const snapshot = bm.words;
    try testing.expectError(error.OutOfBounds, bm.reserveRange(try Range.fromBounds(60, 65)));
    try testing.expectError(error.OutOfBounds, bm.reserveRange(try Range.fromBounds(65, 65)));
    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
}

test "unit: reserveRange rejects overlap with allocated without mutation" {
    var bm = BitmapAllocator.Static(64).init();
    try bm.reserveOne(15);
    const snapshot = bm.words;
    try testing.expectError(error.AlreadyAllocated, bm.reserveRange(try Range.fromBounds(10, 20)));
    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
}

test "unit: freeRange succeeds on allocated non-empty range" {
    var bm = BitmapAllocator.Static(64).init();
    try bm.reserveRange(try Range.fromBounds(0, 30));
    try bm.freeRange(try Range.fromBounds(5, 25));
    try testing.expectEqual(@as(usize, 10), bm.allocated());
    var k: usize = 5;
    while (k < 25) : (k += 1) try testing.expect(bm.isFree(k));
    bm.assertValid();
}

test "unit: freeRange accepts in-bounds empty range as no-op" {
    var bm = BitmapAllocator.Static(64).init();
    try bm.reserveOne(3);
    const snapshot = bm.words;
    try bm.freeRange(try Range.fromBounds(0, 0));
    try bm.freeRange(try Range.fromBounds(64, 64));
    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
}

test "unit: freeRange rejects out-of-bounds ranges without mutation" {
    var bm = BitmapAllocator.Static(64).init();
    try bm.reserveRange(try Range.fromBounds(0, 64));
    const snapshot = bm.words;
    try testing.expectError(error.OutOfBounds, bm.freeRange(try Range.fromBounds(60, 65)));
    try testing.expectError(error.OutOfBounds, bm.freeRange(try Range.fromBounds(65, 65)));
    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
}

test "unit: freeRange rejects overlap with free units without mutation" {
    var bm = BitmapAllocator.Static(64).init();
    try bm.reserveRange(try Range.fromBounds(0, 10));
    try bm.reserveRange(try Range.fromBounds(15, 25));
    // gap (10..15) is free — freeRange(0..25) must fail.
    const snapshot = bm.words;
    try testing.expectError(error.NotAllocated, bm.freeRange(try Range.fromBounds(0, 25)));
    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
}

// ---------------------------------------------------------------------------
// Counts, clearing, and invariants
// ---------------------------------------------------------------------------

test "unit: allocated/remaining/isEmpty/isFull cover state spectrum" {
    var bm = BitmapAllocator.Static(129).init();
    try testing.expect(bm.isEmpty());
    try testing.expect(!bm.isFull());
    try bm.reserveRange(try Range.fromBounds(0, 64));
    try testing.expectEqual(@as(usize, 64), bm.allocated());
    try testing.expectEqual(@as(usize, 65), bm.remaining());
    try testing.expect(!bm.isEmpty());
    try testing.expect(!bm.isFull());
    try bm.reserveRange(try Range.fromBounds(64, 129));
    try testing.expect(bm.isFull());
    try testing.expect(!bm.isEmpty());
}

test "unit: clearRetainingCapacity clears all units" {
    var bm = BitmapAllocator.Static(129).init();
    try bm.reserveRange(try Range.fromBounds(0, 129));
    bm.clearRetainingCapacity();
    try testing.expect(bm.isEmpty());
    try testing.expectEqual(@as(usize, 129), bm.capacity());
    bm.assertValid();
}

test "unit: clearRetainingCapacity on Bounded clears every borrowed word" {
    var storage: [3]u64 = .{ 0, 0, 0 };
    var b = try BitmapAllocator.Bounded.wrap(&storage, 130);
    try b.reserveRange(try Range.fromBounds(0, 130));
    b.clearRetainingCapacity();
    try testing.expect(b.isEmpty());
    for (storage) |w| try testing.expectEqual(@as(u64, 0), w);
}

test "unit: assertValid succeeds after every public mutation" {
    var bm = BitmapAllocator.Static(129).init();
    bm.assertValid();
    _ = try bm.allocOne();
    bm.assertValid();
    _ = try bm.allocRange(5);
    bm.assertValid();
    try bm.reserveOne(120);
    bm.assertValid();
    try bm.reserveRange(try Range.fromBounds(64, 80));
    bm.assertValid();
    try bm.freeOne(120);
    bm.assertValid();
    try bm.freeRange(try Range.fromBounds(64, 80));
    bm.assertValid();
    bm.clearRetainingCapacity();
    bm.assertValid();
}

test "unit: unused high bits remain clear after operations" {
    var bm = BitmapAllocator.Static(65).init();
    _ = try bm.allocRange(65);
    try testing.expectEqual(@as(u64, 1), bm.words[1]);
    bm.assertValid();
    try bm.freeRange(try Range.fromBounds(0, 65));
    try testing.expectEqual(@as(u64, 0), bm.words[1]);
    bm.assertValid();
}

test "unit: corrupted unused high bits are detected by isValid" {
    var bm = BitmapAllocator.Static(65).init();
    try testing.expect(bm.isValid());
    // poke an unused high bit in the last word
    bm.words[1] = @as(u64, 1) << 5;
    try testing.expect(!bm.isValid());
}

test "unit: corrupted trailing storage word in Bounded is detected" {
    var storage: [3]u64 = .{ 0, 0, 0 };
    var b = try BitmapAllocator.Bounded.wrap(&storage, 100);
    try testing.expect(b.isValid());
    storage[2] = 1;
    try testing.expect(!b.isValid());
}

// ---------------------------------------------------------------------------
// Model tests
// ---------------------------------------------------------------------------

const model_capacity: usize = 129;

const Model = struct {
    bits: [model_capacity]bool = [_]bool{false} ** model_capacity,

    fn allocated(self: *const Model) usize {
        var n: usize = 0;
        for (self.bits) |b| if (b) {
            n += 1;
        };
        return n;
    }

    fn allocOne(self: *Model) !usize {
        for (self.bits, 0..) |b, i| if (!b) {
            self.bits[i] = true;
            return i;
        };
        return error.OutOfMemory;
    }

    fn allocRange(self: *Model, count: usize) !Range {
        if (count == 0) return Range.empty(0);
        if (count > model_capacity) return error.OutOfMemory;
        var i: usize = 0;
        while (i + count <= model_capacity) : (i += 1) {
            var ok = true;
            var j: usize = 0;
            while (j < count) : (j += 1) {
                if (self.bits[i + j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) {
                var k: usize = 0;
                while (k < count) : (k += 1) self.bits[i + k] = true;
                return try Range.fromBounds(i, i + count);
            }
        }
        return error.OutOfMemory;
    }

    fn reserveOne(self: *Model, index: usize) !void {
        if (index >= model_capacity) return error.OutOfBounds;
        if (self.bits[index]) return error.AlreadyAllocated;
        self.bits[index] = true;
    }

    fn reserveRange(self: *Model, range: Range) !void {
        if (range.isEmpty()) {
            if (range.start > model_capacity) return error.OutOfBounds;
            return;
        }
        if (range.end > model_capacity) return error.OutOfBounds;
        var i = range.start;
        while (i < range.end) : (i += 1) if (self.bits[i]) return error.AlreadyAllocated;
        i = range.start;
        while (i < range.end) : (i += 1) self.bits[i] = true;
    }

    fn freeOne(self: *Model, index: usize) !void {
        if (index >= model_capacity) return error.OutOfBounds;
        if (!self.bits[index]) return error.NotAllocated;
        self.bits[index] = false;
    }

    fn freeRange(self: *Model, range: Range) !void {
        if (range.isEmpty()) {
            if (range.start > model_capacity) return error.OutOfBounds;
            return;
        }
        if (range.end > model_capacity) return error.OutOfBounds;
        var i = range.start;
        while (i < range.end) : (i += 1) if (!self.bits[i]) return error.NotAllocated;
        i = range.start;
        while (i < range.end) : (i += 1) self.bits[i] = false;
    }

    fn clear(self: *Model) void {
        for (&self.bits) |*b| b.* = false;
    }
};

fn snapshotStatic(bm: anytype) [@TypeOf(bm.*).word_count]u64 {
    return bm.words;
}

fn assertParity(comptime BmT: type, bm: *BmT, model: *const Model) !void {
    try testing.expectEqual(model.allocated(), bm.allocated());
    var i: usize = 0;
    while (i < model_capacity) : (i += 1) {
        try testing.expectEqual(model.bits[i], bm.isAllocated(i));
    }
    bm.assertValid();
}

test "model: Static vs bool-array allocator over randomized sequences" {
    var bm = BitmapAllocator.Static(model_capacity).init();
    var model = Model{};

    var rng = std.Random.DefaultPrng.init(0xBADC0FFEE_0DDF00D);
    var random = rng.random();

    var iter: usize = 0;
    while (iter < 4_000) : (iter += 1) {
        const op = random.intRangeAtMost(u8, 0, 6);
        switch (op) {
            0 => {
                const snapshot = snapshotStatic(&bm);
                const got = bm.allocOne();
                const expected = model.allocOne();
                try testing.expectEqual(@as(?usize, if (expected) |x| x else |_| null), if (got) |x| x else |_| null);
                if (got) |_| {} else |err| {
                    try testing.expectEqual(error.OutOfMemory, err);
                    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
                }
            },
            1 => {
                const count = random.intRangeAtMost(usize, 0, 12);
                const snapshot = snapshotStatic(&bm);
                const got = bm.allocRange(count);
                const expected = model.allocRange(count);
                if (got) |r| {
                    const er = try expected;
                    try testing.expectEqual(er.start, r.start);
                    try testing.expectEqual(er.end, r.end);
                } else |err| {
                    try testing.expectError(err, expected);
                    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
                }
            },
            2 => {
                const idx = random.intRangeAtMost(usize, 0, model_capacity + 4);
                const snapshot = snapshotStatic(&bm);
                const got = bm.reserveOne(idx);
                const expected = model.reserveOne(idx);
                if (got) |_| {
                    try expected;
                } else |err| {
                    try testing.expectError(err, expected);
                    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
                }
            },
            3 => {
                const a = random.intRangeAtMost(usize, 0, model_capacity + 4);
                const b = random.intRangeAtMost(usize, a, model_capacity + 4);
                const r = try Range.fromBounds(a, b);
                const snapshot = snapshotStatic(&bm);
                const got = bm.reserveRange(r);
                const expected = model.reserveRange(r);
                if (got) |_| {
                    try expected;
                } else |err| {
                    try testing.expectError(err, expected);
                    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
                }
            },
            4 => {
                const idx = random.intRangeAtMost(usize, 0, model_capacity + 4);
                const snapshot = snapshotStatic(&bm);
                const got = bm.freeOne(idx);
                const expected = model.freeOne(idx);
                if (got) |_| {
                    try expected;
                } else |err| {
                    try testing.expectError(err, expected);
                    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
                }
            },
            5 => {
                const a = random.intRangeAtMost(usize, 0, model_capacity + 4);
                const b = random.intRangeAtMost(usize, a, model_capacity + 4);
                const r = try Range.fromBounds(a, b);
                const snapshot = snapshotStatic(&bm);
                const got = bm.freeRange(r);
                const expected = model.freeRange(r);
                if (got) |_| {
                    try expected;
                } else |err| {
                    try testing.expectError(err, expected);
                    try testing.expectEqualSlices(u64, &snapshot, &bm.words);
                }
            },
            6 => {
                bm.clearRetainingCapacity();
                model.clear();
            },
            else => unreachable,
        }
        try assertParity(@TypeOf(bm), &bm, &model);
    }
}

test "model: Bounded vs bool-array allocator over randomized sequences" {
    var storage: [3]u64 = .{ 0, 0, 0 };
    var bm = try BitmapAllocator.Bounded.wrap(&storage, model_capacity);
    var model = Model{};

    var rng = std.Random.DefaultPrng.init(0xFEED_F00D_D15EA5E);
    var random = rng.random();

    var iter: usize = 0;
    while (iter < 4_000) : (iter += 1) {
        const op = random.intRangeAtMost(u8, 0, 6);
        const snapshot = storage;
        switch (op) {
            0 => {
                const got = bm.allocOne();
                const expected = model.allocOne();
                if (got) |x| {
                    const e = try expected;
                    try testing.expectEqual(e, x);
                } else |err| {
                    try testing.expectError(err, expected);
                    try testing.expectEqualSlices(u64, &snapshot, &storage);
                }
            },
            1 => {
                const count = random.intRangeAtMost(usize, 0, 12);
                const got = bm.allocRange(count);
                const expected = model.allocRange(count);
                if (got) |r| {
                    const er = try expected;
                    try testing.expectEqual(er.start, r.start);
                    try testing.expectEqual(er.end, r.end);
                } else |err| {
                    try testing.expectError(err, expected);
                    try testing.expectEqualSlices(u64, &snapshot, &storage);
                }
            },
            2 => {
                const idx = random.intRangeAtMost(usize, 0, model_capacity + 4);
                const got = bm.reserveOne(idx);
                const expected = model.reserveOne(idx);
                if (got) |_| {
                    try expected;
                } else |err| {
                    try testing.expectError(err, expected);
                    try testing.expectEqualSlices(u64, &snapshot, &storage);
                }
            },
            3 => {
                const a = random.intRangeAtMost(usize, 0, model_capacity + 4);
                const b = random.intRangeAtMost(usize, a, model_capacity + 4);
                const r = try Range.fromBounds(a, b);
                const got = bm.reserveRange(r);
                const expected = model.reserveRange(r);
                if (got) |_| {
                    try expected;
                } else |err| {
                    try testing.expectError(err, expected);
                    try testing.expectEqualSlices(u64, &snapshot, &storage);
                }
            },
            4 => {
                const idx = random.intRangeAtMost(usize, 0, model_capacity + 4);
                const got = bm.freeOne(idx);
                const expected = model.freeOne(idx);
                if (got) |_| {
                    try expected;
                } else |err| {
                    try testing.expectError(err, expected);
                    try testing.expectEqualSlices(u64, &snapshot, &storage);
                }
            },
            5 => {
                const a = random.intRangeAtMost(usize, 0, model_capacity + 4);
                const b = random.intRangeAtMost(usize, a, model_capacity + 4);
                const r = try Range.fromBounds(a, b);
                const got = bm.freeRange(r);
                const expected = model.freeRange(r);
                if (got) |_| {
                    try expected;
                } else |err| {
                    try testing.expectError(err, expected);
                    try testing.expectEqualSlices(u64, &snapshot, &storage);
                }
            },
            6 => {
                bm.clearRetainingCapacity();
                model.clear();
            },
            else => unreachable,
        }
        try testing.expectEqual(model.allocated(), bm.allocated());
        var i: usize = 0;
        while (i < model_capacity) : (i += 1) {
            try testing.expectEqual(model.bits[i], bm.isAllocated(i));
        }
        bm.assertValid();
    }
}
