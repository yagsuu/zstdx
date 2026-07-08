//! Buddy allocator over caller-provided backing. Spec: docs/specs/mem/buddy-allocator.md.

const std = @import("std");

const debug = @import("../core/debug.zig");
const allocation = @import("../algo/allocation.zig");
const word = @import("../bits/word.zig");

const Buddy = allocation.Buddy;
const BuddyWord = u64;
const RangeUsize = @import("../core/range.zig").Range(usize);
const Shift = std.math.Log2Int(BuddyWord);

const buddy_word_bits = @bitSizeOf(BuddyWord);

/// Power-of-two unit allocator over caller-provided bitmap words. Both
/// variants share a per-order bit-per-slot layout, deterministic lowest-index
/// split placement, and eager on-`free` coalescing.
pub const BuddyAllocator = struct {
    /// Inline-storage buddy allocator. Both a default struct literal and
    /// `init()` yield an allocator whose free state covers
    /// `[0, unit_capacity)` via the standard buddy decomposition.
    pub fn Static(comptime unit_capacity: usize, comptime order_count: u8) type {
        if (order_count == 0) {
            @compileError("BuddyAllocator.Static: order_count must be at least 1");
        }
        if (order_count > 32) {
            @compileError("BuddyAllocator.Static: order_count must be at most 32");
        }
        if (unit_capacity == 0) {
            @compileError("BuddyAllocator.Static: unit_capacity must be at least 1");
        }
        if (unit_capacity > (std.math.maxInt(usize) >> (order_count - 1))) {
            @compileError(
                "BuddyAllocator.Static: unit_capacity exceeds (maxInt(usize) >> (order_count - 1))",
            );
        }

        const wc = requiredWordCount(unit_capacity, order_count);
        const initial: [wc]BuddyWord = comptime blk: {
            @setEvalBranchQuota(100_000);
            var arr = [_]BuddyWord{0} ** wc;
            installInitialDecomposition(arr[0..], unit_capacity, order_count);
            break :blk arr;
        };

        return struct {
            words: [word_count]Word = initial,

            const Self = @This();

            pub const Word = u64;
            pub const word_bits = @bitSizeOf(Word);
            pub const Block = Buddy.Block;
            pub const Range = RangeUsize;
            pub const Error = BuddyAllocator.Bounded.Error;

            pub const unit_capacity_const: usize = unit_capacity;
            pub const order_count_const: u8 = order_count;
            pub const max_order_const: u8 = order_count - 1;
            pub const word_count: usize = wc;

            /// Allocator whose free state covers `[0, unit_capacity)`.
            pub fn init() Self {
                return .{};
            }

            /// Restore the initial fully-free decomposition without
            /// releasing backing storage.
            pub fn clearRetainingCapacity(self: *Self) void {
                self.words = initial;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return unit_capacity;
            }

            pub fn orderCount(self: *const Self) u8 {
                _ = self;
                return order_count;
            }

            pub fn maxOrder(self: *const Self) u8 {
                _ = self;
                return order_count - 1;
            }

            pub fn allocatedUnits(self: *const Self) usize {
                return unit_capacity - freeUnitsImpl(self.words[0..], unit_capacity, order_count);
            }

            pub fn remainingUnits(self: *const Self) usize {
                return freeUnitsImpl(self.words[0..], unit_capacity, order_count);
            }

            /// `order` selects an exact block size; higher blocks may split.
            /// `error.InvalidOrder`: `order >= orderCount()`.
            /// `error.OutOfMemory`: no fitting free block. Error leaves allocator unchanged.
            pub fn alloc(self: *Self, order: u8) Error!Block {
                return allocImpl(self.words[0..], unit_capacity, order_count, order);
            }

            /// `block` must match allocator alignment, range, and allocated state.
            /// Free buddies coalesce transitively.
            /// `error.InvalidOrder`, `error.InvalidRequest`, or `error.NotAllocated`.
            /// Error leaves allocator unchanged. Checks trap double-free and misalignment.
            pub fn free(self: *Self, block: Block) Error!void {
                return freeImpl(self.words[0..], unit_capacity, order_count, block);
            }

            /// `error.InvalidRequest`: `range` is invalid.
            /// `error.OutOfBounds`: `range.end > capacity()`.
            /// `error.AlreadyAllocated`: any unit is already allocated.
            /// Empty in-bounds range is a no-op. Error leaves allocator unchanged.
            /// Reserving splits containing blocks down to order 0.
            pub fn reserve(self: *Self, range: Range) Error!void {
                return reserveImpl(self.words[0..], unit_capacity, order_count, range);
            }

            pub fn isFreeBlock(self: *const Self, block: Block) bool {
                return isFreeBlockImpl(self.words[0..], unit_capacity, order_count, block);
            }

            pub fn isValid(self: *const Self) bool {
                return checkValid(self.words[0..], unit_capacity, order_count);
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
            }
        };
    }

    /// Runtime-capacity buddy allocator over caller-owned words. `words`
    /// must live for the allocator's lifetime; the allocator borrows them
    /// and never releases storage.
    pub const Bounded = struct {
        words: []Word,
        unit_capacity: usize,
        order_count: u8,

        pub const Word = u64;
        pub const word_bits = @bitSizeOf(Word);
        pub const Block = Buddy.Block;
        pub const Range = RangeUsize;

        /// `OutOfMemory`: no free block of the requested order exists.
        /// `OutOfBounds`: `reserve`'s range extends past `unit_capacity`.
        /// `InvalidOrder`: `order >= order_count`.
        /// `InvalidRequest`: invalid range, invalid `free` block, or invalid `wrap` input.
        /// `AlreadyAllocated`: `reserve` overlaps an allocated unit.
        /// `NotAllocated`: `free` names a currently free block.
        /// `Overflow`: reserved for future `usize`-boundary arithmetic.
        pub const Error = error{
            OutOfMemory,
            OutOfBounds,
            InvalidOrder,
            InvalidRequest,
            AlreadyAllocated,
            NotAllocated,
            Overflow,
        };

        /// Borrowed words are zeroed only on success.
        /// `error.InvalidRequest`: parameters violate `Static(...)` constraints
        /// or `words.len` is too small. Error leaves borrowed storage unchanged.
        pub fn wrap(words: []Word, unit_capacity: usize, order_count: u8) Error!Bounded {
            if (order_count == 0) return error.InvalidRequest;
            if (order_count > 32) return error.InvalidRequest;
            if (unit_capacity == 0) return error.InvalidRequest;
            if (unit_capacity > std.math.shr(usize, std.math.maxInt(usize), order_count - 1)) {
                return error.InvalidRequest;
            }
            if (words.len < requiredWordCount(unit_capacity, order_count)) {
                return error.InvalidRequest;
            }

            installInitialDecomposition(words, unit_capacity, order_count);
            return .{ .words = words, .unit_capacity = unit_capacity, .order_count = order_count };
        }

        pub fn clearRetainingCapacity(self: *Bounded) void {
            installInitialDecomposition(self.words, self.unit_capacity, self.order_count);
        }

        pub fn capacity(self: *const Bounded) usize {
            return self.unit_capacity;
        }

        pub fn orderCount(self: *const Bounded) u8 {
            return self.order_count;
        }

        pub fn maxOrder(self: *const Bounded) u8 {
            return self.order_count - 1;
        }

        pub fn allocatedUnits(self: *const Bounded) usize {
            return self.unit_capacity - freeUnitsImpl(self.words, self.unit_capacity, self.order_count);
        }

        pub fn remainingUnits(self: *const Bounded) usize {
            return freeUnitsImpl(self.words, self.unit_capacity, self.order_count);
        }

        /// `order` selects an exact block size; higher blocks may split.
        /// `error.InvalidOrder`: `order >= orderCount()`.
        /// `error.OutOfMemory`: no fitting free block. Error leaves allocator unchanged.
        pub fn alloc(self: *Bounded, order: u8) Error!Block {
            return allocImpl(self.words, self.unit_capacity, self.order_count, order);
        }

        /// `block` must match allocator alignment, range, and allocated state.
        /// Free buddies coalesce transitively.
        /// `error.InvalidOrder`, `error.InvalidRequest`, or `error.NotAllocated`.
        /// Error leaves allocator unchanged. Checks trap double-free and misalignment.
        pub fn free(self: *Bounded, block: Block) Error!void {
            return freeImpl(self.words, self.unit_capacity, self.order_count, block);
        }

        /// `error.InvalidRequest`: `range` is invalid.
        /// `error.OutOfBounds`: `range.end > capacity()`.
        /// `error.AlreadyAllocated`: any unit is already allocated.
        /// Empty in-bounds range is a no-op. Error leaves allocator unchanged.
        /// Reserving splits containing blocks down to order 0.
        pub fn reserve(self: *Bounded, range: Range) Error!void {
            return reserveImpl(self.words, self.unit_capacity, self.order_count, range);
        }

        pub fn isFreeBlock(self: *const Bounded, block: Block) bool {
            return isFreeBlockImpl(self.words, self.unit_capacity, self.order_count, block);
        }

        pub fn isValid(self: *const Bounded) bool {
            if (self.order_count == 0) return false;
            if (self.order_count > 32) return false;
            if (self.unit_capacity == 0) return false;
            if (self.unit_capacity > std.math.shr(usize, std.math.maxInt(usize), self.order_count - 1)) {
                return false;
            }
            if (self.words.len < requiredWordCount(self.unit_capacity, self.order_count)) {
                return false;
            }
            return checkValid(self.words, self.unit_capacity, self.order_count);
        }

        pub fn assertValid(self: *const Bounded) void {
            std.debug.assert(self.isValid());
        }
    };
};

// Shared implementation used by both Static and Bounded variants.

const BuddyBlock = Buddy.Block;
const BuddyError = BuddyAllocator.Bounded.Error;

fn ceilDivUsize(a: usize, b: usize) usize {
    return @divFloor(a, b) + @intFromBool(a % b != 0);
}

/// Number of aligned start-slots at `order` (`ceilDiv(unit_capacity, 1 << order)`).
fn slotsForOrder(unit_capacity: usize, order: u8) usize {
    const size = @as(usize, 1) << @as(Shift, @intCast(order));
    return ceilDivUsize(unit_capacity, size);
}

/// Number of slots at `order` whose block fits entirely in `[0, unit_capacity)`.
/// Bits above this count are always zero.
fn validSlotsFor(unit_capacity: usize, order: u8) usize {
    const size = @as(usize, 1) << @as(Shift, @intCast(order));
    return @divFloor(unit_capacity, size);
}

fn wordsForOrder(unit_capacity: usize, order: u8) usize {
    return word.count(BuddyWord, slotsForOrder(unit_capacity, order));
}

fn orderWordOffset(unit_capacity: usize, order: u8) usize {
    var offset: usize = 0;
    var k: u8 = 0;
    while (k < order) : (k += 1) {
        offset += wordsForOrder(unit_capacity, k);
    }
    return offset;
}

/// Sum over `k in [0, order_count)` of `wordsForOrder(unit_capacity, k)`.
fn requiredWordCount(unit_capacity: usize, order_count: u8) usize {
    return orderWordOffset(unit_capacity, order_count);
}

fn bitIsSet(words: []const BuddyWord, unit_capacity: usize, order: u8, slot: usize) bool {
    const off = orderWordOffset(unit_capacity, order);
    return word.isSet(BuddyWord, words[off..], slot);
}

fn setBit(words: []BuddyWord, unit_capacity: usize, order: u8, slot: usize) void {
    const off = orderWordOffset(unit_capacity, order);
    word.set(BuddyWord, words[off..], slot);
}

fn clearBit(words: []BuddyWord, unit_capacity: usize, order: u8, slot: usize) void {
    const off = orderWordOffset(unit_capacity, order);
    word.clear(BuddyWord, words[off..], slot);
}

fn findFirstFreeAtOrder(words: []const BuddyWord, unit_capacity: usize, order: u8) ?usize {
    const off = orderWordOffset(unit_capacity, order);
    const wc = wordsForOrder(unit_capacity, order);
    var wi: usize = 0;
    while (wi < wc) : (wi += 1) {
        const w = words[off + wi];
        if (w != 0) {
            const bit = @ctz(w);
            const slot = wi * buddy_word_bits + bit;
            std.debug.assert(slot < validSlotsFor(unit_capacity, order));
            return slot;
        }
    }
    return null;
}

fn installInitialDecomposition(words: []BuddyWord, unit_capacity: usize, order_count: u8) void {
    for (words) |*w| w.* = 0;
    if (unit_capacity == 0) return;

    var cursor: usize = 0;
    var k: u8 = order_count - 1;
    while (cursor < unit_capacity) {
        while (k > 0 and cursor + (@as(usize, 1) << @as(Shift, @intCast(k))) > unit_capacity) {
            k -= 1;
        }

        const size = @as(usize, 1) << @as(Shift, @intCast(k));

        std.debug.assert(cursor + size <= unit_capacity);
        std.debug.assert(cursor % size == 0);

        setBit(words, unit_capacity, k, cursor >> @as(Shift, @intCast(k)));
        cursor += size;
    }
}

fn freeUnitsImpl(words: []const BuddyWord, unit_capacity: usize, order_count: u8) usize {
    var total: usize = 0;
    var k: u8 = 0;
    while (k < order_count) : (k += 1) {
        const off = orderWordOffset(unit_capacity, k);
        const wc = wordsForOrder(unit_capacity, k);
        var pop: usize = 0;
        for (words[off..][0..wc]) |w| pop += @popCount(w);
        const size = @as(usize, 1) << @as(Shift, @intCast(k));
        total += pop * size;
    }
    return total;
}

fn isFreeBlockImpl(
    words: []const BuddyWord,
    unit_capacity: usize,
    order_count: u8,
    block: BuddyBlock,
) bool {
    if (block.order >= order_count) return false;
    const size = @as(usize, 1) << @as(Shift, @intCast(block.order));
    if (block.start % size != 0) return false;
    const end = std.math.add(usize, block.start, size) catch return false;
    if (end > unit_capacity) return false;
    return bitIsSet(words, unit_capacity, block.order, block.start >> @as(Shift, @intCast(block.order)));
}

fn allocImpl(
    words: []BuddyWord,
    unit_capacity: usize,
    order_count: u8,
    order: u8,
) BuddyError!BuddyBlock {
    if (order >= order_count) return error.InvalidOrder;

    // Find the lowest-start free block whose order is >= target order.
    // Break ties on start by preferring the lowest order (shallowest
    // split). Scans every order and keeps the best candidate.
    var best_start: usize = std.math.maxInt(usize);
    var best_order: u8 = 0;
    var found = false;
    var k: u8 = order;
    while (k < order_count) : (k += 1) {
        const slot = findFirstFreeAtOrder(words, unit_capacity, k) orelse continue;
        const start = slot << @as(Shift, @intCast(k));
        const beats_start = start < best_start;
        const beats_order = start == best_start and k < best_order;
        const should_replace = !found or beats_start or beats_order;
        if (should_replace) {
            best_start = start;
            best_order = k;
            found = true;
        }
    }
    if (!found) return error.OutOfMemory;

    const source_slot = best_start >> @as(Shift, @intCast(best_order));
    clearBit(words, unit_capacity, best_order, source_slot);
    var current: BuddyBlock = .{ .start = best_start, .order = best_order };
    while (current.order > order) {
        std.debug.assert(current.order > 0);
        const pair = Buddy.split(current) catch unreachable;
        const right = pair[1];
        setBit(
            words,
            unit_capacity,
            right.order,
            right.start >> @as(Shift, @intCast(right.order)),
        );
        current = pair[0];
    }

    if (debug.checksEnabled(.build_mode)) {
        const slot = current.start >> @as(Shift, @intCast(current.order));
        std.debug.assert(!bitIsSet(words, unit_capacity, current.order, slot));
    }
    return current;
}

fn freeImpl(
    words: []BuddyWord,
    unit_capacity: usize,
    order_count: u8,
    block: BuddyBlock,
) BuddyError!void {
    if (block.order >= order_count) return error.InvalidOrder;

    const size = @as(usize, 1) << @as(Shift, @intCast(block.order));
    const aligned = block.start % size == 0;
    if (debug.checksEnabled(.build_mode)) std.debug.assert(aligned);
    if (!aligned) return error.InvalidRequest;

    const end = std.math.add(usize, block.start, size) catch return error.InvalidRequest;
    if (end > unit_capacity) return error.InvalidRequest;

    const slot = block.start >> @as(Shift, @intCast(block.order));
    if (bitIsSet(words, unit_capacity, block.order, slot)) {
        if (debug.checksEnabled(.build_mode)) std.debug.assert(false);
        return error.NotAllocated;
    }

    var current = block;
    while (current.order + 1 < order_count) {
        const buddy = Buddy.buddyOf(current) catch break;
        const buddy_size = @as(usize, 1) << @as(Shift, @intCast(buddy.order));
        const buddy_end = std.math.add(usize, buddy.start, buddy_size) catch break;
        if (buddy_end > unit_capacity) break;

        const buddy_slot = buddy.start >> @as(Shift, @intCast(buddy.order));
        if (!bitIsSet(words, unit_capacity, buddy.order, buddy_slot)) break;

        clearBit(words, unit_capacity, buddy.order, buddy_slot);
        current = Buddy.parentOf(current) catch break;
    }

    setBit(
        words,
        unit_capacity,
        current.order,
        current.start >> @as(Shift, @intCast(current.order)),
    );

    if (debug.checksEnabled(.build_mode)) {
        std.debug.assert(!hasBothBuddiesFree(words, unit_capacity, order_count));
    }
}

fn reserveImpl(
    words: []BuddyWord,
    unit_capacity: usize,
    order_count: u8,
    range: RangeUsize,
) BuddyError!void {
    if (!range.isValid()) return error.InvalidRequest;
    if (range.isEmpty()) {
        if (range.start > unit_capacity) return error.OutOfBounds;
        return;
    }
    if (range.end > unit_capacity) return error.OutOfBounds;

    var probe: usize = range.start;
    while (probe < range.end) : (probe += 1) {
        if (containingFreeOrder(words, unit_capacity, order_count, probe) == null) {
            return error.AlreadyAllocated;
        }
    }

    var u: usize = range.start;
    while (u < range.end) : (u += 1) {
        const k = containingFreeOrder(words, unit_capacity, order_count, u).?;
        const size_k = @as(usize, 1) << @as(Shift, @intCast(k));
        const block_start = @divFloor(u, size_k) * size_k;

        clearBit(words, unit_capacity, k, block_start >> @as(Shift, @intCast(k)));
        var current: BuddyBlock = .{ .start = block_start, .order = k };
        while (current.order > 0) {
            std.debug.assert(current.order > 0);
            const pair = Buddy.split(current) catch unreachable;
            const left = pair[0];
            const right = pair[1];
            const left_end = left.start + (@as(usize, 1) << @as(Shift, @intCast(left.order)));
            if (u < left_end) {
                setBit(
                    words,
                    unit_capacity,
                    right.order,
                    right.start >> @as(Shift, @intCast(right.order)),
                );
                current = left;
            } else {
                setBit(
                    words,
                    unit_capacity,
                    left.order,
                    left.start >> @as(Shift, @intCast(left.order)),
                );
                current = right;
            }
        }

        std.debug.assert(current.order == 0);
        std.debug.assert(current.start == u);
    }
}

fn containingFreeOrder(
    words: []const BuddyWord,
    unit_capacity: usize,
    order_count: u8,
    unit: usize,
) ?u8 {
    var k: u8 = 0;
    while (k < order_count) : (k += 1) {
        const size_k = @as(usize, 1) << @as(Shift, @intCast(k));
        const slot = @divFloor(unit, size_k);
        if (slot >= validSlotsFor(unit_capacity, k)) return null;
        if (bitIsSet(words, unit_capacity, k, slot)) return k;
    }
    return null;
}

fn hasBothBuddiesFree(words: []const BuddyWord, unit_capacity: usize, order_count: u8) bool {
    if (order_count == 0) return false;
    var k: u8 = 0;
    while (k + 1 < order_count) : (k += 1) {
        const valid = validSlotsFor(unit_capacity, k);
        var pair: usize = 0;
        while (pair * 2 + 1 < valid) : (pair += 1) {
            const left = pair * 2;
            const right = left + 1;
            if (bitIsSet(words, unit_capacity, k, left) and
                bitIsSet(words, unit_capacity, k, right))
            {
                return true;
            }
        }
    }
    return false;
}

fn hasUnusedHighBits(words: []const BuddyWord, unit_capacity: usize, order_count: u8) bool {
    var k: u8 = 0;
    while (k < order_count) : (k += 1) {
        const valid = validSlotsFor(unit_capacity, k);
        const off = orderWordOffset(unit_capacity, k);
        const wc = wordsForOrder(unit_capacity, k);

        var wi: usize = 0;
        while (wi < wc) : (wi += 1) {
            const base = wi * buddy_word_bits;
            const w = words[off + wi];
            if (base >= valid) {
                if (w != 0) return true;
                continue;
            }
            const in_word = valid - base;
            if (in_word >= buddy_word_bits) continue;
            const high_mask = ~((@as(BuddyWord, 1) << @as(Shift, @intCast(in_word))) - 1);
            if ((w & high_mask) != 0) return true;
        }
    }
    return false;
}

fn checkValid(words: []const BuddyWord, unit_capacity: usize, order_count: u8) bool {
    if (hasUnusedHighBits(words, unit_capacity, order_count)) return false;
    if (hasBothBuddiesFree(words, unit_capacity, order_count)) return false;

    const free_units = freeUnitsImpl(words, unit_capacity, order_count);
    if (free_units > unit_capacity) return false;
    return true;
}
