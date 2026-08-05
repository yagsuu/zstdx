//! Fixed-capacity bit sets. See `docs/specs/bits/set/static.md`.

const std = @import("std");

const word = @import("word.zig");

/// `Static(N)` owns inline word storage and never allocates or waits.
pub const BitSet = struct {
    /// Requirements: `capacity_bits >= 1`.
    /// Invariant: Unused high bits in the final word remain zero.
    pub fn Static(comptime capacity_bits: usize) type {
        comptime if (capacity_bits == 0) @compileError("BitSet.Static requires capacity_bits >= 1");

        return struct {
            words: [word_count]Word = [_]Word{0} ** word_count,

            const Self = @This();

            /// `OutOfBounds`: mutator received an index at or past `bit_capacity`.
            pub const Error = error{OutOfBounds};

            pub const Word = u64;

            pub const word_bits = @bitSizeOf(Word);

            /// The comptime slot count.
            pub const bit_capacity = capacity_bits;

            pub const word_count = word.count(Word, capacity_bits);

            pub fn init() Self {
                return .{};
            }

            /// Returns a set with every valid bit set and every unused high bit clear.
            pub fn full() Self {
                var self: Self = .{};
                self.setAll();
                return self;
            }

            /// Clears every valid bit; slot count is unchanged.
            pub fn clearRetainingCapacity(self: *Self) void {
                for (&self.words) |*w| w.* = 0;
            }

            /// Sets every valid bit; unused high bits stay clear.
            pub fn setAll(self: *Self) void {
                for (&self.words) |*w| w.* = ~@as(Word, 0);
                self.clearUnused();
            }

            pub fn isEmpty(self: *const Self) bool {
                self.assertValid();
                for (self.words) |w| if (w != 0) return false;
                return true;
            }

            pub fn isFull(self: *const Self) bool {
                self.assertValid();
                for (self.words[0 .. word_count - 1]) |w| if (w != ~@as(Word, 0)) return false;
                return self.words[word_count - 1] == word.lastMask(Word, bit_capacity);
            }

            /// Returns the number of set bits.
            pub fn count(self: *const Self) usize {
                self.assertValid();

                var total: usize = 0;
                for (self.words) |w| total += @popCount(w);
                return total;
            }

            /// Returns `true` when `index` is set. Returns `false` for
            /// `index >= bit_capacity`; never errors.
            pub fn isSet(self: *const Self, index: usize) bool {
                self.assertValid();
                if (index >= bit_capacity) return false;
                return word.isSet(Word, self.words[0..], index);
            }

            /// Sets `index`; returns the prior bit value (`true` when it was already set).
            pub fn set(self: *Self, index: usize) Error!bool {
                try checkIndex(index);

                const prior = word.isSet(Word, self.words[0..], index);
                word.set(Word, self.words[0..], index);
                return prior;
            }

            /// Clears `index`; returns the prior bit value (`true` when it was previously set).
            pub fn unset(self: *Self, index: usize) Error!bool {
                try checkIndex(index);

                const prior = word.isSet(Word, self.words[0..], index);
                word.clear(Word, self.words[0..], index);
                return prior;
            }

            /// Writes `value`; returns the prior bit value.
            pub fn assign(self: *Self, index: usize, value: bool) Error!bool {
                return if (value) self.set(index) else self.unset(index);
            }

            /// Returns the new bit value. This differs from `set`, `unset`, and `assign` because the prior toggle value is always `!new`.
            pub fn toggle(self: *Self, index: usize) Error!bool {
                try checkIndex(index);

                const w = &self.words[word.indexOf(Word, index)];
                const bit = word.maskOf(Word, index);
                w.* ^= bit;
                return (w.* & bit) != 0;
            }

            /// Returns the lowest set index, or `null` when empty.
            pub fn firstSet(self: *const Self) ?usize {
                self.assertValid();
                for (self.words, 0..) |w, word_index| {
                    if (w != 0) return word_index * word_bits + @ctz(w);
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

            pub fn unionWith(self: *Self, other: *const Self) void {
                other.assertValid();
                for (&self.words, other.words) |*a, b| a.* |= b;
                self.clearUnused();
            }

            pub fn intersectWith(self: *Self, other: *const Self) void {
                other.assertValid();
                for (&self.words, other.words) |*a, b| a.* &= b;
                self.clearUnused();
            }

            pub fn differenceWith(self: *Self, other: *const Self) void {
                other.assertValid();
                for (&self.words, other.words) |*a, b| a.* &= ~b;
                self.clearUnused();
            }

            /// Asserts that unused bits past `bit_capacity` in the last word are zero.
            pub fn assertValid(self: *const Self) void {
                std.debug.assert((self.words[word_count - 1] & ~word.lastMask(Word, bit_capacity)) == 0);
            }

            fn checkIndex(index: usize) Error!void {
                if (index >= bit_capacity) return error.OutOfBounds;
            }

            fn clearUnused(self: *Self) void {
                self.words[word_count - 1] &= word.lastMask(Word, bit_capacity);
            }
        };
    }
};
