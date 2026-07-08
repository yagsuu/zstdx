//! Fixed-unit bitmap allocators over `u64`-word storage with lowest-index
//! first-fit placement.
//! Spec: docs/specs/mem/bitmap-allocator.md.

const std = @import("std");

const word = @import("../bits/word.zig");

const RangeUsize = @import("../core/range.zig").Range(usize);

/// Family of fixed-unit bitmap allocators. Both variants share `u64`-word
/// storage, lowest-index first-fit placement, and the unused-bit invariant
/// enforced after every public mutation. They never allocate, never wait,
/// and never touch global state.
pub const BitmapAllocator = struct {
    /// Inline `[word_count]Word` storage. The allocator value owns its
    /// backing storage; a default struct literal and `init()` both yield
    /// an empty allocator.
    pub fn Static(comptime capacity_units: usize) type {
        return struct {
            words: [word_count]Word = [_]Word{0} ** word_count,

            const Self = @This();

            /// Backing word type. Implementation-fixed to `u64`.
            pub const Word = u64;

            /// Bits per backing word.
            pub const word_bits = @bitSizeOf(Word);

            /// Comptime unit capacity.
            pub const unit_capacity = capacity_units;

            /// Number of backing words; rounded up from
            /// `unit_capacity / word_bits`.
            pub const word_count = word.count(Word, capacity_units);

            /// Half-open range of unit indexes.
            pub const Range = RangeUsize;

            /// Error set shared with `BitmapAllocator.Bounded`.
            pub const Error = BitmapAllocator.Bounded.Error;

            /// Empty allocator.
            pub fn init() Self {
                return .{};
            }

            /// Mark every unit free. Capacity and backing storage identity
            /// do not change.
            pub fn clearRetainingCapacity(self: *Self) void {
                for (&self.words) |*w| w.* = 0;
            }

            pub fn capacity(self: Self) usize {
                _ = self;
                return unit_capacity;
            }

            pub fn allocated(self: Self) usize {
                return countAllocated(self.words[0..], unit_capacity);
            }

            pub fn remaining(self: Self) usize {
                return unit_capacity - self.allocated();
            }

            pub fn isEmpty(self: Self) bool {
                return self.allocated() == 0;
            }

            pub fn isFull(self: Self) bool {
                return self.allocated() == unit_capacity;
            }

            /// True only when `index < capacity()` and the unit is
            /// allocated. Out-of-bounds indexes return false.
            pub fn isAllocated(self: Self, index: usize) bool {
                return bitIsSet(self.words[0..], unit_capacity, index);
            }

            /// True only when `index < capacity()` and the unit is free.
            /// Out-of-bounds indexes return false.
            pub fn isFree(self: Self, index: usize) bool {
                if (index >= unit_capacity) return false;
                return !bitIsSet(self.words[0..], unit_capacity, index);
            }

            /// Lowest free unit index, or `error.OutOfMemory` when full.
            pub fn allocOne(self: *Self) Error!usize {
                return allocOneImpl(self.words[0..], unit_capacity);
            }

            /// Lowest contiguous first-fit range of `count` free units.
            /// `count == 0` returns `Range.empty(0)` without mutating.
            pub fn allocRange(self: *Self, count: usize) Error!Range {
                return allocRangeImpl(self.words[0..], unit_capacity, count);
            }

            /// `error.OutOfBounds`: `index >= capacity()`.
            /// `error.AlreadyAllocated`: unit is already allocated.
            /// Error leaves allocator unchanged.
            pub fn reserveOne(self: *Self, index: usize) Error!void {
                return reserveOneImpl(self.words[0..], unit_capacity, index);
            }

            /// `range` must be valid; invalid range is a programmer error.
            /// `error.OutOfBounds`: `range.end > capacity()`.
            /// `error.AlreadyAllocated`: any unit is already allocated.
            /// Empty range is a no-op. Error leaves allocator unchanged.
            pub fn reserveRange(self: *Self, range: Range) Error!void {
                return reserveRangeImpl(self.words[0..], unit_capacity, range);
            }

            pub fn freeOne(self: *Self, index: usize) Error!void {
                return freeOneImpl(self.words[0..], unit_capacity, index);
            }

            /// `range` must be valid; invalid range is a programmer error.
            /// `error.OutOfBounds`: `range.end > capacity()`.
            /// `error.NotAllocated`: any unit is already free.
            /// Empty range is a no-op. Error leaves allocator unchanged.
            pub fn freeRange(self: *Self, range: Range) Error!void {
                return freeRangeImpl(self.words[0..], unit_capacity, range);
            }

            /// True when structural invariants hold: unused high bits in
            /// the final logical word are zero, and no trailing storage
            /// is needed past the inline word count (always satisfied for
            /// `Static`).
            pub fn isValid(self: Self) bool {
                return checkValid(self.words[0..], unit_capacity);
            }

            pub fn assertValid(self: Self) void {
                std.debug.assert(self.isValid());
            }
        };
    }

    /// Borrowed `[]Word` bitmap. The caller keeps `words` alive for the
    /// lifetime of the allocator.
    pub const Bounded = struct {
        words: []Word,
        unit_capacity: usize,

        /// Backing word type. Implementation-fixed to `u64`.
        pub const Word = u64;

        /// Bits per backing word.
        pub const word_bits = @bitSizeOf(Word);

        /// Half-open range of unit indexes.
        pub const Range = RangeUsize;

        /// `OutOfMemory`: requested allocation cannot be satisfied.
        /// `OutOfBounds`: caller index or range, or wrap capacity, is
        ///   outside the allocator's unit space.
        /// `AlreadyAllocated`: reserve would overlap an allocated unit.
        /// `NotAllocated`: free would overlap a free unit.
        pub const Error = error{
            OutOfMemory,
            OutOfBounds,
            AlreadyAllocated,
            NotAllocated,
        };

        /// Borrowed words are zeroed only on success.
        /// `error.OutOfBounds`: `unit_capacity` exceeds word storage; unchanged on error.
        pub fn wrap(words: []Word, unit_capacity: usize) Error!Bounded {
            if (word.count(Word, unit_capacity) > words.len) return error.OutOfBounds;
            for (words) |*w| w.* = 0;
            return .{ .words = words, .unit_capacity = unit_capacity };
        }

        pub fn clearRetainingCapacity(self: *Bounded) void {
            for (self.words) |*w| w.* = 0;
        }

        pub fn capacity(self: Bounded) usize {
            return self.unit_capacity;
        }

        pub fn allocated(self: Bounded) usize {
            return countAllocated(self.words, self.unit_capacity);
        }

        pub fn remaining(self: Bounded) usize {
            return self.unit_capacity - self.allocated();
        }

        pub fn isEmpty(self: Bounded) bool {
            return self.allocated() == 0;
        }

        pub fn isFull(self: Bounded) bool {
            return self.allocated() == self.unit_capacity;
        }

        pub fn isAllocated(self: Bounded, index: usize) bool {
            return bitIsSet(self.words, self.unit_capacity, index);
        }

        pub fn isFree(self: Bounded, index: usize) bool {
            if (index >= self.unit_capacity) return false;
            return !bitIsSet(self.words, self.unit_capacity, index);
        }

        pub fn allocOne(self: *Bounded) Error!usize {
            return allocOneImpl(self.words, self.unit_capacity);
        }

        pub fn allocRange(self: *Bounded, count: usize) Error!Range {
            return allocRangeImpl(self.words, self.unit_capacity, count);
        }

        /// `error.OutOfBounds`: `index >= capacity()`.
        /// `error.AlreadyAllocated`: unit is already allocated.
        /// Error leaves allocator unchanged.
        pub fn reserveOne(self: *Bounded, index: usize) Error!void {
            return reserveOneImpl(self.words, self.unit_capacity, index);
        }

        /// `range` must be valid; invalid range is a programmer error.
        /// `error.OutOfBounds`: `range.end > capacity()`.
        /// `error.AlreadyAllocated`: any unit is already allocated.
        /// Empty range is a no-op. Error leaves allocator unchanged.
        pub fn reserveRange(self: *Bounded, range: Range) Error!void {
            return reserveRangeImpl(self.words, self.unit_capacity, range);
        }

        pub fn freeOne(self: *Bounded, index: usize) Error!void {
            return freeOneImpl(self.words, self.unit_capacity, index);
        }

        /// `range` must be valid; invalid range is a programmer error.
        /// `error.OutOfBounds`: `range.end > capacity()`.
        /// `error.NotAllocated`: any unit is already free.
        /// Empty range is a no-op. Error leaves allocator unchanged.
        pub fn freeRange(self: *Bounded, range: Range) Error!void {
            return freeRangeImpl(self.words, self.unit_capacity, range);
        }

        /// True when `unit_capacity <= words.len * word_bits`, unused high
        /// bits in the final logical word are zero, and every borrowed
        /// word past the logical word count is zero.
        pub fn isValid(self: Bounded) bool {
            return checkValid(self.words, self.unit_capacity);
        }

        pub fn assertValid(self: Bounded) void {
            std.debug.assert(self.isValid());
        }
    };
};

// Shared bit-arithmetic helpers; every mutator preflights its full effect
// so that errors leave storage untouched.
const BitmapWord = u64;
const bitmap_word_bits = @bitSizeOf(BitmapWord);
const BitmapError = BitmapAllocator.Bounded.Error;
const Shift = std.math.Log2Int(BitmapWord);

fn logicalWordCount(unit_capacity: usize) usize {
    return word.count(BitmapWord, unit_capacity);
}

fn bitIsSet(words: []const BitmapWord, unit_capacity: usize, index: usize) bool {
    if (index >= unit_capacity) return false;
    return word.isSet(BitmapWord, words, index);
}

fn countAllocated(words: []const BitmapWord, unit_capacity: usize) usize {
    const lwc = logicalWordCount(unit_capacity);
    if (lwc == 0) return 0;

    var total: usize = 0;
    for (words[0..lwc]) |w| total += @popCount(w);
    return total;
}

fn findFirstFree(words: []const BitmapWord, unit_capacity: usize) ?usize {
    const lwc = logicalWordCount(unit_capacity);
    if (lwc == 0) return null;

    if (lwc > 1) {
        for (words[0 .. lwc - 1], 0..) |w, word_index| {
            const inv = ~w;
            if (inv != 0) return word_index * bitmap_word_bits + @ctz(inv);
        }
    }

    const last = words[lwc - 1];
    const inv = (~last) & word.lastMask(BitmapWord, unit_capacity);
    if (inv != 0) return (lwc - 1) * bitmap_word_bits + @ctz(inv);
    return null;
}

fn findFirstFreeRun(words: []const BitmapWord, unit_capacity: usize, count: usize) ?usize {
    var run_start: usize = 0;
    var run_len: usize = 0;
    var i: usize = 0;
    while (i < unit_capacity) : (i += 1) {
        if (!word.isSet(BitmapWord, words, i)) {
            if (run_len == 0) run_start = i;
            run_len += 1;
            if (run_len == count) return run_start;
        } else {
            run_len = 0;
        }
    }

    return null;
}

fn setBits(words: []BitmapWord, start: usize, end: usize) void {
    var i: usize = start;
    while (i < end) : (i += 1) word.set(BitmapWord, words, i);
}

fn clearBits(words: []BitmapWord, start: usize, end: usize) void {
    var i: usize = start;
    while (i < end) : (i += 1) word.clear(BitmapWord, words, i);
}

fn anyBitSet(words: []const BitmapWord, start: usize, end: usize) bool {
    var i: usize = start;
    while (i < end) : (i += 1) {
        if (word.isSet(BitmapWord, words, i)) return true;
    }
    return false;
}

fn anyBitClear(words: []const BitmapWord, start: usize, end: usize) bool {
    var i: usize = start;
    while (i < end) : (i += 1) {
        if (!word.isSet(BitmapWord, words, i)) return true;
    }
    return false;
}

fn allocOneImpl(words: []BitmapWord, unit_capacity: usize) BitmapError!usize {
    const index = findFirstFree(words, unit_capacity) orelse return error.OutOfMemory;
    word.set(BitmapWord, words, index);
    return index;
}

fn allocRangeImpl(words: []BitmapWord, unit_capacity: usize, count: usize) BitmapError!RangeUsize {
    if (count == 0) return RangeUsize.empty(0);
    if (count > unit_capacity) return error.OutOfMemory;

    const start = findFirstFreeRun(words, unit_capacity, count) orelse return error.OutOfMemory;
    setBits(words, start, start + count);
    return RangeUsize.fromBounds(start, start + count) catch unreachable;
}

fn reserveOneImpl(words: []BitmapWord, unit_capacity: usize, index: usize) BitmapError!void {
    if (index >= unit_capacity) return error.OutOfBounds;

    if (word.isSet(BitmapWord, words, index)) return error.AlreadyAllocated;
    word.set(BitmapWord, words, index);
}

fn reserveRangeImpl(words: []BitmapWord, unit_capacity: usize, range: RangeUsize) BitmapError!void {
    range.assertValid();

    if (range.isEmpty()) {
        if (range.start > unit_capacity) return error.OutOfBounds;
        return;
    }

    if (range.end > unit_capacity) return error.OutOfBounds;
    if (anyBitSet(words, range.start, range.end)) return error.AlreadyAllocated;

    setBits(words, range.start, range.end);
}

fn freeOneImpl(words: []BitmapWord, unit_capacity: usize, index: usize) BitmapError!void {
    if (index >= unit_capacity) return error.OutOfBounds;

    if (!word.isSet(BitmapWord, words, index)) return error.NotAllocated;
    word.clear(BitmapWord, words, index);
}

fn freeRangeImpl(words: []BitmapWord, unit_capacity: usize, range: RangeUsize) BitmapError!void {
    range.assertValid();

    if (range.isEmpty()) {
        if (range.start > unit_capacity) return error.OutOfBounds;
        return;
    }

    if (range.end > unit_capacity) return error.OutOfBounds;
    if (anyBitClear(words, range.start, range.end)) return error.NotAllocated;

    clearBits(words, range.start, range.end);
}

fn checkValid(words: []const BitmapWord, unit_capacity: usize) bool {
    const lwc = logicalWordCount(unit_capacity);
    if (lwc > words.len) return false;

    if (lwc > 0) {
        if ((words[lwc - 1] & ~word.lastMask(BitmapWord, unit_capacity)) != 0) return false;
    }

    var i: usize = lwc;
    while (i < words.len) : (i += 1) {
        if (words[i] != 0) return false;
    }

    return true;
}
