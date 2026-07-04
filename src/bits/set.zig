//! Fixed-capacity bit sets used for slot occupancy, free-index tracking,
//! resource masks, and small bounded integer domains. See
//! docs/specs/bits/bitset-static.md.

const std = @import("std");

/// Family of fixed-capacity bit sets. The single approved variant `Static(N)`
/// owns inline word storage; never allocates and never waits.
pub const BitSet = struct {
    /// Bit set with comptime-fixed capacity `capacity_bits`. `capacity_bits`
    /// must be at least 1; `Static(0)` is rejected at compile time. Unused
    /// high bits in the final word stay zero after every public operation.
    pub fn Static(comptime capacity_bits: usize) type {
        comptime if (capacity_bits == 0) @compileError("BitSet.Static requires capacity_bits >= 1");

        return struct {
            words: [word_count]Word = [_]Word{0} ** word_count,

            const Self = @This();

            /// `OutOfBounds`: mutator received an index at or past `bit_capacity`.
            pub const Error = error{OutOfBounds};

            /// Backing storage word type.
            pub const Word = u64;

            /// Bits per backing word.
            pub const word_bits = @bitSizeOf(Word);

            /// Comptime bit capacity (slot count).
            pub const bit_capacity = capacity_bits;

            /// Number of backing words; rounded up from `bit_capacity / word_bits`.
            pub const word_count = @divFloor(capacity_bits, word_bits) + @intFromBool(capacity_bits % word_bits != 0);

            /// Empty set.
            pub fn init() Self {
                return .{};
            }

            /// Set with every valid bit set and every unused high bit clear.
            pub fn full() Self {
                var self: Self = .{};
                self.setAll();
                return self;
            }

            /// Clear every valid bit; slot count is unchanged.
            pub fn clearRetainingCapacity(self: *Self) void {
                for (&self.words) |*word| word.* = 0;
            }

            /// Set every valid bit; unused high bits stay clear.
            pub fn setAll(self: *Self) void {
                for (&self.words) |*word| word.* = ~@as(Word, 0);
                self.clearUnused();
            }

            pub fn isEmpty(self: *const Self) bool {
                self.assertValid();
                for (self.words) |word| if (word != 0) return false;
                return true;
            }

            pub fn isFull(self: *const Self) bool {
                self.assertValid();
                for (self.words[0 .. word_count - 1]) |word| if (word != ~@as(Word, 0)) return false;
                return self.words[word_count - 1] == lastMask();
            }

            /// Population (number of set bits).
            pub fn count(self: *const Self) usize {
                self.assertValid();

                var total: usize = 0;
                for (self.words) |word| total += @popCount(word);
                return total;
            }

            /// True when `index` is set. Returns `false` for
            /// `index >= bit_capacity`; never errors.
            pub fn isSet(self: *const Self, index: usize) bool {
                self.assertValid();
                if (index >= bit_capacity) return false;
                return (self.words[@divFloor(index, word_bits)] & mask(index)) != 0;
            }

            /// Sets `index`; returns the prior bit value (`true` when it was already set).
            pub fn set(self: *Self, index: usize) Error!bool {
                try checkIndex(index);

                const word = &self.words[@divFloor(index, word_bits)];
                const bit = mask(index);
                const prior = (word.* & bit) != 0;
                word.* |= bit;
                return prior;
            }

            /// Clears `index`; returns the prior bit value (`true` when it was previously set).
            pub fn unset(self: *Self, index: usize) Error!bool {
                try checkIndex(index);

                const word = &self.words[@divFloor(index, word_bits)];
                const bit = mask(index);
                const prior = (word.* & bit) != 0;
                word.* &= ~bit;
                return prior;
            }

            /// Writes `value`; returns the prior bit value.
            pub fn assign(self: *Self, index: usize, value: bool) Error!bool {
                return if (value) self.set(index) else self.unset(index);
            }

            /// Flips `index`; returns the new (post-toggle) bit value. Asymmetric
            /// with `set`/`unset`/`assign` by design: the prior value of a toggle is
            /// just `!new` and carries no extra information.
            pub fn toggle(self: *Self, index: usize) Error!bool {
                try checkIndex(index);

                const word = &self.words[@divFloor(index, word_bits)];
                const bit = mask(index);
                word.* ^= bit;
                return (word.* & bit) != 0;
            }

            /// Lowest set index, or `null` when empty.
            pub fn firstSet(self: *const Self) ?usize {
                self.assertValid();
                for (self.words, 0..) |word, word_index| {
                    if (word != 0) return word_index * word_bits + @ctz(word);
                }
                return null;
            }

            /// Removes and returns the lowest set index, or `null` when empty.
            pub fn popFirstSet(self: *Self) ?usize {
                const index = self.firstSet() orelse return null;
                _ = self.unset(index) catch unreachable;
                return index;
            }

            pub fn eql(self: *const Self, other: *const Self) bool {
                self.assertValid();
                other.assertValid();
                return std.mem.eql(Word, &self.words, &other.words);
            }

            pub fn containsAll(self: *const Self, other: *const Self) bool {
                self.assertValid();
                other.assertValid();

                for (self.words, other.words) |a, b| if ((a & b) != b) return false;
                return true;
            }

            pub fn containsAny(self: *const Self, other: *const Self) bool {
                self.assertValid();
                other.assertValid();

                for (self.words, other.words) |a, b| if ((a & b) != 0) return true;
                return false;
            }

            /// `self <- self ∪ other`.
            pub fn unionWith(self: *Self, other: *const Self) void {
                other.assertValid();
                for (&self.words, other.words) |*a, b| a.* |= b;
                self.clearUnused();
            }

            /// `self <- self ∩ other`.
            pub fn intersectWith(self: *Self, other: *const Self) void {
                other.assertValid();
                for (&self.words, other.words) |*a, b| a.* &= b;
                self.clearUnused();
            }

            /// `self <- self \ other`.
            pub fn differenceWith(self: *Self, other: *const Self) void {
                other.assertValid();
                for (&self.words, other.words) |*a, b| a.* &= ~b;
                self.clearUnused();
            }

            /// Asserts the unused-bit invariant: every bit past `bit_capacity` in
            /// the last word is zero.
            pub fn assertValid(self: *const Self) void {
                std.debug.assert((self.words[word_count - 1] & ~lastMask()) == 0);
            }

            fn lastMask() Word {
                const rem = bit_capacity % word_bits;
                if (rem == 0) return ~@as(Word, 0);

                const shift_amount: std.math.Log2Int(Word) = @intCast(rem);
                return (@as(Word, 1) << shift_amount) - 1;
            }

            fn mask(index: usize) Word {
                return @as(Word, 1) << @as(std.math.Log2Int(Word), @intCast(index % word_bits));
            }

            fn checkIndex(index: usize) Error!void {
                if (index >= bit_capacity) return error.OutOfBounds;
            }

            fn clearUnused(self: *Self) void {
                self.words[word_count - 1] &= lastMask();
            }
        };
    }
};
