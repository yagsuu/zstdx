//! Fixed-capacity tag allocators backed by a u64-word bitmap; both
//! variants share an identical observable surface and differ only in
//! storage ownership. Spec: docs/specs/tags/tag-allocator.md.

const std = @import("std");

const word = @import("../bits/word.zig");
const TagFactory = @import("tag.zig").Tag;

/// Family of fixed-capacity tag allocators. Both variants share an
/// identical observable surface and differ only in storage ownership:
/// `Static` carries inline `[word_count]Word` storage, `Bounded` borrows
/// a `[]Word` slice and a runtime `tag_capacity`.
pub const TagAllocator = struct {
    /// Inline-storage tag allocator. `capacity` is fixed at comptime and
    /// must satisfy `capacity <= std.math.maxInt(Int) + 1`.
    pub fn Static(
        comptime DomainT: type,
        comptime IntT: type,
        comptime capacity_tags: comptime_int,
    ) type {
        comptime {
            if (capacity_tags < 0) {
                @compileError("TagAllocator.Static capacity must be non-negative");
            }
            const max_tags: comptime_int = @as(comptime_int, std.math.maxInt(IntT)) + 1;
            if (capacity_tags > max_tags) {
                @compileError("TagAllocator.Static capacity exceeds Int range");
            }
        }
        const TagT = TagFactory(DomainT, IntT);
        const tag_capacity_const: usize = capacity_tags;
        const word_count_const: usize = wordCountFor(tag_capacity_const);
        return struct {
            words: [word_count_const]Word = [_]Word{0} ** word_count_const,
            allocated_count: usize = 0,

            const Self = @This();

            pub const Domain = DomainT;
            pub const Int = IntT;
            pub const Tag = TagT;
            pub const tag_capacity: usize = tag_capacity_const;

            pub const Word = u64;
            pub const word_bits = @bitSizeOf(Word);
            pub const word_count: usize = word_count_const;

            pub const Error = error{
                OutOfTags,
                OutOfBounds,
                AlreadyAllocated,
                NotAllocated,
            };

            pub fn init() Self {
                return .{};
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return tag_capacity;
            }

            pub fn allocated(self: *const Self) usize {
                return self.allocated_count;
            }

            pub fn remaining(self: *const Self) usize {
                return tag_capacity - self.allocated_count;
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.allocated_count == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.allocated_count == tag_capacity;
            }

            pub fn isAllocated(self: *const Self, tag: Tag) bool {
                return queryBit(self.words[0..], tag_capacity, tag);
            }

            pub fn isFree(self: *const Self, tag: Tag) bool {
                const idx = boundedIndex(Int, tag, tag_capacity) orelse return false;
                return !testBit(self.words[0..], idx);
            }

            /// `error.OutOfTags`: no free tag. Unchanged on error.
            /// Successful tag values may be reused after `freeOne`.
            pub fn allocOne(self: *Self) Error!Tag {
                const before = self.allocated_count;
                std.debug.assert(before <= tag_capacity);

                const idx = findFirstFree(self.words[0..], tag_capacity) orelse
                    return error.OutOfTags;
                setBit(self.words[0..], idx);
                self.allocated_count += 1;

                std.debug.assert(self.allocated_count == before + 1);
                return Tag.fromInt(@intCast(idx));
            }

            /// `error.OutOfBounds`: `tag.raw() >= capacity()`.
            /// `error.AlreadyAllocated`: the tag is already reserved. Unchanged on error.
            pub fn reserveOne(self: *Self, tag: Tag) Error!void {
                const before = self.allocated_count;
                std.debug.assert(before <= tag_capacity);

                const idx = boundedIndex(Int, tag, tag_capacity) orelse
                    return error.OutOfBounds;
                if (testBit(self.words[0..], idx)) return error.AlreadyAllocated;
                setBit(self.words[0..], idx);
                self.allocated_count += 1;

                std.debug.assert(self.allocated_count == before + 1);
            }

            /// `error.OutOfBounds`: `tag.raw() >= capacity()`.
            /// `error.NotAllocated`: the tag is already free. Unchanged on error.
            /// No destructor is invoked for external resources keyed by the tag.
            pub fn freeOne(self: *Self, tag: Tag) Error!void {
                const before = self.allocated_count;
                std.debug.assert(before <= tag_capacity);

                const idx = boundedIndex(Int, tag, tag_capacity) orelse
                    return error.OutOfBounds;
                if (!testBit(self.words[0..], idx)) return error.NotAllocated;
                clearBit(self.words[0..], idx);
                self.allocated_count -= 1;

                std.debug.assert(self.allocated_count == before - 1);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                for (&self.words) |*w| w.* = 0;
                self.allocated_count = 0;
            }

            pub fn isValid(self: *const Self) bool {
                return checkInvariants(
                    self.words[0..],
                    tag_capacity,
                    self.allocated_count,
                    null,
                );
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
            }
        };
    }

    /// Borrowed-storage tag allocator. `wrap` validates and clears the
    /// caller-provided word slice before returning an empty allocator.
    pub fn Bounded(
        comptime DomainT: type,
        comptime IntT: type,
    ) type {
        const TagT = TagFactory(DomainT, IntT);
        return struct {
            words: []Word,
            tag_capacity: usize,
            allocated_count: usize,

            const Self = @This();

            pub const Domain = DomainT;
            pub const Int = IntT;
            pub const Tag = TagT;

            pub const Word = u64;
            pub const word_bits = @bitSizeOf(Word);

            pub const Error = error{
                OutOfTags,
                OutOfBounds,
                AlreadyAllocated,
                NotAllocated,
            };

            /// Borrow `words` and present the first `tag_capacity` tags.
            /// Rejects `tag_capacity > words.len * word_bits` and
            /// `tag_capacity > std.math.maxInt(Int) + 1` with
            /// `error.OutOfBounds`, leaving `words` unchanged.
            pub fn wrap(words: []Word, tag_capacity: usize) Error!Self {
                // No-mutation-on-error: validate fully before touching.
                if (!fitsInIntCapacity(Int, tag_capacity)) return error.OutOfBounds;
                if (wordCountFor(tag_capacity) > words.len) return error.OutOfBounds;

                for (words) |*w| w.* = 0;
                return .{
                    .words = words,
                    .tag_capacity = tag_capacity,
                    .allocated_count = 0,
                };
            }

            pub fn capacity(self: *const Self) usize {
                return self.tag_capacity;
            }

            pub fn allocated(self: *const Self) usize {
                return self.allocated_count;
            }

            pub fn remaining(self: *const Self) usize {
                return self.tag_capacity - self.allocated_count;
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.allocated_count == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.allocated_count == self.tag_capacity;
            }

            pub fn isAllocated(self: *const Self, tag: Tag) bool {
                return queryBit(self.words, self.tag_capacity, tag);
            }

            pub fn isFree(self: *const Self, tag: Tag) bool {
                const idx = boundedIndex(Int, tag, self.tag_capacity) orelse return false;
                return !testBit(self.words, idx);
            }

            /// `error.OutOfTags`: no free tag. Unchanged on error.
            /// Successful tag values may be reused after `freeOne`.
            pub fn allocOne(self: *Self) Error!Tag {
                const before = self.allocated_count;
                std.debug.assert(before <= self.tag_capacity);

                const idx = findFirstFree(self.words, self.tag_capacity) orelse
                    return error.OutOfTags;
                setBit(self.words, idx);
                self.allocated_count += 1;

                std.debug.assert(self.allocated_count == before + 1);
                return Tag.fromInt(@intCast(idx));
            }

            /// `error.OutOfBounds`: `tag.raw() >= capacity()`.
            /// `error.AlreadyAllocated`: the tag is already reserved. Unchanged on error.
            pub fn reserveOne(self: *Self, tag: Tag) Error!void {
                const before = self.allocated_count;
                std.debug.assert(before <= self.tag_capacity);

                const idx = boundedIndex(Int, tag, self.tag_capacity) orelse
                    return error.OutOfBounds;
                if (testBit(self.words, idx)) return error.AlreadyAllocated;
                setBit(self.words, idx);
                self.allocated_count += 1;

                std.debug.assert(self.allocated_count == before + 1);
            }

            /// `error.OutOfBounds`: `tag.raw() >= capacity()`.
            /// `error.NotAllocated`: the tag is already free. Unchanged on error.
            /// No destructor is invoked for external resources keyed by the tag.
            pub fn freeOne(self: *Self, tag: Tag) Error!void {
                const before = self.allocated_count;
                std.debug.assert(before <= self.tag_capacity);

                const idx = boundedIndex(Int, tag, self.tag_capacity) orelse
                    return error.OutOfBounds;
                if (!testBit(self.words, idx)) return error.NotAllocated;
                clearBit(self.words, idx);
                self.allocated_count -= 1;

                std.debug.assert(self.allocated_count == before - 1);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                for (self.words) |*w| w.* = 0;
                self.allocated_count = 0;
            }

            pub fn isValid(self: *const Self) bool {
                if (!fitsInIntCapacity(Int, self.tag_capacity)) return false;
                if (wordCountFor(self.tag_capacity) > self.words.len) return false;

                return checkInvariants(
                    self.words,
                    self.tag_capacity,
                    self.allocated_count,
                    self.words.len,
                );
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
            }
        };
    }
};

const BitmapWord = u64;
const BitmapWordBits: usize = @bitSizeOf(BitmapWord);

fn wordCountFor(tag_capacity: usize) usize {
    return word.count(BitmapWord, tag_capacity);
}

fn lastMaskFor(tag_capacity: usize) BitmapWord {
    return word.lastMask(BitmapWord, tag_capacity);
}

fn setBit(words: []BitmapWord, index: usize) void {
    word.set(BitmapWord, words, index);
}

fn clearBit(words: []BitmapWord, index: usize) void {
    word.clear(BitmapWord, words, index);
}

fn testBit(words: []const BitmapWord, index: usize) bool {
    return word.isSet(BitmapWord, words, index);
}

/// Map a `Tag` to its in-range word-bit index, or null when its raw value
/// is at or past `tag_capacity` (or exceeds `usize`).
fn boundedIndex(comptime IntT: type, tag: anytype, tag_capacity: usize) ?usize {
    const raw_value: IntT = tag.raw();
    const idx = std.math.cast(usize, raw_value) orelse return null;
    if (idx >= tag_capacity) return null;
    return idx;
}

fn queryBit(words: []const BitmapWord, tag_capacity: usize, tag: anytype) bool {
    const idx = boundedIndex(@TypeOf(tag).Int, tag, tag_capacity) orelse return false;
    return testBit(words, idx);
}

/// Lowest-free-index forward scan. Unused high bits in the final logical
/// word are OR'd as occupied so they never produce a candidate.
fn findFirstFree(words: []const BitmapWord, tag_capacity: usize) ?usize {
    if (tag_capacity == 0) return null;
    const word_count = wordCountFor(tag_capacity);
    const last_mask = lastMaskFor(tag_capacity);
    var word_index: usize = 0;
    while (word_index < word_count) : (word_index += 1) {
        var w = words[word_index];
        if (word_index == word_count - 1 and last_mask != ~@as(BitmapWord, 0)) {
            w |= ~last_mask;
        }
        if (w != ~@as(BitmapWord, 0)) {
            const inverted = ~w;
            const bit: usize = @ctz(inverted);
            return word_index * BitmapWordBits + bit;
        }
    }
    return null;
}

fn fitsInIntCapacity(comptime IntT: type, tag_capacity: usize) bool {
    const max_tags: comptime_int = @as(comptime_int, std.math.maxInt(IntT)) + 1;
    if (max_tags >= @as(comptime_int, std.math.maxInt(usize)) + 1) return true;
    return tag_capacity <= @as(usize, max_tags);
}

/// Shared invariant check:
/// - `allocated_count <= tag_capacity`.
/// - Popcount of the logical region equals `allocated_count`.
/// - Unused high bits in the final logical word are zero.
/// - Words beyond the logical region (Bounded only) are zero.
fn checkInvariants(
    words: []const BitmapWord,
    tag_capacity: usize,
    allocated_count: usize,
    bounded_words_len: ?usize,
) bool {
    if (allocated_count > tag_capacity) return false;
    const word_count = wordCountFor(tag_capacity);
    const last_mask = lastMaskFor(tag_capacity);

    var total: usize = 0;
    var word_index: usize = 0;
    while (word_index < word_count) : (word_index += 1) {
        const w = words[word_index];
        if (word_index == word_count - 1 and last_mask != ~@as(BitmapWord, 0)) {
            if ((w & ~last_mask) != 0) return false;
            total += @popCount(w & last_mask);
        } else {
            total += @popCount(w);
        }
    }
    if (total != allocated_count) return false;

    if (bounded_words_len) |total_words| {
        var tag_index: usize = word_count;
        while (tag_index < total_words) : (tag_index += 1) {
            if (words[tag_index] != 0) return false;
        }
    }
    return true;
}
