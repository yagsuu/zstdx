//! Fixed-capacity canonical range sets. See `docs/specs/ranges/set.md`.

const std = @import("std");

const core = @import("../core.zig");

pub const RangeSet = struct {
    pub fn Static(comptime T: type, comptime capacity_ranges: usize) type {
        comptime if (capacity_ranges == 0) @compileError("RangeSet.Static capacity_ranges must be non-zero");

        return struct {
            buffer: [capacity_ranges]Range = undefined,
            count: usize = 0,

            const Self = @This();

            pub const Range = core.Range(T);
            pub const Error = error{ Full, InvalidRange };
            pub const range_capacity = capacity_ranges;

            pub fn init() Self {
                return .{};
            }

            pub fn len(self: *const Self) usize {
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return range_capacity;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.len() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.len() == range_capacity;
            }

            pub fn asConstSlice(self: *const Self) []const Range {
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            /// `error.InvalidRange`: `range` is invalid.
            /// `error.Full`: The canonical result would exceed capacity.
            /// An empty range is a no-op. On success, prior slices are invalid. On error, the set is unchanged.
            pub fn insert(self: *Self, range: Range) Error!void {
                try insertRange(Range, self.buffer[0..], &self.count, range);
            }

            /// `error.InvalidRange`: `range` is invalid.
            /// `error.Full`: A middle split needs a slot at capacity.
            /// Empty or disjoint ranges are no-ops. On success, prior slices are invalid. On error, the set is unchanged.
            pub fn remove(self: *Self, range: Range) Error!void {
                try removeRange(Range, self.buffer[0..], &self.count, range);
            }

            pub fn contains(self: *const Self, value: T) bool {
                return self.findContaining(value) != null;
            }

            /// Precondition: `range.isValid()`. Empty ranges follow `Range`
            /// boundary containment: inside stored ranges or on boundaries, never gaps.
            pub fn containsRange(self: *const Self, range: Range) bool {
                return containsRangeInSlice(Range, self.asConstSlice(), range);
            }

            /// Precondition: `range.isValid()`.
            /// Empty ranges never overlap. Non-empty ranges need a stored intersection.
            pub fn overlaps(self: *const Self, range: Range) bool {
                return self.findIntersecting(range) != null;
            }

            pub fn findContaining(self: *const Self, value: T) ?Range {
                return findContainingValue(Range, self.asConstSlice(), value);
            }

            /// Precondition: `range.isValid()`.
            /// Returns the first non-empty intersection in ascending order, or `null` if no stored range intersects.
            /// Empty ranges yield `null`. The returned range is a value copy and remains valid after a mutation,
            /// move, or `clearRetainingCapacity`.
            pub fn findIntersecting(self: *const Self, range: Range) ?Range {
                return findIntersectingRange(Range, self.asConstSlice(), range);
            }

            pub fn assertValid(self: *const Self) void {
                assertCanonical(Range, self.buffer[0..], self.count);
            }
        };
    }

    pub fn Bounded(comptime T: type) type {
        return struct {
            buffer: []Range,
            count: usize = 0,

            const Self = @This();

            pub const Range = core.Range(T);
            pub const Error = error{ Full, InvalidRange };

            pub fn wrap(buffer: []Range) Self {
                return .{ .buffer = buffer };
            }

            pub fn len(self: *const Self) usize {
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                return self.buffer.len;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.len() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.len() == self.capacity();
            }

            pub fn asConstSlice(self: *const Self) []const Range {
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            /// `error.InvalidRange`: `range` is invalid.
            /// `error.Full`: The canonical result would exceed capacity.
            /// An empty range is a no-op. On success, prior slices are invalid. On error, the set is unchanged.
            pub fn insert(self: *Self, range: Range) Error!void {
                try insertRange(Range, self.buffer, &self.count, range);
            }

            /// `error.InvalidRange`: `range` is invalid.
            /// `error.Full`: A middle split needs a slot at capacity.
            /// Empty or disjoint ranges are no-ops. On success, prior slices are invalid. On error, the set is unchanged.
            pub fn remove(self: *Self, range: Range) Error!void {
                try removeRange(Range, self.buffer, &self.count, range);
            }

            pub fn contains(self: *const Self, value: T) bool {
                return self.findContaining(value) != null;
            }

            /// Precondition: `range.isValid()`. Empty ranges follow `Range`
            /// boundary containment: inside stored ranges or on boundaries, never gaps.
            pub fn containsRange(self: *const Self, range: Range) bool {
                return containsRangeInSlice(Range, self.asConstSlice(), range);
            }

            /// Precondition: `range.isValid()`.
            /// Empty ranges never overlap. Non-empty ranges need a stored intersection.
            pub fn overlaps(self: *const Self, range: Range) bool {
                return self.findIntersecting(range) != null;
            }

            pub fn findContaining(self: *const Self, value: T) ?Range {
                return findContainingValue(Range, self.asConstSlice(), value);
            }

            /// Precondition: `range.isValid()`.
            /// Returns the first non-empty intersection in ascending order, or `null` if no stored range intersects.
            /// Empty ranges yield `null`. The returned range is a value copy and remains valid after a mutation,
            /// move, or `clearRetainingCapacity`.
            pub fn findIntersecting(self: *const Self, range: Range) ?Range {
                return findIntersectingRange(Range, self.asConstSlice(), range);
            }

            pub fn assertValid(self: *const Self) void {
                assertCanonical(Range, self.buffer, self.count);
            }
        };
    }
};

fn insertRange(comptime Range: type, buffer: []Range, count: *usize, range: Range) error{ Full, InvalidRange }!void {
    if (!range.isValid()) return error.InvalidRange;
    if (range.isEmpty()) return;

    var merged = range;
    var first: usize = 0;
    while (first < count.* and buffer[first].end < merged.start) : (first += 1) {}

    var last = first;
    while (last < count.* and buffer[last].start <= merged.end) : (last += 1) {
        merged = merged.span(buffer[last]);
    }

    const removed = last - first;
    const new_count = count.* - removed + 1;
    if (new_count > buffer.len) return error.Full;

    if (removed == 0) {
        std.mem.copyBackwards(Range, buffer[first + 1 .. count.* + 1], buffer[first..count.*]);
        buffer[first] = merged;
    } else {
        buffer[first] = merged;
        if (last < count.*) {
            std.mem.copyForwards(Range, buffer[first + 1 .. new_count], buffer[last..count.*]);
        }
    }
    count.* = new_count;
}

fn removeRange(comptime Range: type, buffer: []Range, count: *usize, range: Range) error{ Full, InvalidRange }!void {
    if (!range.isValid()) return error.InvalidRange;
    if (range.isEmpty()) return;

    if (count.* == buffer.len) {
        for (buffer[0..count.*]) |stored| {
            if (stored.start < range.start and range.end < stored.end) return error.Full;
        }
    }

    var i: usize = 0;
    while (i < count.*) {
        const stored = buffer[i];
        switch (classify(Range, stored, range)) {
            .disjoint => i += 1,
            .covers => {
                std.mem.copyForwards(Range, buffer[i .. count.* - 1], buffer[i + 1 .. count.*]);
                count.* -= 1;
            },
            .trim_left => {
                buffer[i].start = range.end;
                i += 1;
            },
            .trim_right => {
                buffer[i].end = range.start;
                i += 1;
            },
            .split => {
                const tail = Range{ .start = range.end, .end = stored.end };
                buffer[i].end = range.start;
                std.mem.copyBackwards(Range, buffer[i + 2 .. count.* + 1], buffer[i + 1 .. count.*]);
                buffer[i + 1] = tail;
                count.* += 1;
                i += 2;
            },
        }
    }
}

fn findContainingValue(comptime Range: type, ranges: []const Range, value: anytype) ?Range {
    var low: usize = 0;
    var high: usize = ranges.len;
    while (low < high) {
        const mid = low + @divFloor(high - low, 2);
        if (value < ranges[mid].start) {
            high = mid;
        } else if (value >= ranges[mid].end) {
            low = mid + 1;
        } else {
            return ranges[mid];
        }
    }
    return null;
}

fn containsRangeInSlice(comptime Range: type, ranges: []const Range, range: Range) bool {
    std.debug.assert(range.isValid());

    if (range.isEmpty()) return containsEmptyBoundary(Range, ranges, range.start);
    const containing = findContainingValue(Range, ranges, range.start) orelse return false;
    return containing.end >= range.end;
}

fn containsEmptyBoundary(comptime Range: type, ranges: []const Range, point: anytype) bool {
    for (ranges) |range| {
        if (range.start <= point and point <= range.end) return true;
        if (point < range.start) return false;
    }
    return false;
}

fn findIntersectingRange(comptime Range: type, ranges: []const Range, range: Range) ?Range {
    std.debug.assert(range.isValid());

    if (range.isEmpty()) return null;
    var low: usize = 0;
    var high: usize = ranges.len;
    while (low < high) {
        const mid = low + @divFloor(high - low, 2);
        if (ranges[mid].end <= range.start) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    if (low < ranges.len and ranges[low].start < range.end) return ranges[low];
    return null;
}

fn assertCanonical(comptime Range: type, buffer: []const Range, count: usize) void {
    std.debug.assert(count <= buffer.len);

    var previous: ?Range = null;
    for (buffer[0..count]) |range| {
        std.debug.assert(range.isValid());
        std.debug.assert(!range.isEmpty());
        if (previous) |prev| std.debug.assert(prev.end < range.start);

        previous = range;
    }
}

const Topology = enum { disjoint, covers, trim_left, trim_right, split };

fn classify(comptime Range: type, stored: Range, range: Range) Topology {
    if (!stored.overlaps(range)) return .disjoint;
    if (range.start <= stored.start and range.end >= stored.end) return .covers;
    if (range.start <= stored.start) return .trim_left;
    if (range.end >= stored.end) return .trim_right;
    return .split;
}
