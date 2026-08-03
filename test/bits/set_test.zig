//! Static bit set contract tests. Spec: docs/specs/bits/bitset/static.md.

const std = @import("std");

const stdx = @import("stdx");

const BitSet = stdx.bits.BitSet;

const testing = std.testing;

test "unit: BitSet.Static index ops cover first/middle/last and reject OOB" {
    const Set = BitSet.Static(129);
    var set: Set = .{};
    try testing.expect(set.isEmpty());
    _ = try set.set(0);
    _ = try set.set(64);
    _ = try set.set(128);
    try testing.expect(set.isSet(128));
    try testing.expectEqual(@as(usize, 3), set.count());
    try testing.expectEqual(@as(?usize, 0), set.firstSet());
    try testing.expectEqual(@as(?usize, 0), set.popFirstSet());
    _ = try set.assign(1, true);
    _ = try set.toggle(1);
    try testing.expect(!set.isSet(1));
    _ = try set.unset(64);
    try testing.expect(!set.isSet(64));
    try testing.expect(!set.isSet(Set.bit_capacity));
    try testing.expectError(error.OutOfBounds, set.set(Set.bit_capacity));
    set.assertValid();
}

test "unit: BitSet.Static set/unset return the prior bit value" {
    const Set = BitSet.Static(64);
    var set = Set.init();

    // First set: bit was clear -> prior = false; bit is now set.
    try testing.expectEqual(false, try set.set(7));
    try testing.expect(set.isSet(7));

    // Second set on the same bit: prior = true; bit remains set.
    try testing.expectEqual(true, try set.set(7));
    try testing.expect(set.isSet(7));

    // Unset a set bit: prior = true; bit is now clear.
    try testing.expectEqual(true, try set.unset(7));
    try testing.expect(!set.isSet(7));

    // Unset an already-clear bit: prior = false; bit remains clear.
    try testing.expectEqual(false, try set.unset(7));
    try testing.expect(!set.isSet(7));
}

test "unit: BitSet.Static assign returns prior value across every transition" {
    const Set = BitSet.Static(64);
    var set = Set.init();

    // false -> false
    try testing.expectEqual(false, try set.assign(3, false));
    try testing.expect(!set.isSet(3));

    // false -> true
    try testing.expectEqual(false, try set.assign(3, true));
    try testing.expect(set.isSet(3));

    // true -> true
    try testing.expectEqual(true, try set.assign(3, true));
    try testing.expect(set.isSet(3));

    // true -> false
    try testing.expectEqual(true, try set.assign(3, false));
    try testing.expect(!set.isSet(3));
}

test "unit: BitSet.Static toggle returns the new value" {
    const Set = BitSet.Static(64);
    var set = Set.init();

    // clear -> set: new = true.
    try testing.expectEqual(true, try set.toggle(12));
    try testing.expect(set.isSet(12));

    // set -> clear: new = false.
    try testing.expectEqual(false, try set.toggle(12));
    try testing.expect(!set.isSet(12));
}

test "unit: BitSet.Static set algebra preserves unused high bits" {
    const Set = BitSet.Static(129);
    var full = Set.full();
    try testing.expect(full.isFull());
    full.clearRetainingCapacity();
    try testing.expect(full.isEmpty());
    full.setAll();

    var other = Set.init();
    _ = try other.set(128);
    try testing.expect(full.containsAll(&other));
    try testing.expect(full.containsAny(&other));

    var unioned = Set.init();
    unioned.unionWith(&other);
    try testing.expect(unioned.eql(&other));
    unioned.intersectWith(&other);
    try testing.expect(unioned.eql(&other));
    unioned.differenceWith(&other);
    try testing.expect(unioned.isEmpty());
}

test "unit: BitSet.Static boundary capacities full and round-trip" {
    try testing.expect(BitSet.Static(1).full().isFull());
    try testing.expect(BitSet.Static(64).full().isFull());
    try testing.expect(BitSet.Static(65).full().isFull());
}
