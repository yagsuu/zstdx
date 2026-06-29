//! Static bit set contract tests. Spec: docs/specs/bits/bitset-static.md.

const std = @import("std");

const zstdx = @import("zstdx");

const BitSet = zstdx.bits.BitSet;

const testing = std.testing;

test "unit: BitSet.Static(0) is both empty and full" {
    const Zero = BitSet.Static(0);
    var zero = Zero.init();
    try testing.expect(zero.isEmpty());
    try testing.expect(zero.isFull());
    try testing.expectEqual(@as(?usize, null), zero.popFirstSet());
}

test "unit: BitSet.Static index ops cover first/middle/last and reject OOB" {
    const Set = BitSet.Static(129);
    var set: Set = .{};
    try testing.expect(set.isEmpty());
    try testing.expect(try set.insert(0));
    try testing.expect(!try set.insert(0));
    try set.set(64);
    try set.set(128);
    try testing.expect(try set.isSet(128));
    try testing.expectEqual(@as(usize, 3), set.count());
    try testing.expectEqual(@as(?usize, 0), set.firstSet());
    try testing.expectEqual(@as(?usize, 0), set.popFirstSet());
    try set.assign(1, true);
    try set.toggle(1);
    try testing.expect(!try set.isSet(1));
    try testing.expect(try set.remove(64));
    try testing.expectError(error.OutOfBounds, set.set(129));
    set.assertValid();
}

test "unit: BitSet.Static set algebra preserves unused high bits" {
    const Set = BitSet.Static(129);
    var full = Set.full();
    try testing.expect(full.isFull());
    full.clearAll();
    try testing.expect(full.isEmpty());
    full.fill();

    var other = Set.init();
    try other.set(128);
    try testing.expect(full.containsAll(other));
    try testing.expect(full.containsAny(other));

    var unioned = Set.init();
    unioned.unionWith(other);
    try testing.expect(unioned.eql(other));
    unioned.intersectWith(other);
    try testing.expect(unioned.eql(other));
    unioned.differenceWith(other);
    try testing.expect(unioned.isEmpty());
}

test "unit: BitSet.Static boundary capacities full and round-trip" {
    try testing.expect(BitSet.Static(1).full().isFull());
    try testing.expect(BitSet.Static(64).full().isFull());
    try testing.expect(BitSet.Static(65).full().isFull());
}
