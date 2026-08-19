//! Fixed-unit bitmap allocators over `u64`-word storage with lowest-index
//! first-fit placement.
//! See `docs/specs/mem/alloc/bitmap.md`.

const std = @import("std");

const word = @import("../../bits/word.zig");

const RangeUsize = @import("../../core/range.zig").Range(usize);

const BitmapWord = u64;
const Shift = std.math.Log2Int(BitmapWord);

const bitmap_word_bits = @bitSizeOf(BitmapWord);

pub const BitmapAllocator = struct {
    pub fn Static(comptime capacity_units: usize) type {
        comptime if (capacity_units == 0) @compileError("BitmapAllocator.Static capacity_units must be non-zero");

        return struct {
            words: [word_count]Word = [_]Word{0} ** word_count,

            const Self = @This();

            pub const Word = u64;
            pub const Range = RangeUsize;

            pub const Error = BitmapAllocator.Bounded.Error;
            pub const AllocError = BitmapAllocator.Bounded.AllocError;
            pub const ReserveError = BitmapAllocator.Bounded.ReserveError;
            pub const FreeError = BitmapAllocator.Bounded.FreeError;

            pub const word_bits = @bitSizeOf(Word);
            pub const unit_capacity = capacity_units;
            pub const word_count = word.count(Word, capacity_units);

            pub fn init() Self {
                return .{};
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

            /// Returns false when `index` is out of bounds.
            pub fn isAllocated(self: Self, index: usize) bool {
                return bitIsSet(self.words[0..], unit_capacity, index);
            }

            /// Returns false when `index` is out of bounds.
            pub fn isFree(self: Self, index: usize) bool {
                if (index >= unit_capacity) return false;
                return !bitIsSet(self.words[0..], unit_capacity, index);
            }

            /// Allocates the lowest free unit.
            pub fn allocOne(self: *Self) AllocError!usize {
                return allocOneImpl(self.words[0..], unit_capacity);
            }

            /// Allocates the lowest contiguous free range.
            /// `count == 0` does not mutate.
            pub fn allocRange(self: *Self, count: usize) AllocError!Range {
                return allocRangeImpl(self.words[0..], unit_capacity, count);
            }

            /// Leaves the bitmap unchanged on error.
            pub fn reserveOne(self: *Self, index: usize) ReserveError!void {
                return reserveOneImpl(self.words[0..], unit_capacity, index);
            }

            /// Requires a valid `range`.
            /// An empty in-bounds range is a no-op; errors do not mutate.
            pub fn reserveRange(self: *Self, range: Range) ReserveError!void {
                return reserveRangeImpl(self.words[0..], unit_capacity, range);
            }

            pub fn freeOne(self: *Self, index: usize) FreeError!void {
                return freeOneImpl(self.words[0..], unit_capacity, index);
            }

            /// Requires a valid `range`.
            /// An empty in-bounds range is a no-op; errors do not mutate.
            pub fn freeRange(self: *Self, range: Range) FreeError!void {
                return freeRangeImpl(self.words[0..], unit_capacity, range);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                for (&self.words) |*w| w.* = 0;
            }

            pub fn isValid(self: Self) bool {
                return checkValid(self.words[0..], unit_capacity);
            }

            pub fn assertValid(self: Self) void {
                std.debug.assert(self.isValid());
            }
        };
    }

    /// Borrows `words`; they must outlive the allocator.
    pub const Bounded = struct {
        words: []Word,
        unit_capacity: usize,

        pub const Word = u64;
        pub const Range = RangeUsize;

        pub const word_bits = @bitSizeOf(Word);

        /// `OutOfMemory`: requested allocation cannot be satisfied.
        /// `OutOfBounds`: caller index or range, or wrap capacity, is
        ///   outside the allocator's unit space.
        /// `AlreadyAllocated`: reserve would overlap an allocated unit.
        /// `NotAllocated`: free would overlap a free unit.
        pub const WrapError = error{OutOfBounds};
        pub const AllocError = error{OutOfMemory};
        pub const ReserveError = error{ OutOfBounds, AlreadyAllocated };
        pub const FreeError = error{ OutOfBounds, NotAllocated };
        pub const Error = WrapError || AllocError || ReserveError || FreeError;

        /// Clears `words` only after validating `unit_capacity`.
        pub fn wrap(words: []Word, unit_capacity: usize) WrapError!Bounded {
            if (word.count(Word, unit_capacity) > words.len) return error.OutOfBounds;
            for (words) |*w| w.* = 0;
            return .{ .words = words, .unit_capacity = unit_capacity };
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

        pub fn allocOne(self: *Bounded) AllocError!usize {
            return allocOneImpl(self.words, self.unit_capacity);
        }

        pub fn allocRange(self: *Bounded, count: usize) AllocError!Range {
            return allocRangeImpl(self.words, self.unit_capacity, count);
        }

        pub fn reserveOne(self: *Bounded, index: usize) ReserveError!void {
            return reserveOneImpl(self.words, self.unit_capacity, index);
        }

        /// Requires a valid `range`.
        /// An empty in-bounds range is a no-op; errors do not mutate.
        pub fn reserveRange(self: *Bounded, range: Range) ReserveError!void {
            return reserveRangeImpl(self.words, self.unit_capacity, range);
        }

        pub fn freeOne(self: *Bounded, index: usize) FreeError!void {
            return freeOneImpl(self.words, self.unit_capacity, index);
        }

        /// Requires a valid `range`.
        /// An empty in-bounds range is a no-op; errors do not mutate.
        pub fn freeRange(self: *Bounded, range: Range) FreeError!void {
            return freeRangeImpl(self.words, self.unit_capacity, range);
        }

        pub fn clearRetainingCapacity(self: *Bounded) void {
            for (self.words) |*w| w.* = 0;
        }

        pub fn isValid(self: Bounded) bool {
            return checkValid(self.words, self.unit_capacity);
        }

        pub fn assertValid(self: Bounded) void {
            std.debug.assert(self.isValid());
        }
    };
};

const BitmapAllocError = BitmapAllocator.Bounded.AllocError;
const BitmapReserveError = BitmapAllocator.Bounded.ReserveError;
const BitmapFreeError = BitmapAllocator.Bounded.FreeError;

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

fn allocOneImpl(words: []BitmapWord, unit_capacity: usize) BitmapAllocError!usize {
    const index = findFirstFree(words, unit_capacity) orelse return error.OutOfMemory;
    word.set(BitmapWord, words, index);
    return index;
}

fn allocRangeImpl(words: []BitmapWord, unit_capacity: usize, count: usize) BitmapAllocError!RangeUsize {
    if (count == 0) return RangeUsize.empty(0);
    if (count > unit_capacity) return error.OutOfMemory;

    const start = findFirstFreeRun(words, unit_capacity, count) orelse return error.OutOfMemory;
    setBits(words, start, start + count);
    return RangeUsize.fromBounds(start, start + count) catch unreachable;
}

fn reserveOneImpl(words: []BitmapWord, unit_capacity: usize, index: usize) BitmapReserveError!void {
    if (index >= unit_capacity) return error.OutOfBounds;

    if (word.isSet(BitmapWord, words, index)) return error.AlreadyAllocated;
    word.set(BitmapWord, words, index);
}

fn reserveRangeImpl(words: []BitmapWord, unit_capacity: usize, range: RangeUsize) BitmapReserveError!void {
    range.assertValid();

    if (range.isEmpty()) {
        if (range.start > unit_capacity) return error.OutOfBounds;
        return;
    }

    if (range.end > unit_capacity) return error.OutOfBounds;
    if (anyBitSet(words, range.start, range.end)) return error.AlreadyAllocated;

    setBits(words, range.start, range.end);
}

fn freeOneImpl(words: []BitmapWord, unit_capacity: usize, index: usize) BitmapFreeError!void {
    if (index >= unit_capacity) return error.OutOfBounds;

    if (!word.isSet(BitmapWord, words, index)) return error.NotAllocated;
    word.clear(BitmapWord, words, index);
}

fn freeRangeImpl(words: []BitmapWord, unit_capacity: usize, range: RangeUsize) BitmapFreeError!void {
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
