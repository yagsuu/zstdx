//! Buddy allocator over fixed bitmap storage.
//! See `docs/specs/mem/alloc/buddy.md`.

const std = @import("std");

const debug = @import("core").debug;
const buddy = @import("algo").alloc.buddy;
const Bitmap = @import("bits").Set(u64);

/// Uses lowest-index splitting and eager coalescing.
pub const BuddyAllocator = struct {
    /// Owns inline storage initialized to the standard buddy decomposition.
    pub fn Static(comptime unit_capacity: usize, comptime order_count: u8) type {
        comptime requireStaticShape(unit_capacity, order_count);

        const wc = requiredWordCount(unit_capacity, order_count);
        const initial = initialBitmap(wc, unit_capacity, order_count);

        return struct {
            bitmap: Bitmap.Static(wc * Bitmap.Word.width) = initial,

            const Self = @This();

            pub const Word = u64;
            pub const Block = buddy.Block;
            pub const Range = RangeUsize;
            pub const Error = BuddyAllocator.Bounded.Error;

            pub const unit_capacity_const: usize = unit_capacity;
            pub const order_count_const: u8 = order_count;
            pub const max_order_const: u8 = order_count - 1;
            pub const word_count: usize = wc;
            pub const word_bits = Bitmap.Word.width;

            pub fn init() Self {
                return .{};
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
                return unit_capacity - freeUnitsImpl(&self.bitmap, unit_capacity, order_count);
            }

            pub fn remainingUnits(self: *const Self) usize {
                return freeUnitsImpl(&self.bitmap, unit_capacity, order_count);
            }

            pub fn isFreeBlock(self: *const Self, block: Block) bool {
                return isFreeBlockImpl(&self.bitmap, unit_capacity, order_count, block);
            }

            /// Splits higher-order blocks when necessary.
            /// Errors leave allocator state unchanged.
            pub fn alloc(self: *Self, order: u8) Error!Block {
                return allocImpl(&self.bitmap, unit_capacity, order_count, order);
            }

            /// Requires an allocated, aligned block.
            /// Coalesces free buddies; errors leave allocator state unchanged.
            pub fn free(self: *Self, block: Block) Error!void {
                return freeImpl(&self.bitmap, unit_capacity, order_count, block);
            }

            /// Requires a valid `range`.
            /// An empty in-bounds range is a no-op; errors do not mutate.
            /// Splits containing blocks to order 0.
            pub fn reserve(self: *Self, range: Range) Error!void {
                return reserveImpl(&self.bitmap, unit_capacity, order_count, range);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.bitmap = initial;
            }

            pub fn isValid(self: *const Self) bool {
                return checkValid(&self.bitmap, unit_capacity, order_count);
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
            }
        };
    }

    /// Borrows `words`; they must outlive the allocator.
    pub const Bounded = struct {
        bitmap: Bitmap.Bounded,
        unit_capacity: usize,
        order_count: u8,

        pub const Word = u64;
        pub const word_bits = Bitmap.Word.width;
        pub const Block = buddy.Block;
        pub const Range = RangeUsize;

        /// `OutOfMemory`: no free block of the requested order exists.
        /// `OutOfBounds`: `reserve`'s range extends past `unit_capacity`.
        /// `InvalidOrder`: `order >= order_count`.
        /// `InvalidRequest`: invalid range, invalid `free` block, or invalid `wrap` input.
        /// `AlreadyAllocated`: `reserve` overlaps an allocated unit.
        /// `NotAllocated`: `free` names a currently free block.
        pub const Error = error{
            OutOfMemory,
            OutOfBounds,
            InvalidOrder,
            InvalidRequest,
            AlreadyAllocated,
            NotAllocated,
        };

        /// Initializes `words` only after validating all arguments.
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

            const bit_capacity = std.math.mul(
                usize,
                requiredWordCount(unit_capacity, order_count),
                Bitmap.Word.width,
            ) catch return error.InvalidRequest;
            var bitmap = Bitmap.Bounded.wrap(words, bit_capacity) catch return error.InvalidRequest;
            installInitialDecomposition(&bitmap, unit_capacity, order_count);
            return .{ .bitmap = bitmap, .unit_capacity = unit_capacity, .order_count = order_count };
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
            return self.unit_capacity - freeUnitsImpl(&self.bitmap, self.unit_capacity, self.order_count);
        }

        pub fn remainingUnits(self: *const Bounded) usize {
            return freeUnitsImpl(&self.bitmap, self.unit_capacity, self.order_count);
        }

        pub fn isFreeBlock(self: *const Bounded, block: Block) bool {
            return isFreeBlockImpl(&self.bitmap, self.unit_capacity, self.order_count, block);
        }

        /// Splits higher-order blocks when necessary.
        /// Errors leave allocator state unchanged.
        pub fn alloc(self: *Bounded, order: u8) Error!Block {
            return allocImpl(&self.bitmap, self.unit_capacity, self.order_count, order);
        }

        /// Requires an allocated, aligned block.
        /// Coalesces free buddies; errors leave allocator state unchanged.
        pub fn free(self: *Bounded, block: Block) Error!void {
            return freeImpl(&self.bitmap, self.unit_capacity, self.order_count, block);
        }

        /// Requires a valid `range`.
        /// An empty in-bounds range is a no-op; errors do not mutate.
        /// Splits containing blocks to order 0.
        pub fn reserve(self: *Bounded, range: Range) Error!void {
            return reserveImpl(&self.bitmap, self.unit_capacity, self.order_count, range);
        }

        pub fn clearRetainingCapacity(self: *Bounded) void {
            self.bitmap.clearRetainingCapacity();
            installInitialDecomposition(&self.bitmap, self.unit_capacity, self.order_count);
        }

        pub fn isValid(self: *const Bounded) bool {
            if (self.order_count == 0) return false;
            if (self.order_count > 32) return false;
            if (self.unit_capacity == 0) return false;
            if (self.unit_capacity > std.math.shr(usize, std.math.maxInt(usize), self.order_count - 1)) {
                return false;
            }
            if (self.bitmap.items.len < requiredWordCount(self.unit_capacity, self.order_count)) {
                return false;
            }
            const bit_capacity = std.math.mul(
                usize,
                requiredWordCount(self.unit_capacity, self.order_count),
                Bitmap.Word.width,
            ) catch return false;
            if (self.bitmap.limit != bit_capacity) {
                return false;
            }
            return checkValid(&self.bitmap, self.unit_capacity, self.order_count);
        }

        pub fn assertValid(self: *const Bounded) void {
            std.debug.assert(self.isValid());
        }
    };
};

const BuddyBlock = buddy.Block;
const BuddyWord = u64;
const RangeUsize = @import("core").Range(usize);
const Shift = std.math.Log2Int(usize);

fn requireStaticShape(comptime unit_capacity: usize, comptime order_count: u8) void {
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
}

fn initialBitmap(
    comptime word_count: usize,
    comptime unit_capacity: usize,
    comptime order_count: u8,
) Bitmap.Static(word_count * Bitmap.Word.width) {
    @setEvalBranchQuota(100_000);
    var bitmap = Bitmap.Static(word_count * Bitmap.Word.width).init();
    installInitialDecomposition(&bitmap, unit_capacity, order_count);
    return bitmap;
}

const BuddyError = BuddyAllocator.Bounded.Error;

/// Aligned start slots at `order`, rounded up.
fn slotsForOrder(unit_capacity: usize, order: u8) usize {
    const size = @as(usize, 1) << @as(Shift, @intCast(order));
    return @divFloor(unit_capacity, size) + @intFromBool(unit_capacity % size != 0);
}

/// Slots at `order` whose blocks fit within `[0, unit_capacity)`.
fn validSlotsFor(unit_capacity: usize, order: u8) usize {
    const size = @as(usize, 1) << @as(Shift, @intCast(order));
    return @divFloor(unit_capacity, size);
}

fn wordsForOrder(unit_capacity: usize, order: u8) usize {
    const slots = slotsForOrder(unit_capacity, order);
    return slots / Bitmap.Word.width + @intFromBool(slots % Bitmap.Word.width != 0);
}

fn orderWordOffset(unit_capacity: usize, order: u8) usize {
    var offset: usize = 0;
    var k: u8 = 0;
    while (k < order) : (k += 1) {
        offset += wordsForOrder(unit_capacity, k);
    }
    return offset;
}

fn requiredWordCount(unit_capacity: usize, order_count: u8) usize {
    return orderWordOffset(unit_capacity, order_count);
}

fn assertStorageShape(bitmap: anytype, unit_capacity: usize, order_count: u8) void {
    if (debug.checksEnabled()) {
        std.debug.assert(order_count > 0 and order_count <= 32);
        std.debug.assert(unit_capacity > 0);
        std.debug.assert(unit_capacity <= std.math.shr(usize, std.math.maxInt(usize), order_count - 1));
        const required = requiredWordCount(unit_capacity, order_count);
        std.debug.assert(bitmap.items.len >= required);
        std.debug.assert(bitmap.capacity() == required * Bitmap.Word.width);
        bitmap.assertValid();
    }
}

fn bitIsSet(bitmap: anytype, unit_capacity: usize, order: u8, slot: usize) bool {
    const word_index = orderWordOffset(unit_capacity, order) + slot / Bitmap.Word.width;
    return Bitmap.Word.isSet(bitmap.items[word_index], slot % Bitmap.Word.width);
}

fn setBit(bitmap: anytype, unit_capacity: usize, order: u8, slot: usize) void {
    const word_index = orderWordOffset(unit_capacity, order) + slot / Bitmap.Word.width;
    Bitmap.Word.set(&bitmap.items[word_index], slot % Bitmap.Word.width);
}

fn clearBit(bitmap: anytype, unit_capacity: usize, order: u8, slot: usize) void {
    const word_index = orderWordOffset(unit_capacity, order) + slot / Bitmap.Word.width;
    Bitmap.Word.clear(&bitmap.items[word_index], slot % Bitmap.Word.width);
}

fn findFirstFreeAtOrder(bitmap: anytype, unit_capacity: usize, order: u8) ?usize {
    const words = bitmap.words();
    const off = orderWordOffset(unit_capacity, order);
    const wc = wordsForOrder(unit_capacity, order);
    var wi: usize = 0;
    while (wi < wc) : (wi += 1) {
        const w = words[off + wi];
        if (w != 0) {
            const bit = @ctz(w);
            const slot = wi * Bitmap.Word.width + bit;
            std.debug.assert(slot < validSlotsFor(unit_capacity, order));
            return slot;
        }
    }
    return null;
}

fn installInitialDecomposition(bitmap: anytype, unit_capacity: usize, order_count: u8) void {
    if (unit_capacity == 0) return;

    assertStorageShape(bitmap, unit_capacity, order_count);

    var cursor: usize = 0;
    var k: u8 = order_count - 1;
    while (cursor < unit_capacity) {
        while (k > 0 and cursor + (@as(usize, 1) << @as(Shift, @intCast(k))) > unit_capacity) {
            k -= 1;
        }

        const size = @as(usize, 1) << @as(Shift, @intCast(k));

        std.debug.assert(cursor + size <= unit_capacity);
        std.debug.assert(cursor % size == 0);

        setBit(bitmap, unit_capacity, k, cursor >> @as(Shift, @intCast(k)));
        cursor += size;
    }
}

fn freeUnitsImpl(bitmap: anytype, unit_capacity: usize, order_count: u8) usize {
    const words = bitmap.words();
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
    bitmap: anytype,
    unit_capacity: usize,
    order_count: u8,
    block: BuddyBlock,
) bool {
    if (block.order >= order_count) return false;
    const size = @as(usize, 1) << @as(Shift, @intCast(block.order));

    if (block.start % size != 0) return false;
    const end = std.math.add(usize, block.start, size) catch return false;

    if (end > unit_capacity) {
        return false;
    }
    assertStorageShape(bitmap, unit_capacity, order_count);
    return bitIsSet(bitmap, unit_capacity, block.order, block.start >> @as(Shift, @intCast(block.order)));
}

fn allocImpl(
    bitmap: anytype,
    unit_capacity: usize,
    order_count: u8,
    order: u8,
) BuddyError!BuddyBlock {
    if (order >= order_count) {
        return error.InvalidOrder;
    }
    assertStorageShape(bitmap, unit_capacity, order_count);

    // Select the lowest-start free block. Break same-start ties by order.
    var best_start: usize = std.math.maxInt(usize);
    var best_order: u8 = 0;
    var found = false;

    var k: u8 = order;
    while (k < order_count) : (k += 1) {
        const slot = findFirstFreeAtOrder(bitmap, unit_capacity, k) orelse continue;
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
    clearBit(bitmap, unit_capacity, best_order, source_slot);

    var current: BuddyBlock = .{ .start = best_start, .order = best_order };
    while (current.order > order) {
        std.debug.assert(current.order > 0);
        const pair = buddy.split(current) catch unreachable;

        const right = pair[1];
        setBit(
            bitmap,
            unit_capacity,
            right.order,
            right.start >> @as(Shift, @intCast(right.order)),
        );

        current = pair[0];
    }

    if (debug.checksEnabled()) {
        const slot = current.start >> @as(Shift, @intCast(current.order));
        std.debug.assert(!bitIsSet(bitmap, unit_capacity, current.order, slot));
    }

    return current;
}

fn freeImpl(
    bitmap: anytype,
    unit_capacity: usize,
    order_count: u8,
    block: BuddyBlock,
) BuddyError!void {
    if (block.order >= order_count) return error.InvalidOrder;

    const size = @as(usize, 1) << @as(Shift, @intCast(block.order));
    const aligned = block.start % size == 0;
    if (debug.checksEnabled()) std.debug.assert(aligned);
    if (!aligned) return error.InvalidRequest;

    const end = std.math.add(usize, block.start, size) catch return error.InvalidRequest;
    if (end > unit_capacity) {
        return error.InvalidRequest;
    }
    assertStorageShape(bitmap, unit_capacity, order_count);

    const slot = block.start >> @as(Shift, @intCast(block.order));
    if (bitIsSet(bitmap, unit_capacity, block.order, slot)) {
        if (debug.checksEnabled()) std.debug.assert(false);
        return error.NotAllocated;
    }

    var current = block;
    while (current.order + 1 < order_count) {
        const sibling = buddy.buddyOf(current) catch break;
        const sibling_size = @as(usize, 1) << @as(Shift, @intCast(sibling.order));
        const sibling_end = std.math.add(usize, sibling.start, sibling_size) catch break;
        if (sibling_end > unit_capacity) break;

        const sibling_slot = sibling.start >> @as(Shift, @intCast(sibling.order));
        if (!bitIsSet(bitmap, unit_capacity, sibling.order, sibling_slot)) break;

        clearBit(bitmap, unit_capacity, sibling.order, sibling_slot);
        current = buddy.parentOf(current) catch break;
    }

    setBit(
        bitmap,
        unit_capacity,
        current.order,
        current.start >> @as(Shift, @intCast(current.order)),
    );

    if (debug.checksEnabled()) {
        std.debug.assert(!hasBothBuddiesFree(bitmap, unit_capacity, order_count));
    }
}

fn reserveImpl(
    bitmap: anytype,
    unit_capacity: usize,
    order_count: u8,
    range: RangeUsize,
) BuddyError!void {
    if (!range.isValid()) return error.InvalidRequest;
    if (range.isEmpty()) {
        if (range.start > unit_capacity) return error.OutOfBounds;
        return;
    }

    if (range.end > unit_capacity) {
        return error.OutOfBounds;
    }
    assertStorageShape(bitmap, unit_capacity, order_count);

    var probe: usize = range.start;
    while (probe < range.end) : (probe += 1) {
        if (containingFreeOrder(bitmap, unit_capacity, order_count, probe) == null) {
            return error.AlreadyAllocated;
        }
    }

    var u: usize = range.start;
    while (u < range.end) : (u += 1) {
        const k = containingFreeOrder(bitmap, unit_capacity, order_count, u).?;
        const size_k = @as(usize, 1) << @as(Shift, @intCast(k));
        const block_start = @divFloor(u, size_k) * size_k;

        clearBit(bitmap, unit_capacity, k, block_start >> @as(Shift, @intCast(k)));

        var current: BuddyBlock = .{ .start = block_start, .order = k };
        while (current.order > 0) {
            std.debug.assert(current.order > 0);

            const pair = buddy.split(current) catch unreachable;
            const left = pair[0];
            const right = pair[1];
            const left_end = left.start + (@as(usize, 1) << @as(Shift, @intCast(left.order)));
            if (u < left_end) {
                setBit(
                    bitmap,
                    unit_capacity,
                    right.order,
                    right.start >> @as(Shift, @intCast(right.order)),
                );
                current = left;
            } else {
                setBit(
                    bitmap,
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
    bitmap: anytype,
    unit_capacity: usize,
    order_count: u8,
    unit: usize,
) ?u8 {
    var k: u8 = 0;
    while (k < order_count) : (k += 1) {
        const size_k = @as(usize, 1) << @as(Shift, @intCast(k));
        const slot = @divFloor(unit, size_k);
        if (slot >= validSlotsFor(unit_capacity, k)) return null;
        if (bitIsSet(bitmap, unit_capacity, k, slot)) return k;
    }
    return null;
}

fn hasBothBuddiesFree(bitmap: anytype, unit_capacity: usize, order_count: u8) bool {
    if (order_count == 0) return false;

    var k: u8 = 0;
    while (k + 1 < order_count) : (k += 1) {
        const valid = validSlotsFor(unit_capacity, k);

        var pair: usize = 0;
        while (pair * 2 + 1 < valid) : (pair += 1) {
            const left = pair * 2;
            const right = left + 1;

            if (bitIsSet(bitmap, unit_capacity, k, left) and
                bitIsSet(bitmap, unit_capacity, k, right))
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
            const base = wi * Bitmap.Word.width;
            const w = words[off + wi];

            if (base >= valid) {
                if (w != 0) return true;
                continue;
            }

            const in_word = valid - base;
            if (in_word >= Bitmap.Word.width) {
                continue;
            }

            const high_mask = ~((@as(BuddyWord, 1) << @as(Bitmap.Word.Shift, @intCast(in_word))) - 1);
            if ((w & high_mask) != 0) return true;
        }
    }
    return false;
}

fn checkValid(bitmap: anytype, unit_capacity: usize, order_count: u8) bool {
    const words = bitmap.items[0..];
    const required = requiredWordCount(unit_capacity, order_count);
    if (hasUnusedHighBits(words, unit_capacity, order_count)) return false;
    for (words[required..]) |word| {
        if (word != 0) return false;
    }
    if (hasBothBuddiesFree(bitmap, unit_capacity, order_count)) return false;

    const free_units = freeUnitsImpl(bitmap, unit_capacity, order_count);
    if (free_units > unit_capacity) return false;
    return true;
}
