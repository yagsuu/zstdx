//! TagAllocator contract tests. Spec: docs/specs/tags/tag-allocator.md.

const std = @import("std");
const stdx = @import("stdx");

const Tag = stdx.tags.Tag;
const TagAllocator = stdx.tags.TagAllocator;

const testing = std.testing;

const NvmeCid = struct {};
const AhciSlot = struct {};
const DomainA = struct {};
const DomainB = struct {};

// ---------------------------------------------------------------- helpers

fn paramType(comptime Fn: type, comptime index: usize) type {
    return @typeInfo(Fn).@"fn".params[index].type.?;
}

/// Bool-array reference allocator used by the model tests.
fn ReferenceAlloc(comptime IntT: type) type {
    return struct {
        used: [256]bool = [_]bool{false} ** 256,
        cap: usize,

        const Self = @This();
        pub const Int = IntT;

        pub fn init(cap: usize) Self {
            return .{ .cap = cap };
        }

        pub fn allocated(self: *const Self) usize {
            var n: usize = 0;
            for (self.used[0..self.cap]) |b| if (b) {
                n += 1;
            };
            return n;
        }

        pub fn isFull(self: *const Self) bool {
            return self.allocated() == self.cap;
        }

        pub fn allocOne(self: *Self) ?usize {
            var i: usize = 0;
            while (i < self.cap) : (i += 1) {
                if (!self.used[i]) {
                    self.used[i] = true;
                    return i;
                }
            }
            return null;
        }

        const RErr = error{ OutOfBounds, AlreadyAllocated, NotAllocated };

        pub fn reserveOne(self: *Self, idx: usize) RErr!void {
            if (idx >= self.cap) return error.OutOfBounds;
            if (self.used[idx]) return error.AlreadyAllocated;
            self.used[idx] = true;
        }

        pub fn freeOne(self: *Self, idx: usize) RErr!void {
            if (idx >= self.cap) return error.OutOfBounds;
            if (!self.used[idx]) return error.NotAllocated;
            self.used[idx] = false;
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            for (&self.used) |*b| b.* = false;
        }
    };
}

// ---------------------------------------------------------------- Tag identity / compile-time

test "compile: TagAllocator.Static yields distinct types per domain and capacity" {
    comptime {
        std.debug.assert(TagAllocator.Static(DomainA, u16, 64) !=
            TagAllocator.Static(DomainB, u16, 64));
        std.debug.assert(TagAllocator.Static(DomainA, u16, 64) !=
            TagAllocator.Static(DomainA, u16, 128));
        std.debug.assert(TagAllocator.Bounded(DomainA, u16) !=
            TagAllocator.Bounded(DomainB, u16));
    }
    try testing.expect(TagAllocator.Static(DomainA, u16, 64) !=
        TagAllocator.Static(DomainB, u16, 64));
}

test "compile: Static(D, u16, N).Tag equals Bounded(D, u16).Tag" {
    comptime {
        const S = TagAllocator.Static(DomainA, u16, 64);
        const B = TagAllocator.Bounded(DomainA, u16);
        std.debug.assert(S.Tag == B.Tag);
        std.debug.assert(S.Tag == Tag(DomainA, u16));
    }
}

test "compile: cross-domain mixing is rejected at the type level" {
    // `reserveOne`/`freeOne`/`isAllocated`/`isFree` accept ONLY the
    // allocator's own Tag type. Verified via the function's parameter
    // type: passing a different-domain Tag would be a compile error.
    const S = TagAllocator.Static(NvmeCid, u16, 256);
    const Other = Tag(AhciSlot, u5);
    comptime {
        const T = paramType(@TypeOf(S.reserveOne), 1);
        std.debug.assert(T == S.Tag);
        std.debug.assert(T != Other);
        std.debug.assert(paramType(@TypeOf(S.freeOne), 1) == S.Tag);
        std.debug.assert(paramType(@TypeOf(S.isAllocated), 1) == S.Tag);
        std.debug.assert(paramType(@TypeOf(S.isFree), 1) == S.Tag);
    }
}

// ---------------------------------------------------------------- Construction & capacity

test "unit: Static.init() is empty and reports configured capacity" {
    const S = TagAllocator.Static(DomainA, u16, 64);
    var a = S.init();
    try testing.expectEqual(@as(usize, 64), a.capacity());
    try testing.expectEqual(@as(usize, 0), a.allocated());
    try testing.expectEqual(@as(usize, 64), a.remaining());
    try testing.expect(a.isEmpty());
    try testing.expect(!a.isFull());
    try testing.expectEqual(a.capacity(), a.allocated() + a.remaining());
    a.assertValid();
}

test "unit: Static default struct literal is empty" {
    const S = TagAllocator.Static(DomainA, u16, 65);
    var a: S = .{};
    try testing.expectEqual(@as(usize, 65), a.capacity());
    try testing.expectEqual(@as(usize, 0), a.allocated());
    try testing.expect(a.isEmpty());
    a.assertValid();
}

test "unit: Static(D, u16, 0) is both empty and full" {
    const S = TagAllocator.Static(DomainA, u16, 0);
    var a = S.init();
    try testing.expectEqual(@as(usize, 0), a.capacity());
    try testing.expect(a.isEmpty());
    try testing.expect(a.isFull());
    try testing.expectError(error.OutOfTags, a.allocOne());
    a.assertValid();
}

test "unit: Static(D, u16, 1) cycles its only tag" {
    const S = TagAllocator.Static(DomainA, u16, 1);
    var a = S.init();
    const t = try a.allocOne();
    try testing.expectEqual(@as(u16, 0), t.raw());
    try testing.expect(a.isFull());
    try testing.expectError(error.OutOfTags, a.allocOne());
    try a.freeOne(t);
    try testing.expect(a.isEmpty());
}

test "unit: Static(D, u16, 64) (single-word) fills and empties" {
    const S = TagAllocator.Static(DomainA, u16, 64);
    var a = S.init();
    var i: u16 = 0;
    while (i < 64) : (i += 1) {
        const t = try a.allocOne();
        try testing.expectEqual(i, t.raw());
    }
    try testing.expect(a.isFull());
    try testing.expectError(error.OutOfTags, a.allocOne());
    a.assertValid();
}

test "unit: Static(D, u16, 65) (two-word) preserves unused high bits" {
    const S = TagAllocator.Static(DomainA, u16, 65);
    var a = S.init();
    var i: u16 = 0;
    while (i < 65) : (i += 1) _ = try a.allocOne();
    try testing.expect(a.isFull());
    try testing.expectError(error.OutOfTags, a.allocOne());
    // Unused high bits of word[1] are zero.
    try testing.expectEqual(@as(u64, 1), a.words[1]);
    a.assertValid();
}

test "unit: Static(D, u16, 129) non-word multiple invariants" {
    const S = TagAllocator.Static(DomainA, u16, 129);
    var a = S.init();
    var i: u16 = 0;
    while (i < 129) : (i += 1) _ = try a.allocOne();
    try testing.expect(a.isFull());
    a.assertValid();
    // High bits of the third word past bit 0 must be zero.
    try testing.expectEqual(@as(u64, 1), a.words[2]);
}

test "unit: Static(D, u5, 32) width-bounded allocator fills" {
    const S = TagAllocator.Static(DomainA, u5, 32);
    var a = S.init();
    var i: u5 = 0;
    while (true) {
        const t = try a.allocOne();
        try testing.expectEqual(i, t.raw());
        if (i == 31) break;
        i += 1;
    }
    try testing.expect(a.isFull());
    try testing.expectError(error.OutOfTags, a.allocOne());
}

test "unit: Bounded.wrap clears borrowed words and reports capacity" {
    const B = TagAllocator.Bounded(DomainA, u16);
    var backing: [4]u64 = .{ 0xdead, 0xbeef, 0xcafe, 0xbabe };
    var a = try B.wrap(&backing, 200);
    try testing.expectEqual(@as(usize, 200), a.capacity());
    try testing.expect(a.isEmpty());
    for (backing) |w| try testing.expectEqual(@as(u64, 0), w);
    a.assertValid();
}

test "unit: Bounded.wrap with zero capacity is empty and full" {
    const B = TagAllocator.Bounded(DomainA, u16);
    var a = try B.wrap(&.{}, 0);
    try testing.expectEqual(@as(usize, 0), a.capacity());
    try testing.expect(a.isEmpty());
    try testing.expect(a.isFull());
    try testing.expectError(error.OutOfTags, a.allocOne());
    a.assertValid();
}

test "unit: Bounded.wrap rejects tag_capacity > words.len*word_bits" {
    const B = TagAllocator.Bounded(DomainA, u16);
    var backing: [2]u64 = .{ 0xdead, 0xbeef };
    const result = B.wrap(&backing, 129);
    try testing.expectError(error.OutOfBounds, result);
    // Rejected wrap leaves borrowed words unchanged.
    try testing.expectEqual(@as(u64, 0xdead), backing[0]);
    try testing.expectEqual(@as(u64, 0xbeef), backing[1]);
}

test "unit: Bounded.wrap rejects tag_capacity > maxInt(Int)+1" {
    const B = TagAllocator.Bounded(DomainA, u8); // max tags = 256
    var backing: [8]u64 = [_]u64{0xaa} ** 8;
    const result = B.wrap(&backing, 257);
    try testing.expectError(error.OutOfBounds, result);
    for (backing) |w| try testing.expectEqual(@as(u64, 0xaa), w);
}

test "unit: Bounded.wrap exactly at maxInt(Int)+1 succeeds" {
    const B = TagAllocator.Bounded(DomainA, u8);
    var backing: [4]u64 = [_]u64{0xff} ** 4;
    var a = try B.wrap(&backing, 256);
    try testing.expectEqual(@as(usize, 256), a.capacity());
    for (backing) |w| try testing.expectEqual(@as(u64, 0), w);
}

// Compile-time rejection: Static(D, u8, 257) is a compile error. We
// cannot run this at runtime; the assertion is encoded in the spec and
// in `requireUnsignedInt` / capacity check inside `allocator.zig`.

// ---------------------------------------------------------------- Allocation

test "unit: allocOne returns ascending tags from an empty allocator" {
    const S = TagAllocator.Static(DomainA, u16, 8);
    var a = S.init();
    var i: u16 = 0;
    while (i < 8) : (i += 1) {
        const t = try a.allocOne();
        try testing.expectEqual(i, t.raw());
    }
}

test "unit: allocOne returns the lowest free tag after partial frees" {
    const S = TagAllocator.Static(DomainA, u16, 8);
    var a = S.init();
    var tags: [8]S.Tag = undefined;
    for (&tags) |*slot| slot.* = try a.allocOne();
    try a.freeOne(tags[3]);
    try a.freeOne(tags[1]);
    try a.freeOne(tags[5]);
    const t1 = try a.allocOne();
    try testing.expectEqual(@as(u16, 1), t1.raw());
    const t2 = try a.allocOne();
    try testing.expectEqual(@as(u16, 3), t2.raw());
    const t3 = try a.allocOne();
    try testing.expectEqual(@as(u16, 5), t3.raw());
}

test "unit: allocOne returns OutOfTags without mutation when full" {
    const S = TagAllocator.Static(DomainA, u16, 4);
    var a = S.init();
    var i: u16 = 0;
    while (i < 4) : (i += 1) _ = try a.allocOne();
    const before_allocated = a.allocated();
    const before_words = a.words;
    try testing.expectError(error.OutOfTags, a.allocOne());
    try testing.expectEqual(before_allocated, a.allocated());
    try testing.expectEqualSlices(u64, &before_words, &a.words);
}

test "unit: allocOne returns a Tag whose raw() is in bounds" {
    const S = TagAllocator.Static(DomainA, u16, 7);
    var a = S.init();
    var i: u16 = 0;
    while (i < 7) : (i += 1) {
        const t = try a.allocOne();
        try testing.expect(t.raw() < 7);
    }
}

test "unit: allocOne return type is the allocator's Tag, not a bare Int" {
    const S = TagAllocator.Static(DomainA, u16, 8);
    var a = S.init();
    const t = try a.allocOne();
    try testing.expect(@TypeOf(t) == S.Tag);
    try testing.expect(@TypeOf(t) == Tag(DomainA, u16));
    try testing.expect(@TypeOf(t) != u16);
}

test "unit: allocOne crosses a word boundary in the right order" {
    const S = TagAllocator.Static(DomainA, u16, 130);
    var a = S.init();
    var i: u16 = 0;
    while (i < 130) : (i += 1) {
        const t = try a.allocOne();
        try testing.expectEqual(i, t.raw());
    }
    try testing.expect(a.isFull());
}

// ---------------------------------------------------------------- Reserve / free

test "unit: reserveOne succeeds for a free in-bounds tag" {
    const S = TagAllocator.Static(DomainA, u16, 16);
    var a = S.init();
    try a.reserveOne(S.Tag.fromInt(5));
    try testing.expect(a.isAllocated(S.Tag.fromInt(5)));
    try testing.expectEqual(@as(usize, 1), a.allocated());
}

test "unit: reserveOne rejects out-of-bounds with OutOfBounds, no mutation" {
    const S = TagAllocator.Static(DomainA, u16, 16);
    var a = S.init();
    const before = a.allocated();
    try testing.expectError(error.OutOfBounds, a.reserveOne(S.Tag.fromInt(16)));
    try testing.expectError(error.OutOfBounds, a.reserveOne(S.Tag.fromInt(1000)));
    try testing.expectEqual(before, a.allocated());
    a.assertValid();
}

test "unit: reserveOne rejects allocated tag with AlreadyAllocated, no mutation" {
    const S = TagAllocator.Static(DomainA, u16, 16);
    var a = S.init();
    try a.reserveOne(S.Tag.fromInt(7));
    const before_alloc = a.allocated();
    const before_words = a.words;
    try testing.expectError(error.AlreadyAllocated, a.reserveOne(S.Tag.fromInt(7)));
    try testing.expectEqual(before_alloc, a.allocated());
    try testing.expectEqualSlices(u64, &before_words, &a.words);
}

test "unit: freeOne succeeds for an allocated tag" {
    const S = TagAllocator.Static(DomainA, u16, 16);
    var a = S.init();
    const t = try a.allocOne();
    try a.freeOne(t);
    try testing.expect(a.isFree(t));
    try testing.expectEqual(@as(usize, 0), a.allocated());
}

test "unit: freeOne rejects out-of-bounds with OutOfBounds, no mutation" {
    const S = TagAllocator.Static(DomainA, u16, 16);
    var a = S.init();
    try testing.expectError(error.OutOfBounds, a.freeOne(S.Tag.fromInt(16)));
    try testing.expectError(error.OutOfBounds, a.freeOne(S.Tag.fromInt(40000)));
    a.assertValid();
}

test "unit: freeOne rejects a free tag with NotAllocated, no mutation" {
    const S = TagAllocator.Static(DomainA, u16, 16);
    var a = S.init();
    const before_alloc = a.allocated();
    const before_words = a.words;
    try testing.expectError(error.NotAllocated, a.freeOne(S.Tag.fromInt(3)));
    try testing.expectEqual(before_alloc, a.allocated());
    try testing.expectEqualSlices(u64, &before_words, &a.words);
}

test "unit: isAllocated and isFree return false for out-of-bounds tags" {
    const S = TagAllocator.Static(DomainA, u16, 16);
    var a = S.init();
    try testing.expect(!a.isAllocated(S.Tag.fromInt(16)));
    try testing.expect(!a.isAllocated(S.Tag.fromInt(40000)));
    try testing.expect(!a.isFree(S.Tag.fromInt(16)));
    try testing.expect(!a.isFree(S.Tag.fromInt(40000)));
}

test "unit: after freeOne(t), allocOne may return t.raw() again" {
    const S = TagAllocator.Static(DomainA, u16, 8);
    var a = S.init();
    const t0 = try a.allocOne();
    const t1 = try a.allocOne();
    _ = t1;
    try a.freeOne(t0);
    const t_reuse = try a.allocOne();
    try testing.expectEqual(t0.raw(), t_reuse.raw());
}

// ---------------------------------------------------------------- Counts / clearing / invariants

test "unit: count queries across empty/partial/full/zero states" {
    {
        const S = TagAllocator.Static(DomainA, u16, 0);
        var a = S.init();
        try testing.expect(a.isEmpty());
        try testing.expect(a.isFull());
        try testing.expectEqual(@as(usize, 0), a.allocated());
        try testing.expectEqual(@as(usize, 0), a.remaining());
    }
    {
        const S = TagAllocator.Static(DomainA, u16, 8);
        var a = S.init();
        try testing.expect(a.isEmpty());
        try testing.expect(!a.isFull());
        _ = try a.allocOne();
        _ = try a.allocOne();
        try testing.expect(!a.isEmpty());
        try testing.expect(!a.isFull());
        try testing.expectEqual(@as(usize, 2), a.allocated());
        try testing.expectEqual(@as(usize, 6), a.remaining());
        var i: u16 = 0;
        while (i < 6) : (i += 1) _ = try a.allocOne();
        try testing.expect(a.isFull());
        try testing.expectEqual(@as(usize, 8), a.allocated());
        try testing.expectEqual(@as(usize, 0), a.remaining());
    }
}

test "unit: clearRetainingCapacity clears all tags and preserves capacity" {
    const S = TagAllocator.Static(DomainA, u16, 130);
    var a = S.init();
    var i: u16 = 0;
    while (i < 50) : (i += 1) _ = try a.allocOne();
    try testing.expectEqual(@as(usize, 50), a.allocated());
    a.clearRetainingCapacity();
    try testing.expectEqual(@as(usize, 0), a.allocated());
    try testing.expectEqual(@as(usize, 130), a.capacity());
    try testing.expectEqual(@as(usize, 130), a.remaining());
    a.assertValid();
    // Subsequent alloc starts at 0.
    const t = try a.allocOne();
    try testing.expectEqual(@as(u16, 0), t.raw());
}

test "unit: assertValid succeeds after every public mutation" {
    const S = TagAllocator.Static(DomainA, u16, 129);
    var a = S.init();
    a.assertValid();
    const t0 = try a.allocOne();
    a.assertValid();
    try a.reserveOne(S.Tag.fromInt(100));
    a.assertValid();
    try a.freeOne(t0);
    a.assertValid();
    a.clearRetainingCapacity();
    a.assertValid();
}

test "unit: unused high bits remain clear across operations" {
    const S = TagAllocator.Static(DomainA, u16, 65);
    var a = S.init();
    var i: u16 = 0;
    while (i < 65) : (i += 1) _ = try a.allocOne();
    // Only bit 0 of word[1] is logical; high 63 bits must be zero.
    try testing.expectEqual(@as(u64, 1), a.words[1]);
    try a.freeOne(S.Tag.fromInt(64));
    try testing.expectEqual(@as(u64, 0), a.words[1]);
    a.clearRetainingCapacity();
    try testing.expectEqual(@as(u64, 0), a.words[1]);
    try a.reserveOne(S.Tag.fromInt(64));
    try testing.expectEqual(@as(u64, 1), a.words[1]);
}

test "unit: assertValid detects corrupted unused high bits" {
    const S = TagAllocator.Static(DomainA, u16, 65);
    var a = S.init();
    try testing.expect(a.isValid());
    a.words[1] = 0x8000_0000_0000_0000; // unused high bit set
    try testing.expect(!a.isValid());
}

test "unit: isValid detects allocated_count drift" {
    const S = TagAllocator.Static(DomainA, u16, 8);
    var a = S.init();
    _ = try a.allocOne();
    try testing.expect(a.isValid());
    a.allocated_count = 7; // popcount disagrees
    try testing.expect(!a.isValid());
}

test "unit: Bounded round-trips and validates across operations" {
    const B = TagAllocator.Bounded(DomainA, u16);
    var backing: [3]u64 = .{ 0, 0, 0 };
    var a = try B.wrap(&backing, 150);
    var i: u16 = 0;
    while (i < 100) : (i += 1) _ = try a.allocOne();
    try testing.expectEqual(@as(usize, 100), a.allocated());
    a.assertValid();
    try a.freeOne(B.Tag.fromInt(0));
    a.assertValid();
    a.clearRetainingCapacity();
    try testing.expect(a.isEmpty());
    a.assertValid();
}

test "unit: Bounded unused high bits and trailing words stay clear" {
    const B = TagAllocator.Bounded(DomainA, u16);
    var backing: [4]u64 = .{ 0, 0, 0, 0 };
    var a = try B.wrap(&backing, 65);
    var i: u16 = 0;
    while (i < 65) : (i += 1) _ = try a.allocOne();
    try testing.expectEqual(@as(u64, 1), backing[1]);
    try testing.expectEqual(@as(u64, 0), backing[2]);
    try testing.expectEqual(@as(u64, 0), backing[3]);
}

// ---------------------------------------------------------------- Model tests

fn modelRun(
    comptime AllocT: type,
    a: *AllocT,
    ref: *ReferenceAlloc(AllocT.Int),
    seed: u64,
    iterations: usize,
) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    var rng = prng.random();
    var iter: usize = 0;
    while (iter < iterations) : (iter += 1) {
        const op = rng.intRangeAtMost(u8, 0, 9);
        switch (op) {
            0, 1, 2, 3 => {
                // allocOne
                const ref_full = ref.isFull();
                const before_allocated = a.allocated();
                const before_ref_count = ref.allocated();
                if (a.allocOne()) |t| {
                    try testing.expect(!ref_full);
                    const ref_idx = ref.allocOne().?;
                    try testing.expectEqual(@as(usize, ref_idx), @as(usize, t.raw()));
                } else |err| {
                    try testing.expectEqual(error.OutOfTags, err);
                    try testing.expect(ref_full);
                    try testing.expectEqual(before_allocated, a.allocated());
                    try testing.expectEqual(before_ref_count, ref.allocated());
                }
            },
            4, 5 => {
                // reserveOne at a random index (may be out of bounds, in
                // use, or free).
                const idx = rng.intRangeAtMost(usize, 0, ref.cap + 4);
                const before_allocated = a.allocated();
                const before_ref_count = ref.allocated();
                const ref_result = ref.reserveOne(idx);
                if (idx > std.math.maxInt(AllocT.Int)) {
                    // ref returns OutOfBounds but we can't construct a
                    // Tag with this raw value; skip — both views agree
                    // on rejection.
                    if (ref_result) |_| {
                        // ref didn't reject? cap must have allowed it,
                        // but `idx > maxInt(Int)` should never reach
                        // here since cap <= maxInt(Int)+1.
                        unreachable;
                    } else |_| {}
                    continue;
                }
                const tag = AllocT.Tag.fromInt(@intCast(idx));
                const a_result = a.reserveOne(tag);
                if (ref_result) |_| {
                    try a_result; // both succeed
                } else |ref_err| {
                    try testing.expectError(ref_err, a_result);
                    try testing.expectEqual(before_allocated, a.allocated());
                    try testing.expectEqual(before_ref_count, ref.allocated());
                }
            },
            6, 7 => {
                // freeOne at a random index
                const idx = rng.intRangeAtMost(usize, 0, ref.cap + 4);
                const before_allocated = a.allocated();
                const before_ref_count = ref.allocated();
                const ref_result = ref.freeOne(idx);
                if (idx > std.math.maxInt(AllocT.Int)) {
                    if (ref_result) |_| unreachable else |_| {}
                    continue;
                }
                const tag = AllocT.Tag.fromInt(@intCast(idx));
                const a_result = a.freeOne(tag);
                if (ref_result) |_| {
                    try a_result;
                } else |ref_err| {
                    try testing.expectError(ref_err, a_result);
                    try testing.expectEqual(before_allocated, a.allocated());
                    try testing.expectEqual(before_ref_count, ref.allocated());
                }
            },
            8 => {
                // clearRetainingCapacity
                a.clearRetainingCapacity();
                ref.clearRetainingCapacity();
            },
            9 => {
                // snapshot equivalence
                try testing.expectEqual(ref.allocated(), a.allocated());
                var k: usize = 0;
                while (k < ref.cap) : (k += 1) {
                    const tag = AllocT.Tag.fromInt(@intCast(k));
                    try testing.expectEqual(ref.used[k], a.isAllocated(tag));
                    try testing.expectEqual(!ref.used[k], a.isFree(tag));
                }
            },
            else => unreachable,
        }
        a.assertValid();
        try testing.expectEqual(ref.allocated(), a.allocated());
    }
    // Final whole-set equivalence
    var k: usize = 0;
    while (k < ref.cap) : (k += 1) {
        const tag = AllocT.Tag.fromInt(@intCast(k));
        try testing.expectEqual(ref.used[k], a.isAllocated(tag));
    }
}

test "model: Static(D, u16, 70) matches bool-array reference" {
    const S = TagAllocator.Static(DomainA, u16, 70);
    var a = S.init();
    var ref = ReferenceAlloc(u16).init(70);
    try modelRun(S, &a, &ref, 0xC0FFEE, 4000);
}

test "model: Static(D, u8, 200) matches bool-array reference" {
    const S = TagAllocator.Static(DomainB, u8, 200);
    var a = S.init();
    var ref = ReferenceAlloc(u8).init(200);
    try modelRun(S, &a, &ref, 0xDEADBEEF, 4000);
}

test "model: Bounded(D, u16) over 129 tags matches bool-array reference" {
    const B = TagAllocator.Bounded(DomainA, u16);
    var backing: [4]u64 = .{ 0, 0, 0, 0 };
    var a = try B.wrap(&backing, 129);
    var ref = ReferenceAlloc(u16).init(129);
    try modelRun(B, &a, &ref, 0xBADC0DE, 4000);
}

test "model: Static(D, u5, 32) width-bounded matches reference" {
    const S = TagAllocator.Static(DomainA, u5, 32);
    var a = S.init();
    var ref = ReferenceAlloc(u5).init(32);
    try modelRun(S, &a, &ref, 0xABCDEF, 2000);
}
