//! Buddy allocator contract tests. See `docs/specs/mem/alloc/buddy.md`.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const testing = std.testing;

const BuddyAllocator = stdx.mem.alloc.BuddyAllocator;
const buddy = stdx.algo.alloc.buddy;

// Static factory

test "unit: Static(16, 5) exposes const surface" {
    const T = BuddyAllocator.Static(16, 5);
    try testing.expectEqual(@as(usize, 16), T.unit_capacity_const);
    try testing.expectEqual(@as(u8, 5), T.order_count_const);
    try testing.expectEqual(@as(u8, 4), T.max_order_const);
    try testing.expect(@sizeOf(T) > 0);
    try testing.expect(@sizeOf(T) < @sizeOf([16]u64));
}

test "unit: Static(1, 1) compiles as degenerate one-block allocator" {
    var a = BuddyAllocator.Static(1, 1).init();
    try testing.expectEqual(@as(usize, 1), a.capacity());
    try testing.expectEqual(@as(u8, 1), a.orderCount());
    try testing.expectEqual(@as(u8, 0), a.maxOrder());
    try testing.expect(a.isFreeBlock(.{ .start = 0, .order = 0 }));
    try testing.expectEqual(@as(usize, 0), a.allocatedUnits());
}

test "contract: Block type is stdx.algo.alloc.buddy.Block" {
    comptime std.debug.assert(BuddyAllocator.Static(16, 5).Block == buddy.Block);
    comptime std.debug.assert(BuddyAllocator.Bounded.Block == buddy.Block);
}

// Compile-only rejection cases: `Static(0, 5)`, `Static(16, 0)`,
// `Static(16, 33)`, and `Static(std.math.maxInt(usize), 5)` are guarded by
// `@compileError` in `src/mem/alloc/buddy.zig` and cannot be exercised at runtime
// in Zig. Positive comptime assertions pin the contract for legal parameter
// grids.

// wrap

test "unit: Bounded.wrap succeeds for sufficient words" {
    var words: [16]u64 = @splat(0xdead_beef_dead_beef);
    var a = try BuddyAllocator.Bounded.wrap(&words, 16, 5);
    try testing.expectEqual(@as(usize, 16), a.capacity());
    try testing.expectEqual(@as(u8, 5), a.orderCount());
    try testing.expectEqual(@as(u8, 4), a.maxOrder());
    try testing.expect(a.isValid());
    try testing.expectEqual(@as(usize, 0), a.allocatedUnits());
    // Verify all borrowed words below word_count are zero-or-initial (no leftover
    // 0xdead pattern) — wrap installs the initial decomposition on top of a
    // cleared buffer.
    for (words[0..5]) |w| try testing.expect(w != 0xdead_beef_dead_beef);
}

test "unit: Bounded.wrap rejects invalid parameters without mutation" {
    var words: [16]u64 = @splat(0x1234);
    try testing.expectError(error.InvalidRequest, BuddyAllocator.Bounded.wrap(&words, 0, 5));
    try testing.expectError(error.InvalidRequest, BuddyAllocator.Bounded.wrap(&words, 16, 0));
    try testing.expectError(error.InvalidRequest, BuddyAllocator.Bounded.wrap(&words, 16, 33));
    for (words) |w| try testing.expectEqual(@as(u64, 0x1234), w);

    var tiny: [1]u64 = @splat(0xabcd);
    try testing.expectError(error.InvalidRequest, BuddyAllocator.Bounded.wrap(&tiny, 4096, 8));
    try testing.expectEqual(@as(u64, 0xabcd), tiny[0]);
}

// Initial decomposition

test "unit: Static(1, 1) initial decomposition is one order-0 block" {
    var a = BuddyAllocator.Static(1, 1).init();
    try testing.expect(a.isFreeBlock(.{ .start = 0, .order = 0 }));
}

test "unit: Static(8, 4) initial decomposition places one order-3 block" {
    var a = BuddyAllocator.Static(8, 4).init();
    try testing.expect(a.isFreeBlock(.{ .start = 0, .order = 3 }));
    try testing.expect(!a.isFreeBlock(.{ .start = 0, .order = 0 }));
    try testing.expect(!a.isFreeBlock(.{ .start = 0, .order = 1 }));
    try testing.expect(!a.isFreeBlock(.{ .start = 0, .order = 2 }));
    try testing.expect(!a.isFreeBlock(.{ .start = 4, .order = 2 }));
    try testing.expectEqual(@as(usize, 0), a.allocatedUnits());
    try testing.expectEqual(@as(usize, 8), a.remainingUnits());
}

test "unit: Static(12, 4) initial decomposition is {0..8},{8..12}" {
    var a = BuddyAllocator.Static(12, 4).init();
    try testing.expect(a.isFreeBlock(.{ .start = 0, .order = 3 }));
    try testing.expect(a.isFreeBlock(.{ .start = 8, .order = 2 }));
    try testing.expect(!a.isFreeBlock(.{ .start = 0, .order = 2 }));
    try testing.expect(!a.isFreeBlock(.{ .start = 4, .order = 2 }));
    try testing.expectEqual(@as(usize, 12), a.remainingUnits());
    try testing.expectEqual(@as(usize, 0), a.allocatedUnits());
}

// alloc / free round trip

test "unit: alloc(0) on Static(16, 5) returns {0, 0}" {
    var a = BuddyAllocator.Static(16, 5).init();
    const b = try a.alloc(0);
    try testing.expectEqual(@as(usize, 0), b.start);
    try testing.expectEqual(@as(u8, 0), b.order);
    try testing.expectEqual(@as(usize, 15), a.remainingUnits());
    try testing.expectEqual(@as(usize, 1), a.allocatedUnits());
}

test "unit: alloc(maxOrder) returns the top block" {
    var a = BuddyAllocator.Static(16, 5).init();
    const b = try a.alloc(a.maxOrder());
    try testing.expectEqual(@as(usize, 0), b.start);
    try testing.expectEqual(@as(u8, 4), b.order);
    try testing.expectEqual(@as(usize, 0), a.remainingUnits());
}

test "unit: successive alloc(0) on fully-free allocator return 0,1,2,..." {
    var a = BuddyAllocator.Static(8, 4).init();
    var k: usize = 0;
    while (k < 8) : (k += 1) {
        const b = try a.alloc(0);
        try testing.expectEqual(k, b.start);
        try testing.expectEqual(@as(u8, 0), b.order);
    }
    try testing.expectError(error.OutOfMemory, a.alloc(0));
}

test "contract: alloc(order) returns (1 << order)-aligned start" {
    var a = BuddyAllocator.Static(64, 6).init();
    // Interleave orders to force splits.
    const b0 = try a.alloc(2);
    const b1 = try a.alloc(3);
    const b2 = try a.alloc(1);
    const b3 = try a.alloc(4);
    try testing.expectEqual(@as(usize, 0), b0.start % (@as(usize, 1) << 2));
    try testing.expectEqual(@as(usize, 0), b1.start % (@as(usize, 1) << 3));
    try testing.expectEqual(@as(usize, 0), b2.start % (@as(usize, 1) << 1));
    try testing.expectEqual(@as(usize, 0), b3.start % (@as(usize, 1) << 4));
}

test "unit: alloc-free-alloc round trip returns same block" {
    var a = BuddyAllocator.Static(16, 5).init();
    const first = try a.alloc(2);
    try a.free(first);
    const second = try a.alloc(2);
    try testing.expectEqual(first.start, second.start);
    try testing.expectEqual(first.order, second.order);
}

// Splitting behavior

test "unit: alloc(0) on Static(8, 4) splits down to {0,0} plus buddies" {
    var a = BuddyAllocator.Static(8, 4).init();
    const b = try a.alloc(0);
    try testing.expectEqual(@as(usize, 0), b.start);
    try testing.expectEqual(@as(u8, 0), b.order);
    try testing.expect(a.isFreeBlock(.{ .start = 1, .order = 0 }));
    try testing.expect(a.isFreeBlock(.{ .start = 2, .order = 1 }));
    try testing.expect(a.isFreeBlock(.{ .start = 4, .order = 2 }));
    try testing.expect(!a.isFreeBlock(.{ .start = 0, .order = 3 }));
}

test "unit: post-alloc(0), alloc(0) returns {1,0}" {
    var a = BuddyAllocator.Static(8, 4).init();
    _ = try a.alloc(0);
    const b = try a.alloc(0);
    try testing.expectEqual(@as(usize, 1), b.start);
    try testing.expectEqual(@as(u8, 0), b.order);
}

test "unit: post-alloc(0), alloc(1) returns {2,1}" {
    var a = BuddyAllocator.Static(8, 4).init();
    _ = try a.alloc(0);
    const b = try a.alloc(1);
    try testing.expectEqual(@as(usize, 2), b.start);
    try testing.expectEqual(@as(u8, 1), b.order);
}

test "unit: post-alloc(0), alloc(2) returns {4,2}" {
    var a = BuddyAllocator.Static(8, 4).init();
    _ = try a.alloc(0);
    const b = try a.alloc(2);
    try testing.expectEqual(@as(usize, 4), b.start);
    try testing.expectEqual(@as(u8, 2), b.order);
}

// Eager coalescing

test "unit: free coalesces the {0,0}/{1,0} pair back to {0,1}" {
    var a = BuddyAllocator.Static(8, 4).init();
    const b0 = try a.alloc(0);
    const b1 = try a.alloc(0);
    const b2 = try a.alloc(1);
    const b3 = try a.alloc(2);
    try testing.expectEqual(@as(usize, 8), a.allocatedUnits());

    try a.free(b0);
    try testing.expect(a.isFreeBlock(.{ .start = 0, .order = 0 }));
    try a.free(b1);
    try testing.expect(a.isFreeBlock(.{ .start = 0, .order = 1 }));
    try testing.expect(!a.isFreeBlock(.{ .start = 0, .order = 0 }));
    try testing.expect(!a.isFreeBlock(.{ .start = 1, .order = 0 }));
    try a.free(b2);
    try testing.expect(a.isFreeBlock(.{ .start = 0, .order = 2 }));
    try testing.expect(!a.isFreeBlock(.{ .start = 0, .order = 1 }));
    try testing.expect(!a.isFreeBlock(.{ .start = 2, .order = 1 }));
    try a.free(b3);
    try testing.expect(a.isFreeBlock(.{ .start = 0, .order = 3 }));
    try testing.expectEqual(@as(usize, 0), a.allocatedUnits());
    const top = try a.alloc(3);
    try testing.expectEqual(@as(usize, 0), top.start);
    try testing.expectEqual(@as(u8, 3), top.order);
}

// Non-coalescing

test "unit: free does not coalesce when buddy is allocated" {
    var a = BuddyAllocator.Static(8, 4).init();
    const b0 = try a.alloc(0);
    _ = try a.alloc(0);
    _ = try a.alloc(0);

    try a.free(b0);
    try testing.expect(a.isFreeBlock(.{ .start = 0, .order = 0 }));
    try testing.expect(!a.isFreeBlock(.{ .start = 0, .order = 1 }));
}

// Exhaustion / InvalidOrder / free errors

test "unit: alloc(1) on exhausted Static(4, 3) returns OutOfMemory" {
    var a = BuddyAllocator.Static(4, 3).init();
    _ = try a.alloc(1);
    _ = try a.alloc(1);
    const snapshot = snapshotStatic(&a);
    try testing.expectError(error.OutOfMemory, a.alloc(1));
    try expectSnapshotStatic(&a, snapshot);
    try testing.expectError(error.OutOfMemory, a.alloc(0));
    try expectSnapshotStatic(&a, snapshot);
}

test "unit: alloc(order_count) returns InvalidOrder without mutation" {
    var a = BuddyAllocator.Static(16, 5).init();
    const snapshot = snapshotStatic(&a);
    try testing.expectError(error.InvalidOrder, a.alloc(5));
    try expectSnapshotStatic(&a, snapshot);
}

test "unit: free with order == order_count returns InvalidOrder" {
    var a = BuddyAllocator.Static(16, 5).init();
    const snapshot = snapshotStatic(&a);
    try testing.expectError(error.InvalidOrder, a.free(.{ .start = 0, .order = 5 }));
    try expectSnapshotStatic(&a, snapshot);
}

test "unit: double-free returns NotAllocated in release" {
    if (@import("builtin").mode == .Debug or @import("builtin").mode == .ReleaseSafe) return;
    var a = BuddyAllocator.Static(16, 5).init();
    // Allocate two order-0 blocks then free just the first: its buddy is
    // still allocated so no coalesce happens and the order-0 bit remains
    // set. A second free of that block observes the bit already set.
    const b0 = try a.alloc(0);
    _ = try a.alloc(0);
    try a.free(b0);
    try testing.expectError(error.NotAllocated, a.free(b0));
}

test "unit: free with unaligned start returns InvalidRequest in release" {
    if (@import("builtin").mode == .Debug or @import("builtin").mode == .ReleaseSafe) return;
    var a = BuddyAllocator.Static(16, 5).init();
    try testing.expectError(error.InvalidRequest, a.free(.{ .start = 1, .order = 1 }));
}

test "unit: free with out-of-bounds block returns InvalidRequest" {
    var a = BuddyAllocator.Static(16, 5).init();
    const snapshot = snapshotStatic(&a);
    // Order-2 block starting at 15 extends to 19 > unit_capacity.
    try testing.expectError(error.InvalidRequest, a.free(.{ .start = 16, .order = 2 }));
    try expectSnapshotStatic(&a, snapshot);
}

// reserve

test "unit: reserve(3..5) on Static(8, 4) leaves {0..3} and {5..8} allocable" {
    var a = BuddyAllocator.Static(8, 4).init();
    const Range = @TypeOf(a).Range;
    try a.reserve(try Range.fromBounds(3, 5));

    const first = try a.alloc(0);
    try testing.expectEqual(@as(usize, 0), first.start);
    const second = try a.alloc(0);
    try testing.expectEqual(@as(usize, 1), second.start);
    const third = try a.alloc(0);
    try testing.expectEqual(@as(usize, 2), third.start);
    const fourth = try a.alloc(0);
    try testing.expectEqual(@as(usize, 5), fourth.start);
}

test "unit: reserve out-of-bounds range returns OutOfBounds without mutation" {
    var a = BuddyAllocator.Static(8, 4).init();
    const Range = @TypeOf(a).Range;
    const snapshot = snapshotStatic(&a);
    try testing.expectError(error.OutOfBounds, a.reserve(try Range.fromBounds(0, 9)));
    try expectSnapshotStatic(&a, snapshot);
}

test "unit: reserve on already-allocated span returns AlreadyAllocated" {
    var a = BuddyAllocator.Static(8, 4).init();
    const Range = @TypeOf(a).Range;
    const b0 = try a.alloc(0);
    try testing.expectEqual(@as(usize, 0), b0.start);

    const snapshot = snapshotStatic(&a);
    try testing.expectError(error.AlreadyAllocated, a.reserve(try Range.fromBounds(0, 2)));
    try expectSnapshotStatic(&a, snapshot);

    try a.reserve(try Range.fromBounds(1, 2));
}

test "unit: reserve empty range is a no-op inside capacity" {
    var a = BuddyAllocator.Static(8, 4).init();
    const Range = @TypeOf(a).Range;
    const snapshot = snapshotStatic(&a);
    try a.reserve(Range.empty(5));
    try expectSnapshotStatic(&a, snapshot);
}

test "unit: reserve after alloc/free round trips succeeds on free span" {
    var a = BuddyAllocator.Static(16, 5).init();
    const Range = @TypeOf(a).Range;

    const b0 = try a.alloc(1);
    try a.free(b0);
    const b1 = try a.alloc(2);
    try a.free(b1);

    try a.reserve(try Range.fromBounds(4, 6));
    try testing.expect(!isUnitFree(&a, 4));
    try testing.expect(!isUnitFree(&a, 5));
    try testing.expect(isUnitFree(&a, 3));
    try testing.expect(isUnitFree(&a, 6));
}

// No-mutation-on-error compilation for each error path

test "contract: OutOfMemory leaves state unchanged" {
    var a = BuddyAllocator.Static(4, 3).init();
    _ = try a.alloc(1);
    _ = try a.alloc(1);
    const snapshot = snapshotStatic(&a);
    try testing.expectError(error.OutOfMemory, a.alloc(1));
    try expectSnapshotStatic(&a, snapshot);
}

test "contract: NotAllocated leaves state unchanged" {
    if (@import("builtin").mode == .Debug or @import("builtin").mode == .ReleaseSafe) return;
    var a = BuddyAllocator.Static(16, 5).init();
    const b0 = try a.alloc(0);
    _ = try a.alloc(0);
    try a.free(b0);
    const snapshot = snapshotStatic(&a);
    try testing.expectError(error.NotAllocated, a.free(b0));
    try expectSnapshotStatic(&a, snapshot);
}

test "contract: InvalidRequest on free leaves state unchanged" {
    var a = BuddyAllocator.Static(16, 5).init();
    const snapshot = snapshotStatic(&a);
    try testing.expectError(error.InvalidRequest, a.free(.{ .start = 24, .order = 2 }));
    try expectSnapshotStatic(&a, snapshot);
}

test "unit: fresh Static / Bounded values are valid" {
    var s = BuddyAllocator.Static(16, 5).init();
    try testing.expect(s.isValid());
    s.assertValid();

    var words: [16]u64 = @splat(0);
    var b = try BuddyAllocator.Bounded.wrap(&words, 16, 5);
    try testing.expect(b.isValid());
    b.assertValid();
}

test "unit: assertValid holds after mutation sequences" {
    var a = BuddyAllocator.Static(16, 5).init();
    a.assertValid();
    const b0 = try a.alloc(2);
    a.assertValid();
    const b1 = try a.alloc(0);
    a.assertValid();
    try a.free(b0);
    a.assertValid();
    try a.free(b1);
    a.assertValid();
    const Range = @TypeOf(a).Range;
    try a.reserve(try Range.fromBounds(4, 6));
    a.assertValid();
}

test "unit: mutated bitmap that pairs order-k buddies both free fails isValid" {
    var words: [16]u64 = @splat(0);
    var a = try BuddyAllocator.Bounded.wrap(&words, 8, 4);
    // Manually mark {0,0} and {1,0} both free while max_order block is
    // also free — creates a same-order buddy-pair violation at order 0.
    words[0] |= 0b11;
    try testing.expect(!a.isValid());
}

test "unit: Bounded with insufficient words fails isValid" {
    var words: [1]u64 = @splat(0);
    // Test-only backdoor: construct a Bounded whose words.len is smaller
    // than requiredWordCount, bypassing wrap's guard.
    var a: BuddyAllocator.Bounded = .{
        .words = words[0..],
        .unit_capacity = 4096,
        .order_count = 8,
    };
    try testing.expect(!a.isValid());
}

test "unit: clearRetainingCapacity restores fresh state" {
    var a = BuddyAllocator.Static(16, 5).init();
    const fresh = snapshotStatic(&a);

    _ = try a.alloc(0);
    _ = try a.alloc(3);
    try testing.expect(a.allocatedUnits() > 0);

    a.clearRetainingCapacity();
    try expectSnapshotStatic(&a, fresh);
    try testing.expectEqual(@as(usize, 0), a.allocatedUnits());
}

// Debug-mode traps for `free` with unaligned start and double-free cannot be
// exercised at test runtime in Zig; `std.debug.assert(false)` unconditionally
// aborts the process. Release-mode error-return paths pin the
// `error.InvalidRequest` and `error.NotAllocated` contracts for Release
// builds; the trap behavior is exercised by production panics only.

test "model: buddy matches naive []bool reference under random ops" {
    inline for (.{ 1, 4, 8, 16, 64 }) |cap| {
        inline for (.{ 1, 2, 3, 5 }) |orders| {
            const T = BuddyAllocator.Static(cap, orders);
            try runModel(T, cap, orders, 0xdeadbeef);
        }
    }
}

test "stress: 10K random ops on Static(256, 6) return to fully-free state" {
    const T = BuddyAllocator.Static(256, 6);
    var a: T = .init();

    var prng = std.Random.DefaultPrng.init(0x517cc1b727220a95);
    const rng = prng.random();

    var live = std.ArrayList(T.Block).empty;
    defer live.deinit(std.testing.allocator);

    var op: usize = 0;
    while (op < 10_000) : (op += 1) {
        const roll = rng.uintLessThan(u8, 100);
        if (roll < 55) {
            const order = rng.uintLessThan(u8, 6);
            if (a.alloc(order)) |b| {
                try live.append(std.testing.allocator, b);
            } else |err| {
                try testing.expect(err == error.OutOfMemory);
            }
        } else if (live.items.len > 0) {
            const idx = rng.uintLessThan(usize, live.items.len);
            const b = live.swapRemove(idx);
            try a.free(b);
        }
        a.assertValid();
    }

    // Drain live blocks back.
    while (live.items.len > 0) {
        const b = live.pop().?;
        try a.free(b);
    }
    a.assertValid();
    try testing.expectEqual(@as(usize, 0), a.allocatedUnits());
    try testing.expectEqual(@as(usize, 256), a.remainingUnits());

    // Should equal a freshly-initialised allocator bit-for-bit.
    const fresh: T = .init();
    try testing.expectEqualSlices(u64, fresh.words[0..], a.words[0..]);
}

fn snapshotStatic(a: anytype) [@TypeOf(a.*).word_count]u64 {
    return a.words;
}

fn expectSnapshotStatic(a: anytype, snapshot: [@TypeOf(a.*).word_count]u64) !void {
    try testing.expectEqualSlices(u64, snapshot[0..], a.words[0..]);
}

fn isUnitFree(a: anytype, unit: usize) bool {
    const T = @TypeOf(a.*);
    var k: u8 = 0;
    while (k < T.order_count_const) : (k += 1) {
        const size = @as(usize, 1) << @as(std.math.Log2Int(u64), @intCast(k));
        const aligned_start = (unit / size) * size;
        if (aligned_start + size > T.unit_capacity_const) continue;
        if (a.isFreeBlock(.{ .start = aligned_start, .order = k })) return true;
    }
    return false;
}

// Model reference: naive []bool per unit.

const Reference = struct {
    used: []bool, // used[i] = true when unit i is currently allocated.

    fn init(allocator: std.mem.Allocator, capacity: usize) !Reference {
        const used = try allocator.alloc(bool, capacity);
        @memset(used, false);
        return .{ .used = used };
    }

    fn deinit(self: *Reference, allocator: std.mem.Allocator) void {
        allocator.free(self.used);
    }

    fn allocatedUnits(self: Reference) usize {
        var n: usize = 0;
        for (self.used) |u| n += @intFromBool(u);
        return n;
    }

    /// Naive lowest-index power-of-two-aligned free run of `size` units.
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

    fn isFree(self: Reference, unit: usize) bool {
        return !self.used[unit];
    }

    fn reserve(self: *Reference, start: usize, end: usize) void {
        var i: usize = start;
        while (i < end) : (i += 1) {
            self.used[i] = true;
        }
    }
};

fn runModel(comptime T: type, comptime capacity: usize, comptime order_count: u8, seed: u64) !void {
    var a: T = .init();
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
            // alloc
            const order = rng.uintLessThan(u8, order_count);
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
            // free
            const idx = rng.uintLessThan(usize, live_alloc.items.len);
            const b = live_alloc.swapRemove(idx);
            try a.free(b);
            ref.free(b.start, b.order);
        } else if (capacity >= 2) {
            // reserve
            const start = rng.uintLessThan(usize, capacity);
            const end_off = rng.uintLessThan(usize, @min(capacity - start, 4)) + 1;
            const end = start + end_off;
            const Range = T.Range;
            // Peek reference to know if this range is legal.
            var any_used = false;
            var i: usize = start;
            while (i < end) : (i += 1) {
                if (ref.used[i]) {
                    any_used = true;
                    break;
                }
            }
            if (any_used) {
                const snapshot = a.words;
                try testing.expectError(error.AlreadyAllocated, a.reserve(try Range.fromBounds(start, end)));
                try testing.expectEqualSlices(u64, snapshot[0..], a.words[0..]);
            } else {
                try a.reserve(try Range.fromBounds(start, end));
                ref.reserve(start, end);
            }
        }

        // Cross-check state.
        try testing.expectEqual(ref.allocatedUnits(), a.allocatedUnits());
        a.assertValid();
    }
}
