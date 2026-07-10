//! Fixed-capacity sorted range maps. See docs/specs/ranges/range-map.md.

const std = @import("std");

const core = @import("../core.zig");

fn requireRuntimeValue(comptime V: type) void {
    if (@sizeOf(V) == 0) @compileError("range map value type must have nonzero size");
}

pub const RangeMap = struct {
    pub fn Static(comptime T: type, comptime V: type, comptime capacity_entries: usize) type {
        comptime requireRuntimeValue(V);
        return struct {
            buffer: [capacity_entries]Entry = undefined,
            count: usize = 0,

            const Self = @This();

            pub const Range = core.Range(T);
            pub const Entry = struct {
                range: Range,
                value: V,
            };
            pub const Error = error{ Full, InvalidRange, Overlap };
            pub const entry_capacity = capacity_entries;

            pub fn init() Self {
                return .{};
            }

            pub fn len(self: *const Self) usize {
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return entry_capacity;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.len() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.len() == entry_capacity;
            }

            pub fn asConstSlice(self: *const Self) []const Entry {
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            /// `error.InvalidRange`: `range` is invalid.
            /// `error.Overlap`: `range` overlaps a stored entry.
            /// `error.Full`: disjoint insert needs a slot at capacity.
            /// Empty range is a no-op. Success invalidates prior pointers/slices.
            /// Error leaves map unchanged.
            pub fn insert(self: *Self, range: Range, value: V) Error!void {
                try insertEntry(Range, Entry, self.buffer[0..], &self.count, range, value);
            }

            /// `error.InvalidRange`: `range` is invalid.
            /// `error.Full`: final entry count would exceed capacity.
            /// Empty range is a no-op. Assignment never coalesces neighbors.
            /// Success invalidates prior pointers/slices; error leaves map unchanged.
            pub fn assign(self: *Self, range: Range, value: V) Error!void {
                try assignEntry(Range, Entry, self.buffer[0..], &self.count, range, value);
            }

            /// `error.InvalidRange`: `range` is invalid.
            /// `error.Full`: middle split needs a slot at capacity.
            /// Empty/disjoint ranges are no-ops; there is no `NotFound`.
            /// Success invalidates prior pointers/slices; error leaves map unchanged.
            pub fn remove(self: *Self, range: Range) Error!void {
                try removeEntry(Range, Entry, self.buffer[0..], &self.count, range);
            }

            pub fn coalesceAdjacent(self: *Self, context: anytype, comptime eql: core.Eql(@TypeOf(context), V)) void {
                coalesceEntry(Range, Entry, V, self.buffer[0..], &self.count, context, eql);
            }

            pub fn contains(self: *const Self, value: T) bool {
                return self.findContaining(value) != null;
            }

            /// Returned pointer aliases the stored value and is invalidated by any
            /// mutation, move, or `clearRetainingCapacity`.
            pub fn get(self: *const Self, value: T) ?*const V {
                const entry = self.findContaining(value) orelse return null;
                return &entry.value;
            }

            /// Precondition: `range.isValid()`. Adjacent entries count as continuous
            /// coverage even with differing values. Empty ranges follow boundary
            /// containment on mapped entries, never gaps.
            pub fn containsRange(self: *const Self, range: Range) bool {
                return containsMappedRange(Range, Entry, self.asConstSlice(), range);
            }

            /// Precondition: `range.isValid()`.
            /// Empty ranges never overlap. Non-empty ranges need a stored-entry intersection.
            pub fn overlaps(self: *const Self, range: Range) bool {
                return self.findIntersecting(range) != null;
            }

            /// Returned pointer aliases stored storage and is invalidated by any
            /// mutation, move, or `clearRetainingCapacity`.
            pub fn findContaining(self: *const Self, value: T) ?*const Entry {
                return findContainingEntry(Range, Entry, self.asConstSlice(), value);
            }

            /// Precondition: `range.isValid()`.
            /// Returns the first ascending entry whose range intersects `range`, or `null`
            /// when no stored entry intersects. Empty ranges yield `null`.
            /// The returned pointer is invalidated by mutation, move, or `clearRetainingCapacity`.
            pub fn findIntersecting(self: *const Self, range: Range) ?*const Entry {
                return findIntersectingEntry(Range, Entry, self.asConstSlice(), range);
            }

            pub fn assertValid(self: *const Self) void {
                assertEntries(Range, Entry, self.buffer[0..], self.count);
            }
        };
    }

    pub fn Bounded(comptime T: type, comptime V: type) type {
        comptime requireRuntimeValue(V);
        return struct {
            buffer: []Entry,
            count: usize = 0,

            const Self = @This();

            pub const Range = core.Range(T);
            pub const Entry = struct {
                range: Range,
                value: V,
            };
            pub const Error = error{ Full, InvalidRange, Overlap };

            pub fn wrap(buffer: []Entry) Self {
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

            pub fn asConstSlice(self: *const Self) []const Entry {
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            /// `error.InvalidRange`: `range` is invalid.
            /// `error.Overlap`: `range` overlaps a stored entry.
            /// `error.Full`: disjoint insert needs a slot at capacity.
            /// Empty range is a no-op. Success invalidates prior pointers/slices.
            /// Error leaves map unchanged.
            pub fn insert(self: *Self, range: Range, value: V) Error!void {
                try insertEntry(Range, Entry, self.buffer, &self.count, range, value);
            }

            /// `error.InvalidRange`: `range` is invalid.
            /// `error.Full`: final entry count would exceed capacity.
            /// Empty range is a no-op. Assignment never coalesces neighbors.
            /// Success invalidates prior pointers/slices; error leaves map unchanged.
            pub fn assign(self: *Self, range: Range, value: V) Error!void {
                try assignEntry(Range, Entry, self.buffer, &self.count, range, value);
            }

            /// `error.InvalidRange`: `range` is invalid.
            /// `error.Full`: middle split needs a slot at capacity.
            /// Empty/disjoint ranges are no-ops; there is no `NotFound`.
            /// Success invalidates prior pointers/slices; error leaves map unchanged.
            pub fn remove(self: *Self, range: Range) Error!void {
                try removeEntry(Range, Entry, self.buffer, &self.count, range);
            }

            pub fn coalesceAdjacent(self: *Self, context: anytype, comptime eql: core.Eql(@TypeOf(context), V)) void {
                coalesceEntry(Range, Entry, V, self.buffer, &self.count, context, eql);
            }

            pub fn contains(self: *const Self, value: T) bool {
                return self.findContaining(value) != null;
            }

            /// Returned pointer aliases the stored value and is invalidated by any
            /// mutation, move, or `clearRetainingCapacity`.
            pub fn get(self: *const Self, value: T) ?*const V {
                const entry = self.findContaining(value) orelse return null;
                return &entry.value;
            }

            /// Precondition: `range.isValid()`. Adjacent entries count as continuous
            /// coverage even with differing values. Empty ranges follow boundary
            /// containment on mapped entries, never gaps.
            pub fn containsRange(self: *const Self, range: Range) bool {
                return containsMappedRange(Range, Entry, self.asConstSlice(), range);
            }

            /// Precondition: `range.isValid()`.
            /// Empty ranges never overlap. Non-empty ranges need a stored-entry intersection.
            pub fn overlaps(self: *const Self, range: Range) bool {
                return self.findIntersecting(range) != null;
            }

            /// Returned pointer aliases stored storage and is invalidated by any
            /// mutation, move, or `clearRetainingCapacity`.
            pub fn findContaining(self: *const Self, value: T) ?*const Entry {
                return findContainingEntry(Range, Entry, self.asConstSlice(), value);
            }

            /// Precondition: `range.isValid()`.
            /// Returns the first ascending entry whose range intersects `range`, or `null`
            /// when no stored entry intersects. Empty ranges yield `null`.
            /// The returned pointer is invalidated by mutation, move, or `clearRetainingCapacity`.
            pub fn findIntersecting(self: *const Self, range: Range) ?*const Entry {
                return findIntersectingEntry(Range, Entry, self.asConstSlice(), range);
            }

            pub fn assertValid(self: *const Self) void {
                assertEntries(Range, Entry, self.buffer, self.count);
            }
        };
    }
};

fn insertEntry(
    comptime Range: type,
    comptime Entry: type,
    buffer: []Entry,
    count: *usize,
    range: Range,
    value: anytype,
) error{ Full, InvalidRange, Overlap }!void {
    if (!range.isValid()) return error.InvalidRange;
    if (range.isEmpty()) return;

    var index: usize = 0;
    while (index < count.* and buffer[index].range.end <= range.start) : (index += 1) {}
    if (index < count.* and buffer[index].range.start < range.end) return error.Overlap;
    if (count.* == buffer.len) return error.Full;

    std.mem.copyBackwards(Entry, buffer[index + 1 .. count.* + 1], buffer[index..count.*]);
    buffer[index] = .{ .range = range, .value = value };
    count.* += 1;
}

fn assignEntry(
    comptime Range: type,
    comptime Entry: type,
    buffer: []Entry,
    count: *usize,
    range: Range,
    value: anytype,
) error{ Full, InvalidRange, Overlap }!void {
    if (!range.isValid()) return error.InvalidRange;
    if (range.isEmpty()) return;

    const final_count = assignedCount(Range, Entry, buffer[0..count.*], range);
    if (final_count > buffer.len) return error.Full;

    std.debug.assert(range.isValid());
    std.debug.assert(!range.isEmpty());
    std.debug.assert(final_count <= buffer.len);

    removeEntry(Range, Entry, buffer, count, range) catch unreachable;
    insertEntry(Range, Entry, buffer, count, range, value) catch unreachable;
}

fn assignedCount(
    comptime Range: type,
    comptime Entry: type,
    entries: []const Entry,
    range: Range,
) usize {
    var result: usize = 1;
    for (entries) |entry| {
        if (entry.range.overlaps(range)) {
            if (entry.range.start < range.start) result += 1;
            if (range.end < entry.range.end) result += 1;
        } else {
            result += 1;
        }
    }
    return result;
}

fn removeEntry(
    comptime Range: type,
    comptime Entry: type,
    buffer: []Entry,
    count: *usize,
    range: Range,
) error{ Full, InvalidRange, Overlap }!void {
    if (!range.isValid()) return error.InvalidRange;
    if (range.isEmpty()) return;

    if (count.* == buffer.len) {
        for (buffer[0..count.*]) |entry| {
            if (entry.range.start < range.start and range.end < entry.range.end) return error.Full;
        }
    }

    var i: usize = 0;
    while (i < count.*) {
        const entry = buffer[i];
        switch (classify(Range, entry.range, range)) {
            .disjoint => i += 1,
            .covers => {
                std.mem.copyForwards(Entry, buffer[i .. count.* - 1], buffer[i + 1 .. count.*]);
                count.* -= 1;
            },
            .trim_left => {
                buffer[i].range.start = range.end;
                i += 1;
            },
            .trim_right => {
                buffer[i].range.end = range.start;
                i += 1;
            },
            .split => {
                const tail = Entry{
                    .range = Range{ .start = range.end, .end = entry.range.end },
                    .value = entry.value,
                };
                buffer[i].range.end = range.start;
                std.mem.copyBackwards(Entry, buffer[i + 2 .. count.* + 1], buffer[i + 1 .. count.*]);
                buffer[i + 1] = tail;
                count.* += 1;
                i += 2;
            },
        }
    }
}

fn coalesceEntry(
    comptime Range: type,
    comptime Entry: type,
    comptime V: type,
    buffer: []Entry,
    count: *usize,
    context: anytype,
    comptime eql: core.Eql(@TypeOf(context), V),
) void {
    _ = Range;
    var i: usize = 0;
    while (i + 1 < count.*) {
        if (buffer[i].range.end == buffer[i + 1].range.start and eql(context, &buffer[i].value, &buffer[i + 1].value)) {
            buffer[i].range.end = buffer[i + 1].range.end;
            std.mem.copyForwards(Entry, buffer[i + 1 .. count.* - 1], buffer[i + 2 .. count.*]);
            count.* -= 1;
        } else {
            i += 1;
        }
    }
}

fn findContainingEntry(
    comptime Range: type,
    comptime Entry: type,
    entries: []const Entry,
    value: anytype,
) ?*const Entry {
    _ = Range;
    var low: usize = 0;
    var high: usize = entries.len;
    while (low < high) {
        const mid = low + @divFloor(high - low, 2);
        if (value < entries[mid].range.start) {
            high = mid;
        } else if (value >= entries[mid].range.end) {
            low = mid + 1;
        } else {
            return &entries[mid];
        }
    }
    return null;
}

fn containsMappedRange(comptime Range: type, comptime Entry: type, entries: []const Entry, range: Range) bool {
    std.debug.assert(range.isValid());
    if (range.isEmpty()) return containsEmptyBoundary(Range, Entry, entries, range.start);

    const first = findContainingEntry(Range, Entry, entries, range.start) orelse return false;
    var covered_end = first.range.end;
    if (covered_end >= range.end) return true;

    var index = @divExact(@intFromPtr(first) - @intFromPtr(entries.ptr), @sizeOf(Entry)) + 1;
    while (index < entries.len and entries[index].range.start <= covered_end) : (index += 1) {
        covered_end = entries[index].range.end;
        if (covered_end >= range.end) return true;
    }
    return false;
}

fn containsEmptyBoundary(
    comptime Range: type,
    comptime Entry: type,
    entries: []const Entry,
    point: anytype,
) bool {
    _ = Range;
    for (entries) |entry| {
        if (entry.range.start <= point and point <= entry.range.end) return true;
        if (point < entry.range.start) return false;
    }
    return false;
}

fn findIntersectingEntry(
    comptime Range: type,
    comptime Entry: type,
    entries: []const Entry,
    range: Range,
) ?*const Entry {
    std.debug.assert(range.isValid());
    if (range.isEmpty()) return null;
    var low: usize = 0;
    var high: usize = entries.len;
    while (low < high) {
        const mid = low + @divFloor(high - low, 2);
        if (entries[mid].range.end <= range.start) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    if (low < entries.len and entries[low].range.start < range.end) return &entries[low];
    return null;
}

fn assertEntries(comptime Range: type, comptime Entry: type, buffer: []const Entry, count: usize) void {
    _ = Range;
    std.debug.assert(count <= buffer.len);
    var previous: ?Entry = null;
    for (buffer[0..count]) |entry| {
        std.debug.assert(entry.range.isValid());
        std.debug.assert(!entry.range.isEmpty());
        if (previous) |prev| std.debug.assert(prev.range.end <= entry.range.start);

        previous = entry;
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
