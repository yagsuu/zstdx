//! Fixed-capacity bit sets used for slot occupancy, free-index tracking,
//! resource masks, and small bounded integer domains. See
//! docs/specs/bits/bitset-static.md.

const std = @import("std");

/// Family of fixed-capacity bit sets. The single approved variant `Static(N)`
/// owns inline word storage; never allocates and never waits.
pub const BitSet = struct {
    /// Bit set with comptime-fixed capacity `capacity_bits`. `Static(0)` is
    /// valid and is both empty and full. Unused high bits in the final word
    /// stay zero after every public operation.
    pub fn Static(comptime capacity_bits: usize) type {
        return struct {
            words: [word_count]Word = [_]Word{0} ** word_count,

            const Self = @This();

            /// `OutOfBounds`: index is at or past `bit_count`.
            pub const Error = error{OutOfBounds};

            /// Backing storage word type.
            pub const Word = u64;

            /// Bits per backing word.
            pub const word_bits = @bitSizeOf(Word);

            /// Comptime bit capacity.
            pub const bit_count = capacity_bits;

            /// Number of backing words; rounded up from `bit_count / word_bits`.
            pub const word_count = capacity_bits / word_bits + @intFromBool(capacity_bits % word_bits != 0);

            /// Empty set.
            pub fn init() Self {
                return .{};
            }

            /// Set with every valid bit set and every unused high bit clear.
            pub fn full() Self {
                var self: Self = .{};
                self.fill();
                return self;
            }

            fn lastMask() Word {
                if (bit_count == 0) return 0;
                const rem = bit_count % word_bits;
                if (rem == 0) return ~@as(Word, 0);
                return (@as(Word, 1) << @as(std.math.Log2Int(Word), @intCast(rem))) - 1;
            }

            fn mask(index: usize) Word {
                return @as(Word, 1) << @as(std.math.Log2Int(Word), @intCast(index % word_bits));
            }

            fn checkIndex(index: usize) Error!void {
                if (index >= bit_count) return error.OutOfBounds;
            }

            fn clearUnused(self: *Self) void {
                if (word_count > 0) self.words[word_count - 1] &= lastMask();
            }

            pub fn clearAll(self: *Self) void {
                for (&self.words) |*word| word.* = 0;
            }

            /// Set every valid bit; unused high bits stay clear.
            pub fn fill(self: *Self) void {
                for (&self.words) |*word| word.* = ~@as(Word, 0);
                self.clearUnused();
            }

            pub fn isEmpty(self: Self) bool {
                self.assertValid();
                for (self.words) |word| if (word != 0) return false;
                return true;
            }

            /// `Static(0).isFull()` is true because every bit in the empty
            /// universe is set.
            pub fn isFull(self: Self) bool {
                self.assertValid();
                if (word_count == 0) return true;
                for (self.words[0 .. word_count - 1]) |word| if (word != ~@as(Word, 0)) return false;
                return self.words[word_count - 1] == lastMask();
            }

            pub fn count(self: Self) usize {
                self.assertValid();
                var total: usize = 0;
                for (self.words) |word| total += @popCount(word);
                return total;
            }

            pub fn isSet(self: Self, index: usize) Error!bool {
                try checkIndex(index);
                self.assertValid();
                if (bit_count == 0) unreachable;
                return (self.words[index / word_bits] & mask(index)) != 0;
            }

            pub fn set(self: *Self, index: usize) Error!void {
                try checkIndex(index);
                if (bit_count == 0) unreachable;
                self.words[index / word_bits] |= mask(index);
            }

            pub fn unset(self: *Self, index: usize) Error!void {
                try checkIndex(index);
                if (bit_count == 0) unreachable;
                self.words[index / word_bits] &= ~mask(index);
            }

            pub fn assign(self: *Self, index: usize, value: bool) Error!void {
                if (value) try self.set(index) else try self.unset(index);
            }

            pub fn toggle(self: *Self, index: usize) Error!void {
                try checkIndex(index);
                if (bit_count == 0) unreachable;
                self.words[index / word_bits] ^= mask(index);
            }

            /// Sets `index` and returns true iff the bit changed from unset to
            /// set.
            pub fn insert(self: *Self, index: usize) Error!bool {
                const was_set = try self.isSet(index);
                if (!was_set) try self.set(index);
                return !was_set;
            }

            /// Clears `index` and returns true iff the bit changed from set to
            /// unset.
            pub fn remove(self: *Self, index: usize) Error!bool {
                const was_set = try self.isSet(index);
                if (was_set) try self.unset(index);
                return was_set;
            }

            /// Lowest set index, or `null` when empty.
            pub fn firstSet(self: Self) ?usize {
                self.assertValid();
                for (self.words, 0..) |word, word_index| {
                    if (word != 0) return word_index * word_bits + @ctz(word);
                }
                return null;
            }

            /// Removes and returns the lowest set index, or `null` when empty.
            pub fn popFirstSet(self: *Self) ?usize {
                const index = self.firstSet() orelse return null;
                self.unset(index) catch unreachable;
                return index;
            }

            pub fn eql(self: Self, other: Self) bool {
                self.assertValid();
                other.assertValid();
                return std.mem.eql(Word, &self.words, &other.words);
            }

            pub fn containsAll(self: Self, other: Self) bool {
                self.assertValid();
                other.assertValid();
                for (self.words, other.words) |a, b| if ((a & b) != b) return false;
                return true;
            }

            pub fn containsAny(self: Self, other: Self) bool {
                self.assertValid();
                other.assertValid();
                for (self.words, other.words) |a, b| if ((a & b) != 0) return true;
                return false;
            }

            /// `self <- self ∪ other`.
            pub fn unionWith(self: *Self, other: Self) void {
                other.assertValid();
                for (&self.words, other.words) |*a, b| a.* |= b;
                self.clearUnused();
            }

            /// `self <- self ∩ other`.
            pub fn intersectWith(self: *Self, other: Self) void {
                other.assertValid();
                for (&self.words, other.words) |*a, b| a.* &= b;
                self.clearUnused();
            }

            /// `self <- self \ other`.
            pub fn differenceWith(self: *Self, other: Self) void {
                other.assertValid();
                for (&self.words, other.words) |*a, b| a.* &= ~b;
                self.clearUnused();
            }

            /// Asserts the unused-bit invariant: every bit past `bit_count` in
            /// the last word is zero.
            pub fn assertValid(self: Self) void {
                if (word_count > 0) std.debug.assert((self.words[word_count - 1] & ~lastMask()) == 0);
            }
        };
    }
};
