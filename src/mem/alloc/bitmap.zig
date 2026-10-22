//! Fixed-unit bitmap allocators over `u64`-word storage with lowest-index
//! first-fit placement.
//! See `docs/specs/mem/alloc/bitmap.md`.

const std = @import("std");
const debug = @import("core").debug;

const Bitmap = @import("bits").Set(u64);
const RangeUsize = @import("core").Range(usize);

pub const BitmapAllocator = struct {
    pub fn Static(comptime capacity_units: usize) type {
        comptime if (capacity_units == 0) @compileError("BitmapAllocator.Static capacity_units must be non-zero");

        return struct {
            bitmap: Bitmap.Static(capacity_units) = .{},

            const Self = @This();

            pub const Word = u64;
            pub const Range = RangeUsize;

            pub const Error = BitmapAllocator.Bounded.Error;
            pub const AllocError = BitmapAllocator.Bounded.AllocError;
            pub const ReserveError = BitmapAllocator.Bounded.ReserveError;
            pub const FreeError = BitmapAllocator.Bounded.FreeError;

            pub const word_bits = Bitmap.Word.width;
            pub const unit_capacity = capacity_units;
            pub const word_count = Bitmap.Static(capacity_units).init().words().len;

            pub fn init() Self {
                return .{};
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return unit_capacity;
            }

            pub fn allocated(self: *const Self) usize {
                return self.bitmap.count();
            }

            pub fn remaining(self: *const Self) usize {
                return unit_capacity - self.allocated();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.allocated() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.allocated() == unit_capacity;
            }

            /// Returns false when `index` is out of bounds.
            pub fn isAllocated(self: *const Self, index: usize) bool {
                return self.bitmap.isSet(index);
            }

            /// Returns false when `index` is out of bounds.
            pub fn isFree(self: *const Self, index: usize) bool {
                if (index >= unit_capacity) {
                    return false;
                }
                return !self.bitmap.isSet(index);
            }

            /// Allocates the lowest free unit.
            pub fn allocOne(self: *Self) AllocError!usize {
                return allocOneImpl(&self.bitmap);
            }

            /// Allocates the lowest contiguous free range.
            /// `count == 0` does not mutate.
            pub fn allocRange(self: *Self, count: usize) AllocError!Range {
                return allocRangeImpl(&self.bitmap, count);
            }

            /// Leaves the bitmap unchanged on error.
            pub fn reserveOne(self: *Self, index: usize) ReserveError!void {
                return reserveOneImpl(&self.bitmap, index);
            }

            /// Requires a valid `range`.
            /// An empty in-bounds range is a no-op; errors do not mutate.
            pub fn reserveRange(self: *Self, range: Range) ReserveError!void {
                return reserveRangeImpl(&self.bitmap, range);
            }

            pub fn freeOne(self: *Self, index: usize) FreeError!void {
                return freeOneImpl(&self.bitmap, index);
            }

            /// Requires a valid `range`.
            /// An empty in-bounds range is a no-op; errors do not mutate.
            pub fn freeRange(self: *Self, range: Range) FreeError!void {
                return freeRangeImpl(&self.bitmap, range);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.bitmap.clearRetainingCapacity();
            }

            pub fn isValid(self: *const Self) bool {
                return checkValid(&self.bitmap);
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
            }
        };
    }

    /// Borrows `words`; they must outlive the allocator.
    pub const Bounded = struct {
        bitmap: Bitmap.Bounded,

        pub const Word = u64;
        pub const Range = RangeUsize;

        pub const word_bits = Bitmap.Word.width;

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
            return .{ .bitmap = try Bitmap.Bounded.wrap(words, unit_capacity) };
        }

        pub fn capacity(self: *const Bounded) usize {
            return self.bitmap.capacity();
        }

        pub fn allocated(self: *const Bounded) usize {
            return self.bitmap.count();
        }

        pub fn remaining(self: *const Bounded) usize {
            return self.capacity() - self.allocated();
        }

        pub fn isEmpty(self: *const Bounded) bool {
            return self.allocated() == 0;
        }

        pub fn isFull(self: *const Bounded) bool {
            return self.allocated() == self.capacity();
        }

        pub fn isAllocated(self: *const Bounded, index: usize) bool {
            return self.bitmap.isSet(index);
        }

        pub fn isFree(self: *const Bounded, index: usize) bool {
            if (index >= self.capacity()) {
                return false;
            }
            return !self.bitmap.isSet(index);
        }

        pub fn allocOne(self: *Bounded) AllocError!usize {
            return allocOneImpl(&self.bitmap);
        }

        pub fn allocRange(self: *Bounded, count: usize) AllocError!Range {
            return allocRangeImpl(&self.bitmap, count);
        }

        pub fn reserveOne(self: *Bounded, index: usize) ReserveError!void {
            return reserveOneImpl(&self.bitmap, index);
        }

        /// Requires a valid `range`.
        /// An empty in-bounds range is a no-op; errors do not mutate.
        pub fn reserveRange(self: *Bounded, range: Range) ReserveError!void {
            return reserveRangeImpl(&self.bitmap, range);
        }

        pub fn freeOne(self: *Bounded, index: usize) FreeError!void {
            return freeOneImpl(&self.bitmap, index);
        }

        /// Requires a valid `range`.
        /// An empty in-bounds range is a no-op; errors do not mutate.
        pub fn freeRange(self: *Bounded, range: Range) FreeError!void {
            return freeRangeImpl(&self.bitmap, range);
        }

        pub fn clearRetainingCapacity(self: *Bounded) void {
            self.bitmap.clearRetainingCapacity();
        }

        pub fn isValid(self: *const Bounded) bool {
            return checkValid(&self.bitmap);
        }

        pub fn assertValid(self: *const Bounded) void {
            std.debug.assert(self.isValid());
        }
    };
};

const BitmapAllocError = BitmapAllocator.Bounded.AllocError;
const BitmapReserveError = BitmapAllocator.Bounded.ReserveError;
const BitmapFreeError = BitmapAllocator.Bounded.FreeError;

fn findFirstFreeRun(bitmap: anytype, count: usize) ?usize {
    const words = bitmap.words();
    var run_start: usize = 0;
    var run_len: usize = 0;
    for (0..bitmap.capacity()) |index| {
        const occupied = Bitmap.Word.isSet(words[index / Bitmap.Word.width], index % Bitmap.Word.width);
        if (!occupied) {
            if (run_len == 0) {
                run_start = index;
            }
            run_len += 1;
            if (run_len == count) {
                return run_start;
            }
        } else {
            run_len = 0;
        }
    }
    return null;
}

fn allocOneImpl(bitmap: anytype) BitmapAllocError!usize {
    const index = bitmap.firstUnset() orelse return error.OutOfMemory;
    Bitmap.Word.set(&bitmap.items[index / Bitmap.Word.width], index % Bitmap.Word.width);
    return index;
}

fn allocRangeImpl(bitmap: anytype, count: usize) BitmapAllocError!RangeUsize {
    if (count == 0) {
        return RangeUsize.empty(0);
    }
    if (count > bitmap.capacity()) {
        return error.OutOfMemory;
    }

    if (debug.checksEnabled()) {
        bitmap.assertValid();
    }

    const start = findFirstFreeRun(bitmap, count) orelse return error.OutOfMemory;
    for (start..start + count) |index| {
        Bitmap.Word.set(&bitmap.items[index / Bitmap.Word.width], index % Bitmap.Word.width);
    }
    return RangeUsize.init(start, start + count) catch unreachable;
}

fn reserveOneImpl(bitmap: anytype, index: usize) BitmapReserveError!void {
    if (try bitmap.set(index)) {
        return error.AlreadyAllocated;
    }
}

fn reserveRangeImpl(bitmap: anytype, range: RangeUsize) BitmapReserveError!void {
    range.assertValid();
    if (range.end > bitmap.capacity()) {
        return error.OutOfBounds;
    }
    if (!range.isEmpty() and debug.checksEnabled()) {
        bitmap.assertValid();
    }

    for (range.start..range.end) |index| {
        if (Bitmap.Word.isSet(bitmap.items[index / Bitmap.Word.width], index % Bitmap.Word.width)) {
            return error.AlreadyAllocated;
        }
    }
    for (range.start..range.end) |index| {
        Bitmap.Word.set(&bitmap.items[index / Bitmap.Word.width], index % Bitmap.Word.width);
    }
}

fn freeOneImpl(bitmap: anytype, index: usize) BitmapFreeError!void {
    if (!(try bitmap.unset(index))) {
        return error.NotAllocated;
    }
}

fn freeRangeImpl(bitmap: anytype, range: RangeUsize) BitmapFreeError!void {
    range.assertValid();
    if (range.end > bitmap.capacity()) {
        return error.OutOfBounds;
    }
    if (!range.isEmpty() and debug.checksEnabled()) {
        bitmap.assertValid();
    }

    for (range.start..range.end) |index| {
        if (!Bitmap.Word.isSet(bitmap.items[index / Bitmap.Word.width], index % Bitmap.Word.width)) {
            return error.NotAllocated;
        }
    }
    for (range.start..range.end) |index| {
        Bitmap.Word.clear(&bitmap.items[index / Bitmap.Word.width], index % Bitmap.Word.width);
    }
}

fn checkValid(bitmap: anytype) bool {
    const capacity = bitmap.capacity();
    const words = bitmap.items[0..];
    const word_count = capacity / Bitmap.Word.width + @intFromBool(capacity % Bitmap.Word.width != 0);
    if (word_count > words.len) {
        return false;
    }
    const remainder = capacity % Bitmap.Word.width;
    if (word_count > 0 and remainder != 0) {
        const last_mask = Bitmap.Word.maskOf(remainder) - 1;
        if (words[word_count - 1] & ~last_mask != 0) {
            return false;
        }
    }
    for (words[word_count..]) |word| {
        if (word != 0) {
            return false;
        }
    }
    return true;
}
